import CoreBluetooth
import Flutter

class BleManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    private static let escPosServiceUUID = CBUUID(string: "000018f0-0000-1000-8000-00805f9b34fb")
    private static let escPosTxCharUUID = CBUUID(string: "00002af1-0000-1000-8000-00805f9b34fb")

    private var centralManager: CBCentralManager?
    private var scanEventSink: FlutterEventSink?
    private var discoveredDevices: [[String: String]] = []
    private var scanTimer: Timer?

    // Connection state
    private var connectedPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var mtuPayload: Int = 20
    private var canWriteWithoutResponse: Bool = false
    private var connectResult: FlutterResult?
    private var writeResult: FlutterResult?
    private var pendingWriteData: Data?
    private var pendingWriteResult: FlutterResult?
    private var connectTimer: Timer?
    private var targetServiceUUID: CBUUID?
    private var targetCharUUID: CBUUID?

    var connectionStateCallback: ((String) -> Void)?

    // Lazy init to avoid triggering the BT permission dialog on plugin load
    private func ensureCentralManager() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    lazy var scanStreamHandler: FlutterStreamHandler = {
        return BleScanStreamHandler(manager: self)
    }()

    func setScanEventSink(_ sink: FlutterEventSink?) {
        scanEventSink = sink
    }

    func requestPermissions(result: @escaping FlutterResult) {
        ensureCentralManager()
        // On iOS, creating CBCentralManager triggers the system dialog if needed.
        // We just check the current state.
        if #available(iOS 13.1, *) {
            switch CBCentralManager.authorization {
            case .allowedAlways:
                result(true)
            case .notDetermined:
                // Dialog was just triggered by ensureCentralManager(). Return true
                // optimistically — if denied, scan/connect will fail with clear errors.
                result(true)
            case .denied, .restricted:
                result(false)
            @unknown default:
                result(true)
            }
        } else {
            // Pre-13.1, permission is always granted if BT is available
            result(centralManager?.state == .poweredOn)
        }
    }

    func getBondedBleDevices(result: @escaping FlutterResult) {
        ensureCentralManager()
        guard let cm = centralManager, cm.state == .poweredOn else {
            result([[[String: String]]]())
            return
        }

        // iOS has no bonded device list. Retrieve peripherals that are
        // currently connected to the system (any service) as a best-effort
        // equivalent.
        let connected = cm.retrieveConnectedPeripherals(withServices: [
            BleManager.escPosServiceUUID
        ])

        let devices: [[String: String]] = connected.map { peripheral in
            [
                "deviceId": peripheral.identifier.uuidString,
                "name": peripheral.name ?? peripheral.identifier.uuidString
            ]
        }
        result(devices)
    }

    func startScan(timeoutMs: Int, result: @escaping FlutterResult) {
        ensureCentralManager()
        guard let cm = centralManager, cm.state == .poweredOn else {
            result(FlutterError(code: "UNAVAILABLE", message: "Bluetooth is not powered on", details: nil))
            return
        }

        discoveredDevices.removeAll()
        cm.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Auto-stop after timeout
        let timeout = Double(timeoutMs) / 1000.0
        scanTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.stopScanInternal()
        }

        result(nil)
    }

    func stopScan(result: @escaping FlutterResult) {
        stopScanInternal()
        result(nil)
    }

    private func stopScanInternal() {
        scanTimer?.invalidate()
        scanTimer = nil
        centralManager?.stopScan()
    }

    func connect(deviceId: String, timeoutMs: Int, serviceUuid: String?, characteristicUuid: String?, result: @escaping FlutterResult) {
        ensureCentralManager()
        guard let cm = centralManager, cm.state == .poweredOn else {
            result(FlutterError(code: "UNAVAILABLE", message: "Bluetooth is not powered on", details: nil))
            return
        }

        guard let uuid = UUID(uuidString: deviceId) else {
            result(FlutterError(code: "INVALID_DEVICE", message: "Invalid device UUID: \(deviceId)", details: nil))
            return
        }

        targetServiceUUID = serviceUuid != nil ? CBUUID(string: serviceUuid!) : BleManager.escPosServiceUUID
        targetCharUUID = characteristicUuid != nil ? CBUUID(string: characteristicUuid!) : BleManager.escPosTxCharUUID

        let peripherals = cm.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else {
            result(FlutterError(code: "NOT_FOUND", message: "Peripheral not found for UUID: \(deviceId)", details: nil))
            return
        }

        connectResult = result
        connectedPeripheral = peripheral
        peripheral.delegate = self

        cm.connect(peripheral, options: nil)

        // Timeout
        let timeout = Double(timeoutMs) / 1000.0
        connectTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self, self.connectResult != nil else { return }
            cm.cancelPeripheralConnection(peripheral)
            self.connectResult?(FlutterError(code: "TIMEOUT", message: "BLE connection timed out", details: nil))
            self.connectResult = nil
            self.connectedPeripheral = nil
        }
    }

    func getMtu(result: @escaping FlutterResult) {
        result(mtuPayload)
    }

    func supportsWriteWithoutResponse(result: @escaping FlutterResult) {
        result(canWriteWithoutResponse)
    }

    func write(data: Data, withoutResponse: Bool, result: @escaping FlutterResult) {
        guard let peripheral = connectedPeripheral, let char = txCharacteristic else {
            result(FlutterError(code: "NOT_CONNECTED", message: "BLE device not connected", details: nil))
            return
        }

        if withoutResponse {
            // CoreBluetooth has a finite internal queue for write-without-response packets.
            // If we write when the queue is full, the packet is silently dropped.
            // Check canSendWriteWithoutResponse first; if not ready, park the write and
            // resolve it from peripheralIsReady(toSendWriteWithoutResponse:).
            if peripheral.canSendWriteWithoutResponse {
                peripheral.writeValue(data, for: char, type: .withoutResponse)
                result(nil)
            } else {
                pendingWriteData = data
                pendingWriteResult = result
            }
        } else {
            writeResult = result
            peripheral.writeValue(data, for: char, type: .withResponse)
        }
    }

    func disconnect(result: @escaping FlutterResult) {
        if let peripheral = connectedPeripheral, let cm = centralManager {
            cm.cancelPeripheralConnection(peripheral)
        }
        cleanup()
        connectionStateCallback?("disconnected")
        result(nil)
    }

    private func cleanup() {
        connectTimer?.invalidate()
        connectTimer = nil
        connectedPeripheral = nil
        txCharacteristic = nil
        mtuPayload = 20
        canWriteWithoutResponse = false
        pendingWriteData = nil
        pendingWriteResult = nil
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // State changes are handled implicitly — if BT turns off,
        // ongoing connections will trigger didDisconnectPeripheral.
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let id = peripheral.identifier.uuidString
        if !discoveredDevices.contains(where: { $0["deviceId"] == id }) {
            discoveredDevices.append([
                "deviceId": id,
                "name": peripheral.name ?? id
            ])
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.scanEventSink?(self.discoveredDevices)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Discover services
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimer?.invalidate()
        connectTimer = nil
        connectResult?(FlutterError(code: "CONNECTION_FAILED", message: "Failed to connect: \(error?.localizedDescription ?? "unknown")", details: nil))
        connectResult = nil
        connectedPeripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectResult != nil {
            connectTimer?.invalidate()
            connectTimer = nil
            connectResult?(FlutterError(code: "DISCONNECTED", message: "Disconnected during setup", details: nil))
            connectResult = nil
        } else {
            // Remote disconnection
            connectionStateCallback?("disconnected")
        }
        cleanup()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            connectTimer?.invalidate()
            connectTimer = nil
            centralManager?.cancelPeripheralConnection(peripheral)
            connectResult?(FlutterError(code: "SERVICE_DISCOVERY_FAILED", message: error.localizedDescription, details: nil))
            connectResult = nil
            return
        }

        // Discover characteristics for all services
        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            // Non-fatal — continue looking at other services
            return
        }

        guard txCharacteristic == nil else { return } // Already found

        // 1. Try target service/characteristic UUIDs
        if let targetSvc = targetServiceUUID, service.uuid == targetSvc {
            if let chars = service.characteristics {
                for c in chars {
                    if c.uuid == targetCharUUID && isWritable(c) {
                        selectCharacteristic(c, peripheral: peripheral)
                        return
                    }
                }
            }
        }

        // 2. Fallback: any writable characteristic
        if let chars = service.characteristics {
            for c in chars {
                if isWritable(c) {
                    selectCharacteristic(c, peripheral: peripheral)
                    return
                }
            }
        }
    }

    private func selectCharacteristic(_ char: CBCharacteristic, peripheral: CBPeripheral) {
        txCharacteristic = char
        // Prefer write-with-response for reliable backpressure; the printer
        // ACKs each chunk before we send the next, preventing buffer overflow.
        // Fall back to write-without-response only if that is the sole option.
        canWriteWithoutResponse = !char.properties.contains(.write) && char.properties.contains(.writeWithoutResponse)

        // Get MTU
        let writeType: CBCharacteristicWriteType = canWriteWithoutResponse ? .withoutResponse : .withResponse
        mtuPayload = peripheral.maximumWriteValueLength(for: writeType)

        connectTimer?.invalidate()
        connectTimer = nil
        connectResult?(nil)
        connectResult = nil
        connectionStateCallback?("connected")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            writeResult?(FlutterError(code: "WRITE_FAILED", message: error.localizedDescription, details: nil))
        } else {
            writeResult?(nil)
        }
        writeResult = nil
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let data = pendingWriteData, let char = txCharacteristic else { return }
        let result = pendingWriteResult
        pendingWriteData = nil
        pendingWriteResult = nil
        peripheral.writeValue(data, for: char, type: .withoutResponse)
        result?(nil)
    }

    private func isWritable(_ c: CBCharacteristic) -> Bool {
        return c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse)
    }
}

class BleScanStreamHandler: NSObject, FlutterStreamHandler {
    private weak var manager: BleManager?

    init(manager: BleManager) {
        self.manager = manager
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        manager?.setScanEventSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        manager?.setScanEventSink(nil)
        return nil
    }
}
