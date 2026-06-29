import Flutter
import UIKit

public class UnifiedEscPosPrinterPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var bleScanEventChannel: FlutterEventChannel?
    private var connectionStateEventChannel: FlutterEventChannel?

    private var bleManager: BleManager?
    private var connectionStateHandler: ConnectionStateStreamHandler?
    private var scanStreamHandler: BleScanStreamHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = UnifiedEscPosPrinterPlugin()
        instance.setup(with: registrar)
    }

    private func setup(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()

        methodChannel = FlutterMethodChannel(
            name: "com.elriztechnology.unified_esc_pos_printer/methods",
            binaryMessenger: messenger
        )
        methodChannel?.setMethodCallHandler(handle)

        bleManager = BleManager()

        bleScanEventChannel = FlutterEventChannel(
            name: "com.elriztechnology.unified_esc_pos_printer/ble_scan",
            binaryMessenger: messenger
        )
        
        scanStreamHandler = BleScanStreamHandler(manager: bleManager!)
        bleScanEventChannel?.setStreamHandler(scanStreamHandler)

        // BT scan channel — not supported on iOS, use a no-op handler
        let btScanEventChannel = FlutterEventChannel(
            name: "com.elriztechnology.unified_esc_pos_printer/bt_scan",
            binaryMessenger: messenger
        )
        btScanEventChannel.setStreamHandler(NoOpStreamHandler())

        connectionStateHandler = ConnectionStateStreamHandler(bleManager: bleManager!)
        connectionStateEventChannel = FlutterEventChannel(
            name: "com.elriztechnology.unified_esc_pos_printer/connection_state",
            binaryMessenger: messenger
        )
        connectionStateEventChannel?.setStreamHandler(connectionStateHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {
        // Permissions
        case "requestPermissions":
            bleManager?.requestPermissions(result: result)

        // BLE
        case "startBleScan":
            let timeoutMs = args?["timeoutMs"] as? Int ?? 5000
            bleManager?.startScan(timeoutMs: timeoutMs, result: result)
        case "stopBleScan":
            bleManager?.stopScan(result: result)
        case "getBondedBleDevices":
            bleManager?.getBondedBleDevices(result: result)
        case "bleConnect":
            let deviceId = args?["deviceId"] as? String ?? ""
            let timeoutMs = args?["timeoutMs"] as? Int ?? 10000
            let serviceUuid = args?["serviceUuid"] as? String
            let characteristicUuid = args?["characteristicUuid"] as? String
            bleManager?.connect(
                deviceId: deviceId,
                timeoutMs: timeoutMs,
                serviceUuid: serviceUuid,
                characteristicUuid: characteristicUuid,
                result: result
            )
        case "bleGetMtu":
            bleManager?.getMtu(result: result)
        case "bleSupportsWriteWithoutResponse":
            bleManager?.supportsWriteWithoutResponse(result: result)
        case "bleWrite":
            let data = (args?["data"] as? FlutterStandardTypedData)?.data ?? Data()
            let withoutResponse = args?["withoutResponse"] as? Bool ?? false
            bleManager?.write(data: data, withoutResponse: withoutResponse, result: result)
        case "bleDisconnect":
            bleManager?.disconnect(result: result)

        // Bluetooth Classic — not supported on iOS
        case "getBondedDevices":
            result(FlutterError(code: "UNSUPPORTED", message: "Bluetooth Classic is not supported on iOS", details: nil))
        case "startBtDiscovery", "stopBtDiscovery", "btConnect", "btWrite", "btDisconnect":
            result(FlutterError(code: "UNSUPPORTED", message: "Bluetooth Classic is not supported on iOS", details: nil))

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - ConnectionStateStreamHandler

class ConnectionStateStreamHandler: NSObject, FlutterStreamHandler {
    private let bleManager: BleManager

    init(bleManager: BleManager) {
        self.bleManager = bleManager
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        bleManager.connectionStateCallback = { state in
            DispatchQueue.main.async {
                events(["type": "ble", "state": state])
            }
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        bleManager.connectionStateCallback = nil
        return nil
    }
}

// MARK: - NoOpStreamHandler

class NoOpStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}
