import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from evaluate_performance import load_ram_evidence, pending_metrics, storage_reduction, benchmark


class PerformanceReportTests(unittest.TestCase):
    def test_pending_measurements_are_null(self):
        metrics = pending_metrics()
        self.assertIsNone(metrics['host_invoke']['median_ms'])
        self.assertIsNone(metrics['storage_reduction']['percent'])
        self.assertIsNone(metrics['official_background_peak_ram']['peak_bytes'])

    def test_reduction_preserves_negative_results_and_hashes(self):
        with tempfile.TemporaryDirectory() as folder:
            baseline, candidate = Path(folder) / 'a', Path(folder) / 'b'
            baseline.write_bytes(b'1234')
            candidate.write_bytes(b'123456')
            result = storage_reduction(baseline, candidate)
            self.assertEqual(result['percent'], -50)
            self.assertEqual(len(result['float32_sha256']), 64)
            self.assertFalse(result['reference_dtype_verified'])

    def test_empty_baseline_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            file = Path(folder) / 'empty'
            file.touch()
            with self.assertRaises(ValueError):
                storage_reduction(file, file)

    def test_external_ram_requires_actual_artifact_and_records_provenance(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            evidence = root / 'ram.json'
            data = {
                'platform': 'ios', 'profiler': 'Xcode Instruments',
                'profiler_version': 'test', 'device_model': 'fixture',
                'os_version': 'test', 'app_version': 'test', 'build_mode': 'profile',
                'memory_metric': 'physical footprint', 'peak_bytes': 123456,
                'background_interval_seconds': 60, 'captured_at_utc': '2026-11-01T00:00:00Z',
                'evidence_file': 'trace.zip',
            }
            evidence.write_text(json.dumps(data), encoding='utf-8')
            with self.assertRaises(ValueError):
                load_ram_evidence(evidence)
            (root / 'trace.zip').write_bytes(b'unit-test fixture; not a real capture')
            result = load_ram_evidence(evidence)
            self.assertEqual(result['status'], 'externally_reported_not_independently_verified')
            self.assertEqual(result['peak_bytes'], 123456)
            self.assertEqual(len(result['evidence_sha256']), 64)
            data['peak_bytes'] = True
            evidence.write_text(json.dumps(data), encoding='utf-8')
            with self.assertRaises(ValueError):
                load_ram_evidence(evidence)

    def test_host_benchmark_rejects_other_operating_systems(self):
        with patch('evaluate_performance.platform.system', return_value='Darwin'):
            with self.assertRaises(ValueError):
                benchmark(None, None, 10, 5, None, None)


if __name__ == '__main__':
    unittest.main()
