# Serene

Serene is a Flutter app for passive audio monitoring and encrypted evidence
storage.

## Mobile setup

Run `flutter pub get` before building. Android requests microphone permission
for monitoring and notification permission so its foreground service can show
the persistent monitoring notification. Location is requested only when an
incident is saved; an evidence record has no coordinates if location is
unavailable or permission is denied. If microphone or notification access is
denied, enable it in the device's app settings and reopen Serene.

Monitoring begins after microphone permission has been granted. Android runs
capture, inference and encrypted checkpoints in the microphone foreground
service with a persistent notification and a Stop button. Removing the UI from
recent apps does not intentionally stop that service. iOS keeps an active audio
session while backgrounded/locked, with the audio background mode enabled.
Recording pauses/resumes around supported audio interruptions. Forced stops,
revoked permissions and operating-system termination can still stop monitoring;
it is not an always-on guarantee and does not restart the microphone at boot.

The model evaluates overlapping five-second audio windows. A positive detection
starts one incident including that trigger window. Only new PCM samples are
appended, so overlaps are not duplicated. Three seconds of negative decisions
close the incident, allowing brief fluctuations. The first window and every
15 seconds of additional audio are encrypted as checkpoints with the same ID;
the final checkpoint replaces that record, instead of creating isolated clips.
Manual stop persists an open incident. Abrupt termination can lose audio since
the most recent successful checkpoint. Slow devices adapt inference frequency
while retaining the audio; a bounded processing queue reports overload rather
than silently dropping audio.

Android writes only encrypted evidence to an atomic background journal. The UI
imports it into Hive when available or after reopening; the service never opens
Hive concurrently with the UI engine. GPS is optional and acquired once per
incident; the background worker does not show location permission dialogs.
The highest-confidence violence prediction supplies the incident label/score.

For iOS builds (including Codemagic), run `flutter pub get`, then
`ruby tool/align_tflite_ios_podspec.rb` from the repository root, followed by
`pod update TensorFlowLiteSwift TensorFlowLiteC --repo-update` in `ios`.
The script changes the plugin's CocoaPods dependency to TensorFlow Lite 2.17.0.
Codemagic checks that both pods resolve to exactly 2.17.0 before building.
iOS builds cannot be produced on Windows.

The current bundled model contains built-in operators, including FULLY_CONNECTED
version 12; it does not contain FlexErf. iOS therefore uses the standard runtime
without TensorFlowLiteSelectTfOps or Flex linker flags. Android also loads this model without an Activity-owned Flex delegate,
so inference works from the service engine.

## Model export

```sh
python tool/export_wav2vec_tflite.py final_models/best_wav2vec.pt
```

The only input is a PyTorch state_dict checkpoint for Wav2Vec2-base with three
classes. The architecture uses `facebook/wav2vec2-base` (downloaded or cached),
not architecture inferred from arbitrary weights. Use TensorFlow 2.17.x and
compatible PyTorch, Transformers, ONNX and onnx2tf dependencies.

The script writes `model.tflite` and `model.report.json` in the current working
directory. It uses dynamic range quantization with INT8 weights and float32
input/output `[1, 80000]` / `[1, 3]`. Runtime kernels may dynamically quantize
activations; this is not calibrated full-integer quantization. No audio or label
files are required, and synthetic inputs are not used for calibration.

The script checks built-in operators, tensor shapes/types, INT8 weights attached
to compute operations, file size reduction and TensorFlow 2.17 inference. It
compares float32 conversion against the PyTorch GELU approximation and reports
synthetic differences against a reference using the base training configuration.
These checks do not measure accuracy on real audio; the checkpoint alone cannot
provide the original training configuration, calibration data or labeled tests.
The report marks real accuracy as unvalidated. The existing output model is
preserved if validation fails. Copy a successful `model.tflite` into
`assets/models/model.tflite` before building the Codemagic IPA.

Check that training class indices match `assets/labels/labels.txt`:
0 = no_violence, 1 = physical_violence, 2 = verbal_violence.
