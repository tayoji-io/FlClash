import Flutter
import Foundation
import UIKit

public class IosPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.follow.clash/ios",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(IosPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getHomeDir":
            result(CoreIdentifiers.sharedContainerURL.path)
        case "readWidgetMode":
            result(WidgetStore.read().mode)
        case "openAppSettings":
            openAppSettings(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func openAppSettings(result: @escaping FlutterResult) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            result(false)
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { opened in
                result(opened)
            }
        }
    }
}
