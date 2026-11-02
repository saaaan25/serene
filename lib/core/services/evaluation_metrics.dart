/// Common contract: a missing measurement is null, never a fabricated zero.
Map<String, Object?> pendingEvaluationMetrics() => {
  'host_invoke': {
    'status': 'pending_external_measurement',
    'median_ms': null,
    'required_host': 'Windows CPU',
    'interpreter_threads': 4,
    'batch_policy': 'original preprocessed batches; no regrouping',
    'excludes': ['model_loading', 'warmup', 'set_tensor', 'get_tensor'],
    'procedure':
        'tool/evaluate_performance.py --model MODEL --batches DIRECTORY',
  },
  'storage_reduction': {
    'status': 'pending_external_measurement',
    'percent': null,
    'float32_bytes': null,
    'optimized_bytes': null,
    'formula': '(1 - optimized_bytes / float32_bytes) * 100',
    'procedure':
        'tool/evaluate_performance.py --float32 BASELINE --optimized MODEL',
  },
  'official_background_peak_ram': {
    'status': 'pending_external_measurement',
    'peak_bytes': null,
    'profiler': null,
    'memory_metric': null,
    'device_model': null,
    'background_interval_seconds': null,
    'evidence_sha256': null,
    'procedure':
        'docs/performance-evaluation.md; export official profiler evidence',
  },
};
