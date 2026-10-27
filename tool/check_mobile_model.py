"""Run the bundled mixed TFLite model with the app's five-second, batch-one contract.

Requires an existing TensorFlow + NumPy environment. Synthetic signals verify
execution and probability semantics, not accuracy on real five-second events.
"""
import hashlib
import json
from pathlib import Path
import time

import numpy as np
import tensorflow as tf


def main():
    root = Path(__file__).resolve().parent.parent
    model = root / "assets/models/model.tflite"
    labels = (root / "assets/labels/labels.txt").read_text().splitlines()
    assert labels == ["no_violence", "physical_violence", "verbal_violence"]
    interpreter = tf.lite.Interpreter(model_path=str(model), num_threads=2)
    # tflite_flutter also performs this initial allocation in fromBuffer.
    interpreter.allocate_tensors()
    inputs = interpreter.get_input_details()
    assert len(inputs) == 2
    pcm = next(t for t in inputs if t["name"] == "serving_default_pcm:0")
    lengths = next(t for t in inputs if t["name"] == "serving_default_valid_samples:0")
    assert pcm["dtype"] == np.float32 and lengths["dtype"] == np.int32
    interpreter.resize_tensor_input(pcm["index"], [1, 80000], strict=True)
    interpreter.resize_tensor_input(lengths["index"], [1], strict=True)
    interpreter.allocate_tensors()
    outputs = interpreter.get_output_details()
    assert len(outputs) == 1 and outputs[0]["dtype"] == np.float32
    assert outputs[0]["shape"].tolist() == [1, 3]
    signals = {
        "silence": np.zeros(80000, dtype=np.float32),
        "sine_440hz": (.1 * np.sin(2 * np.pi * 440 * np.arange(80000) / 16000)).astype(np.float32),
        "seeded_noise": np.random.default_rng(42).uniform(-.1, .1, 80000).astype(np.float32),
    }
    results = []
    for name, samples in signals.items():
        interpreter.set_tensor(pcm["index"], samples.reshape(1, 80000))
        interpreter.set_tensor(lengths["index"], np.array([80000], dtype=np.int32))
        start = time.perf_counter()
        interpreter.invoke()
        elapsed = (time.perf_counter() - start) * 1000
        probabilities = interpreter.get_tensor(outputs[0]["index"])
        assert probabilities.shape == (1, 3)
        assert np.isfinite(probabilities).all()
        assert ((probabilities >= 0) & (probabilities <= 1)).all()
        assert abs(float(probabilities.sum()) - 1) <= 1e-3
        results.append({"signal": name, "probabilities": probabilities[0].tolist(), "host_ms": elapsed})
    print(json.dumps({
        "model_sha256": hashlib.sha256(model.read_bytes()).hexdigest(),
        "tensorflow": tf.__version__, "pcm_shape": [1, 80000],
        "valid_samples": [80000], "results": results,
        "real_audio_quality_validated": False, "mobile_runtime_validated": False,
    }, indent=2))


if __name__ == "__main__":
    main()
