import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenSecurityPlugin") {
      ScreenSecurityPlugin.register(with: registrar)
    }
  }
}

/// iOS cannot block screenshots or recording the way Android's FLAG_SECURE
/// does. Instead this streams `UIScreen.isCaptured` (true while recording,
/// AirPlay or mirroring is active) to Dart on `secure_edu/screen_capture`,
/// and the player hides and pauses the video while it is true.
/// Protected HLS content from a DRM provider (FairPlay) is additionally
/// blacked out by iOS itself in recordings.
final class ScreenSecurityPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(
      name: "secure_edu/screen_capture",
      binaryMessenger: registrar.messenger()
    )
    channel.setStreamHandler(ScreenSecurityPlugin())
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    observer = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in self?.emit() }
    emit()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    sink = nil
    return nil
  }

  private func emit() {
    sink?(UIScreen.main.isCaptured)
  }
}
