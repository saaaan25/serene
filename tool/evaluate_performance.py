"""Export measured/pending thesis metrics. Standard library unless invoking TFLite."""
import argparse
import csv
import hashlib
import json
import math
import platform
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def pending_metrics():
    return {
        'host_invoke': {'status': 'pending_external_measurement', 'median_ms': None},
        'storage_reduction': {'status': 'pending_external_measurement', 'percent': None},
        'official_background_peak_ram': {
            'status': 'pending_external_measurement', 'peak_bytes': None,
        },
    }


def storage_reduction(baseline, optimized):
    size = baseline.stat().st_size
    candidate = optimized.stat().st_size
    if not size or not candidate:
        raise ValueError('Model files must not be empty')
    return {
        'status': 'measured_artifact_sizes',
        'float32_bytes': size, 'optimized_bytes': candidate,
        'float32_sha256': digest(baseline), 'optimized_sha256': digest(optimized),
        'percent': (1 - candidate / size) * 100,
        'formula': '(1 - optimized_bytes / float32_bytes) * 100',
        'reference_dtype_verified': False,
        'note': 'Caller must establish FLOAT32 provenance; file size does not verify tensor dtype.',
    }


def load_ram_evidence(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    expected = {'ios': 'Xcode Instruments', 'android': 'Android Studio Profiler'}
    if data.get('platform') not in expected or data.get('profiler') != expected[data['platform']]:
        raise ValueError('Use ios/Xcode Instruments or android/Android Studio Profiler')
    for key in ['profiler_version', 'device_model', 'os_version', 'app_version',
                'memory_metric', 'captured_at_utc', 'evidence_file']:
        if not isinstance(data.get(key), str) or not data[key].strip():
            raise ValueError(f'Missing evidence field: {key}')
    if data.get('build_mode') not in ['profile', 'release']:
        raise ValueError('RAM evidence must use profile or release mode')
    peak, duration = data.get('peak_bytes'), data.get('background_interval_seconds')
    if type(peak) is not int or peak <= 0:
        raise ValueError('peak_bytes must be a positive integer')
    if type(duration) not in (int, float) or not math.isfinite(duration) or duration <= 0:
        raise ValueError('background_interval_seconds must be positive and finite')
    captured = datetime.fromisoformat(data['captured_at_utc'].replace('Z', '+00:00'))
    if captured.utcoffset() != timezone.utc.utcoffset(captured):
        raise ValueError('captured_at_utc must have UTC timezone')
    artifact = path.parent / data['evidence_file']
    if not artifact.is_file():
        raise ValueError('Evidence must be an existing exported file (zip .trace bundles first)')
    return {
        'status': 'externally_reported_not_independently_verified',
        **{key: data[key] for key in [
            'platform', 'profiler', 'profiler_version', 'device_model', 'os_version',
            'app_version', 'build_mode', 'memory_metric', 'peak_bytes',
            'background_interval_seconds', 'captured_at_utc',
        ]},
        'evidence_sha256': digest(artifact),
        'note': 'Manual transcription from official profiler; verify trace interval and metric.',
    }


def benchmark(model, batches, repetitions, warmup, output, note):
    if platform.system() != 'Windows':
        raise ValueError('This thesis benchmark requires a Windows host')
    import numpy as np
    import tensorflow as tf

    files = sorted(batches.glob('*.npy'))
    if not files:
        raise ValueError('Expected one original preprocessed batch per .npy file')
    interpreter = tf.lite.Interpreter(model_path=str(model), num_threads=4)
    if len(interpreter.get_input_details()) != 1:
        raise ValueError('Benchmark supports exactly one model input')
    all_times, batch_rows = [], []
    with (output / 'invoke_samples.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.writer(stream)
        writer.writerow(['batch', 'iteration', 'invoke_ms'])
        for index, file in enumerate(files):
            batch = np.load(file, allow_pickle=False)
            detail = interpreter.get_input_details()[0]
            if batch.dtype != detail['dtype'] or batch.ndim != len(detail['shape']):
                raise ValueError('Batch dtype/rank must match model; no implicit conversion')
            if not np.isfinite(batch).all() or not batch.size:
                raise ValueError('Batch must contain finite nonempty values')
            interpreter.resize_tensor_input(detail['index'], list(batch.shape), strict=True)
            interpreter.allocate_tensors()
            detail = interpreter.get_input_details()[0]
            interpreter.set_tensor(detail['index'], batch)
            for _ in range(warmup):
                interpreter.invoke()
            times = []
            for iteration in range(repetitions):
                interpreter.set_tensor(detail['index'], batch)
                start = time.perf_counter_ns()
                interpreter.invoke()
                elapsed = (time.perf_counter_ns() - start) / 1_000_000
                for tensor in interpreter.get_output_details():
                    if not np.isfinite(interpreter.get_tensor(tensor['index'])).all():
                        raise ValueError('Non-finite model output')
                times.append(elapsed)
                writer.writerow([index + 1, iteration + 1, elapsed])
                stream.flush()
            batch_rows.append({
                'batch': index + 1, 'sha256': digest(file), 'shape': list(batch.shape),
                'dtype': str(batch.dtype), 'median_ms': statistics.median(times),
            })
            all_times.extend(times)
            note(f'Batch {index + 1}: completed')
    return {
        'status': 'measured_host', 'median_ms': statistics.median(all_times),
        'tensorflow_version': tf.__version__, 'numpy_version': np.__version__,
        'interpreter_threads': 4, 'model_sha256': digest(model),
        'warmups_per_batch': warmup, 'repetitions_per_batch': repetitions,
        'batch_policy': 'original batches supplied by caller; no regrouping or normalization',
        'delegates': 'TensorFlow default CPU delegates; no GPU delegate explicitly loaded',
        'excludes': ['load', 'resize', 'allocate', 'warmup', 'set_tensor', 'get_tensor'],
        'aggregation': 'median of all timed invokes; not per-example latency',
        'batches': batch_rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--float32', type=Path)
    parser.add_argument('--optimized', type=Path)
    parser.add_argument('--model', type=Path)
    parser.add_argument('--batches', type=Path)
    parser.add_argument('--repetitions', type=int, default=10)
    parser.add_argument('--warmup', type=int, default=5)
    parser.add_argument('--ram-evidence', type=Path)
    args = parser.parse_args()
    if bool(args.float32) != bool(args.optimized) or bool(args.model) != bool(args.batches):
        parser.error('Supply --float32/--optimized and --model/--batches as pairs')
    if args.repetitions < 1 or args.warmup < 1:
        parser.error('Repetitions and warmup must be positive')
    now = datetime.now(timezone.utc)
    output = Path('evaluation_results') / ('performance_' + now.strftime('%Y%m%dT%H%M%S%fZ'))
    output.mkdir(parents=True)
    report = {
        'schema_version': 1, 'started_at_utc': now.isoformat(), 'status': 'running',
        'environment': {'os': platform.platform(), 'cpu': platform.processor(),
                        'python': platform.python_version()},
        'evaluation_metrics': pending_metrics(),
        'errors': {},
    }
    def save():
        (output / 'results.json').write_text(json.dumps(report, indent=2, allow_nan=False), encoding='utf-8')
    def note(message):
        line = datetime.now(timezone.utc).isoformat() + ' ' + message
        print(line)
        with (output / 'run.log').open('a', encoding='utf-8') as stream:
            stream.write(line + '\n')
    save()
    note('Starting performance report')
    jobs = []
    if args.float32:
        jobs.append(('storage_reduction', lambda: storage_reduction(args.float32, args.optimized)))
    if args.model:
        jobs.append(('host_invoke', lambda: benchmark(args.model, args.batches, args.repetitions,
                                                     args.warmup, output, note)))
    if args.ram_evidence:
        jobs.append(('official_background_peak_ram', lambda: load_ram_evidence(args.ram_evidence)))
    for key, action in jobs:
        try:
            report['evaluation_metrics'][key] = action()
            note(key + ': completed')
        except Exception as error:
            report['evaluation_metrics'][key]['status'] = 'error'
            report['errors'][key] = {'type': type(error).__name__, 'message': str(error)}
            note(key + ': error; inspect results.json')
        save()
    report['status'] = 'error' if report['errors'] else (
        'partial' if any(value['status'] == 'pending_external_measurement'
                         for value in report['evaluation_metrics'].values()) else 'complete')
    report['ended_at_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    note(f"Finished: {report['status']}. Results: {output}")
    return 1 if report['errors'] else 0


if __name__ == '__main__':
    sys.exit(main())
