import Flutter
import UIKit
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var diagnosticsBridge: DiagnosticsBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    diagnosticsBridge = DiagnosticsBridge(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

private final class DiagnosticsBridge {
  private let channel: FlutterMethodChannel
  private var previousCpu: Double?
  private var previousWall: Double?
  private var previousBatteryMonitoring: Bool?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.example.serene/diagnostics", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(FlutterError(code: "diagnostics_unavailable", message: "Diagnostic service unavailable", details: nil)) }
      switch call.method {
      case "begin":
        if self.previousBatteryMonitoring == nil {
          self.previousBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.previousCpu = self.cpuSeconds()
        self.previousWall = ProcessInfo.processInfo.systemUptime
        result(nil)
      case "end":
        if let enabled = self.previousBatteryMonitoring {
          UIDevice.current.isBatteryMonitoringEnabled = enabled
        }
        self.previousBatteryMonitoring = nil
        self.previousCpu = nil
        self.previousWall = nil
        result(nil)
      case "sample": result(self.sample())
      case "share":
        guard let args = call.arguments as? [String: Any], let json = args["json"] as? String,
              json.utf8.count <= 2_000_000 else {
          return result(FlutterError(code: "invalid_report", message: "Invalid diagnostic report", details: nil))
        }
        do {
          try self.share(json)
          result(nil)
        } catch {
          result(FlutterError(code: "diagnostics_export_failed", message: "Could not share the diagnostic report", details: nil))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func cpuSeconds() -> Double? {
    var usage = rusage()
    guard getrusage(0, &usage) == 0 else { return nil } // RUSAGE_SELF
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
      + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
  }

  private func footprint() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let capacity = Int(count)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return status == KERN_SUCCESS ? info.phys_footprint : nil
  }

  private func sample() -> [String: Any] {
    let wall = ProcessInfo.processInfo.systemUptime
    let cpu = cpuSeconds()
    var data: [String: Any] = ["platform_version": UIDevice.current.systemVersion]
    if let current = cpu, let previous = previousCpu, let start = previousWall,
       wall - start >= 0.25, current >= previous {
      data["process_cpu_percent_one_core"] = 100 * (current - previous) / (wall - start)
    }
    previousCpu = cpu
    previousWall = wall
    if let bytes = footprint() { data["process_footprint_bytes"] = bytes }
    var size = 0
    if sysctlbyname("hw.machine", nil, &size, nil, 0) == 0 && size > 0 {
      var machine = [CChar](repeating: 0, count: size)
      if sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 {
        data["device_model"] = String(cString: machine)
      }
    }
    let battery = UIDevice.current.batteryLevel
    if battery >= 0 { data["battery_percent"] = Double(battery) * 100 }
    if UIDevice.current.batteryState != .unknown {
      data["charging"] = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: data["thermal_state"] = "nominal"
    case .fair: data["thermal_state"] = "fair"
    case .serious: data["thermal_state"] = "serious"
    case .critical: data["thermal_state"] = "critical"
    @unknown default: data["thermal_state"] = "unknown"
    }
    return data
  }

  private func share(_ json: String) throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent("serene_diagnostics", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let expiry = Date().addingTimeInterval(-24 * 60 * 60)
    for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
      if file.lastPathComponent.hasPrefix("serene_diagnostics_"), file.pathExtension == "json",
         let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
         modified < expiry { try? manager.removeItem(at: file) }
    }
    guard var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      throw NSError(domain: "SereneDiagnostics", code: 1)
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    let file = directory.appendingPathComponent("serene_diagnostics_\(Int(Date().timeIntervalSince1970 * 1000)).json")
    try Data(json.utf8).write(to: file, options: .atomic)
    let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
      popover.permittedArrowDirections = []
    }
    presenter.present(sheet, animated: true)
  }
}
