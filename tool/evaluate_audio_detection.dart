import 'dart:convert';
import 'dart:io';

import 'package:serene/core/constants/app_constants.dart';
import 'package:serene/core/dsp/signal_quality.dart';
import 'package:serene/features/audio_monitoring/domain/detection_policy.dart';
import 'package:serene/features/audio_monitoring/domain/entities/inference_result.dart';

/// Consumes predict_mobile_recordings.py output and runs the actual Dart policy.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart tool/evaluate_audio_detection.dart predictions.jsonl',
    );
    exitCode = 64;
    return;
  }
  final results = <Map<String, Object?>>[];
  final policy = DetectionPolicy();
  Map<String, dynamic>? recording;
  Map<String, dynamic>? model;
  final detections = <Map<String, double>>[];
  double? candidateStart;
  Map<String, double>? active;
  var windows = 0;
  var rejected = 0;
  var previousEnd = 0;

  void finish() {
    if (recording == null) return;
    final duration =
        (recording['samples'] as num).toDouble() / AppConstants.sampleRate;
    if (active != null) active!['end_seconds'] = duration;
    final events = (recording['events'] as List).cast<Map<String, dynamic>>();
    final matched = <int>{};
    final delays = <double>[];
    var falseAlarms = 0;
    for (final detection in detections) {
      final confirmation = detection['confirmation_seconds']!;
      final eligible = events.indexWhere(
        (event) =>
            !matched.contains(events.indexOf(event)) &&
            (event['start_seconds'] as num) < confirmation &&
            (event['end_seconds'] as num) >
                confirmation - AppConstants.windowDurationSeconds,
      );
      if (eligible < 0) {
        falseAlarms++;
      } else {
        matched.add(eligible);
        delays.add(confirmation - (events[eligible]['start_seconds'] as num));
      }
    }
    results.add({
      'id': recording['id'],
      'seconds': duration,
      'windows': windows,
      'unevaluated_short_recording': windows == 0,
      'rejected_windows': rejected,
      'annotated_events': events.length,
      'matched_events': matched.length,
      'missed_events': events.length - matched.length,
      'false_alarm_events': falseAlarms,
      'negative_recording_hours': events.isEmpty && windows > 0
          ? (duration - AppConstants.windowDurationSeconds).clamp(
                  0,
                  double.infinity,
                ) /
                3600
          : 0.0,
      'confirmation_delays_seconds': delays,
      'detections': List<Map<String, double>>.from(detections),
    });
    detections.clear();
    active = null;
    candidateStart = null;
    policy.reset();
    windows = 0;
    rejected = 0;
    previousEnd = 0;
  }

  await for (final line in File(
    args.single,
  ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final row = jsonDecode(line) as Map<String, dynamic>;
    if (row['type'] == 'model') {
      model = row;
      if (row['sample_rate'] != AppConstants.sampleRate ||
          row['window_samples'] != AppConstants.expectedSampleCount ||
          (row.containsKey('minimum_centered_rms') &&
              row['minimum_centered_rms'] !=
                  SignalQuality.minimumCenteredRms)) {
        throw const FormatException(
          'Input does not match the app audio contract',
        );
      }
    } else if (row['type'] == 'recording') {
      finish();
      recording = row;
    } else if (row['type'] == 'window') {
      if (recording == null || row['id'] != recording['id']) {
        throw const FormatException('Unmatched recording');
      }
      final end = row['end_sample'] as int;
      if (end <= previousEnd) {
        throw const FormatException('Non-increasing PCM positions');
      }
      previousEnd = end;
      windows++;
      final quality = SignalQuality(
        centeredRms: (row['centered_rms'] as num).toDouble(),
        isFinite: row['signal_finite'] == true,
      );
      if (!quality.isUsable) rejected++;
      InferenceResult? prediction;
      if (quality.isUsable && row['scores'] != null) {
        final scores = (row['scores'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        );
        const labels = [
          AppConstants.classNoViolence,
          AppConstants.classPhysicalViolence,
          AppConstants.classVerbalViolence,
        ];
        if (scores.length != labels.length ||
            labels.any((label) => !scores.containsKey(label)) ||
            scores.values.any((p) => !p.isFinite || p < 0 || p > 1) ||
            (scores.values.reduce((a, b) => a + b) - 1).abs() > 1e-3) {
          throw const FormatException('Invalid probabilities');
        }
        var label = labels.first;
        for (final candidate in labels.skip(1)) {
          if (scores[candidate]! > scores[label]!) label = candidate;
        }
        prediction = InferenceResult(
          label: label,
          confidence: scores[label]!,
          allScores: scores,
          isViolenceDetected:
              label != AppConstants.classNoViolence &&
              scores[label]! >= AppConstants.classificationThreshold,
        );
      }
      final decision = policy.observe(
        endSample: end,
        usableSignal: quality.isUsable,
        freshResult: prediction,
      );
      final seconds = end / AppConstants.sampleRate;
      switch (decision) {
        case DetectionDecision.candidate:
          if (policy.candidateAt == end) {
            candidateStart = seconds - AppConstants.windowDurationSeconds;
          }
        case DetectionDecision.confirmed:
          active = {
            'start_seconds': candidateStart!,
            'confirmation_seconds': seconds,
            'end_seconds': seconds,
          };
          detections.add(active!);
        case DetectionDecision.active:
          active!['end_seconds'] = seconds;
        case DetectionDecision.close:
          active!['end_seconds'] = seconds;
          active = null;
          candidateStart = null;
        case DetectionDecision.idle:
          candidateStart = null;
        case DetectionDecision.ignored:
          break;
      }
    }
  }
  finish();
  if (model == null || results.isEmpty) {
    throw const FormatException('Missing model/recordings');
  }
  num sum(String key) => results.fold<num>(0, (a, r) => a + (r[key] as num));
  final evaluated = results.where(
    (r) => r['unevaluated_short_recording'] == false,
  );
  num evaluatedSum(String key) =>
      evaluated.fold<num>(0, (a, r) => a + (r[key] as num));
  final matched = evaluatedSum('matched_events');
  final falseAlarms = sum('false_alarm_events');
  final negativeHours = sum('negative_recording_hours');
  final negativeFalseAlarms = results
      .where((r) => r['annotated_events'] == 0)
      .fold<num>(0, (a, r) => a + (r['false_alarm_events'] as num));
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'model': model,
      'policy': {
        'threshold': AppConstants.classificationThreshold,
        'confirmation_separation_samples':
            AppConstants.confirmationSeparationSamples,
        'confirmation_timeout_samples': AppConstants.confirmationTimeoutSamples,
        'maximum_unclassified_samples': AppConstants.maximumUnclassifiedSamples,
        'minimum_centered_rms': SignalQuality.minimumCenteredRms,
      },
      'event_precision': matched + falseAlarms == 0
          ? null
          : matched / (matched + falseAlarms),
      'event_recall': evaluatedSum('annotated_events') == 0
          ? null
          : matched / evaluatedSum('annotated_events'),
      'false_alarms_per_negative_hour': negativeHours == 0
          ? null
          : negativeFalseAlarms / negativeHours,
      'recordings': results,
      'scope':
          'Host model and shared Dart policy; not a phone runtime benchmark. Short files and correlated windows require explicit review.',
    }),
  );
}
