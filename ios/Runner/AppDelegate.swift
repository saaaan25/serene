import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let flexDelegateChannelName = "com.example.serene/tflite_flex"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.flexDelegateChannelName,
      binaryMessenger: engineBridge.applicationBinaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "createFlexDelegate":
        let address = FlexDelegateBridge.createDelegate()
        if address == 0 {
          result(
            FlutterError(
              code: "flex_delegate_init_failed",
              message: "Could not resolve the TensorFlow Flex delegate. "
                + "Verify TensorFlowLiteSelectTfOps is linked and force-loaded.",
              details: nil
            )
          )
          return
        }
        result(address)
      case "disposeFlexDelegate":
        FlexDelegateBridge.disposeDelegate()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
