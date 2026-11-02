"""Run the bundled model on labeled, continuous PCM16 phone recordings.

No training, resampling, padding, or threshold selection is performed.
Output contains signal statistics and probabilities, never PCM or GPS.
Requires an existing environment with NumPy and TensorFlow.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time
import wave

import numpy as np

LABELS = ("no_violence", "physical_violence", "verbal_violence")
RATE = 16000
WINDOW = RATE * 5
MINIMUM_CENTERED_RMS = 1 / 32768


def read_manifest(path, split):
    manifest = json.loads(path.read_text(encoding="utf-8"))
    recordings = [r for r in manifest["recordings"] if r["split"] == split]
    if not recordings:
        raise ValueError(f"No recordings for split={split}")
    ids = [r["id"] for r in recordings]
    if len(set(ids)) != len(ids):
        raise ValueError("Recording IDs must be unique")
    return recordings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--split", required=True, choices=("validation", "test"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--inference-stride-seconds", type=int, default=1,
                        help="Use >1 to simulate skipped classifications on slower phones")
    args = parser.parse_args()
    if args.inference_stride_seconds < 1:
        parser.error("inference-stride-seconds must be >=1")
    recordings = read_manifest(args.manifest, args.split)
    # Validate everything before creating the output or importing the runtime.
    decoded = []
    for recording in recordings:
        path = (args.manifest.resolve().parent / recording["path"]).resolve()
        with wave.open(str(path), "rb") as wav:
            if (wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getcomptype()) != (RATE, 1, 2, "NONE"):
                raise ValueError(f"{recording['id']}: requires uncompressed mono PCM16 WAV at 16000 Hz")
            sample_count = wav.getnframes()
        if not sample_count:
            raise ValueError(f"{recording['id']}: empty WAV")
        for event in recording["events"]:
            if event["label"] not in LABELS[1:] or not 0 <= event["start_seconds"] < event["end_seconds"] <= sample_count / RATE:
                raise ValueError(f"{recording['id']}: invalid event annotation")
        decoded.append((recording, path, sample_count))

    import tensorflow as tf
    root = Path(__file__).resolve().parent.parent
    model = root / "assets/models/model.tflite"
    interpreter = tf.lite.Interpreter(model_path=str(model), num_threads=2)
    inputs = interpreter.get_input_details()
    pcm = next(t for t in inputs if t["name"] == "serving_default_pcm:0")
    lengths = next(t for t in inputs if t["name"] == "serving_default_valid_samples:0")
    interpreter.resize_tensor_input(pcm["index"], [1, WINDOW], strict=True)
    interpreter.resize_tensor_input(lengths["index"], [1], strict=True)
    interpreter.allocate_tensors()
    output = interpreter.get_output_details()[0]
    if output["shape"].tolist() != [1, 3]:
        raise ValueError("Unexpected model output shape")
    with args.output.open("w", encoding="utf-8") as destination:
        def emit(row):
            destination.write(json.dumps(row, allow_nan=False) + "\n")
        emit({"type": "model", "sha256": hashlib.sha256(model.read_bytes()).hexdigest(),
              "split": args.split, "sample_rate": RATE, "window_samples": WINDOW,
              "inference_stride_seconds": args.inference_stride_seconds,
              "minimum_centered_rms": MINIMUM_CENTERED_RMS,
              "runtime": "host TensorFlow " + tf.__version__, "phone_runtime_validated": False})
        for recording, path, sample_count in decoded:
            with wave.open(str(path), 'rb') as wav:
                raw = wav.readframes(wav.getnframes())
            samples = np.frombuffer(raw, dtype='<i2').astype(np.float32) / 32768
            if len(samples) != sample_count:
                raise ValueError('Recording changed during evaluation')
            digest = hashlib.sha256(raw).hexdigest()
            emit({"type": "recording", "id": recording["id"], "samples": len(samples),
                  "pcm_sha256": digest, "events": recording["events"]})
            ends = list(range(WINDOW, len(samples) + 1, RATE))
            if ends and ends[-1] != len(samples):
                ends.append(len(samples))  # same final PCM flush as the app
            last_inferred = None
            for end in ends:
                window = samples[end - WINDOW:end]
                rms = float(np.std(window.astype(np.float64)))
                fresh = last_inferred is None or end - last_inferred >= args.inference_stride_seconds * RATE
                scores = None
                elapsed = None
                if fresh and rms > MINIMUM_CENTERED_RMS:
                    interpreter.set_tensor(pcm["index"], window.reshape(1, WINDOW))
                    interpreter.set_tensor(lengths["index"], np.array([WINDOW], dtype=np.int32))
                    start = time.perf_counter()
                    interpreter.invoke()
                    elapsed = (time.perf_counter() - start) * 1000
                    values = interpreter.get_tensor(output["index"])[0]
                    if not np.isfinite(values).all() or (values < 0).any() or (values > 1).any() or abs(float(values.sum()) - 1) > 1e-3:
                        raise ValueError("Invalid model probabilities")
                    scores = dict(zip(LABELS, map(float, values)))
                    last_inferred = end
                emit({"type": "window", "id": recording["id"], "end_sample": end,
                      "centered_rms": rms, "signal_finite": True,
                      "scores": scores, "host_invoke_ms": elapsed})
            print(f"{recording['id']}: {len(ends)} windows", flush=True)


if __name__ == "__main__":
    main()
