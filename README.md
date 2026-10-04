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

On Android, monitoring uses a microphone foreground service and can continue
while the app is in the background. On iOS, audio background mode is enabled;
background execution is subject to iOS audio-session and system policies.

For iOS builds, run `pod install` from the `ios` directory on macOS after
`flutter pub get`. iOS builds cannot be produced on Windows.

The bundled audio model uses a TensorFlow Select op (`FlexErf`). Android
includes the Select TF Ops runtime and creates its delegate before inference;
iOS links the Select TF Ops framework into the app. The prebuilt iOS framework
supports physical arm64 devices, not the iOS simulator; simulator builds need a
Select TF Ops framework built for the simulator architecture.
