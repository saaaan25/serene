import Flutter
import TensorFlowLiteSelectTfOps
import UIKit

private final class FlexDelegateHolder {
  static var shared: FlexDelegateHolder = FlexDelegateHolder()
  var delegate: TfLiteFlexDelegate? = nil
  var pointer: UnsafeMutableRawPointer? = nil
}

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
        do {
          let holder = FlexDelegateHolder.shared
          if holder.delegate == nil {
            let created = TfLiteFlexDelegate()
            holder.delegate = created
            holder.pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(created).toOpaque())
          }
          guard let pointer = holder.pointer else {
            result(
              FlutterError(
                code: "flex_delegate_init_failed",
                message: "Could not resolve the TensorFlow Flex delegate pointer",
                details: nil
              )
            )
            return
          }
          result(Int64(Int(bitPattern: pointer)))
        } catch {
          result(
            FlutterError(
              code: "flex_delegate_init_failed",
              message: "Could not initialize TensorFlow Select Ops: \(error.localizedDescription)",
              details: nil
            )
          )
        }
      case "disposeFlexDelegate":
        FlexDelegateHolder.shared.delegate = nil
        FlexDelegateHolder.shared.pointer = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
