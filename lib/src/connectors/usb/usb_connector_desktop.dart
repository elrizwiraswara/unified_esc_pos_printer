import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:libserialport_plus/libserialport_plus.dart';

import '../../core/commands.dart';
import '../../exceptions/printer_exception.dart';
import '../../models/printer_connection_state.dart';
import '../../models/printer_device.dart';
import 'usb_connector_interface.dart';

/// USB connector for desktop platforms (Windows, Linux, macOS) using
/// `flutter_libserialport` (wraps libserialport).
///
/// Scans via [SerialPort.availablePorts] and opens the selected COM/tty port
/// configured for 115200 baud 8N1.
class UsbConnectorImpl extends UsbConnectorBase {
  SerialPort? _port;
  SerialPortReader? _reader;

  PrinterConnectionState _state = PrinterConnectionState.disconnected;
  final StreamController<PrinterConnectionState> _stateController =
      StreamController<PrinterConnectionState>.broadcast();

  @override
  Stream<PrinterConnectionState> get stateStream => _stateController.stream;

  @override
  PrinterConnectionState get state => _state;

  @override
  Stream<List<UsbPrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    _setState(PrinterConnectionState.scanning);
    final List<String> ports = SerialPort.availablePorts;
    _setState(PrinterConnectionState.disconnected);

    // Filter out Bluetooth virtual COM ports (e.g. "Standard Serial over
    // Bluetooth link" on Windows) — only keep native and USB serial ports.
    final List<UsbPrinterDevice> devices = [];
    for (final String path in ports) {
      final SerialPort sp = SerialPort(path);
      final int transport = sp.transport;
      final String name =
          sp.description?.isNotEmpty == true ? sp.description! : path;
      sp.dispose();

      if (transport == SerialPortTransport.bluetooth) continue;

      devices.add(UsbPrinterDevice(
        name: name,
        identifier: path,
        usbPlatform: UsbPlatform.desktop,
      ));
    }

    if (devices.isNotEmpty) {
      yield devices;
    }
  }

  @override
  Future<void> stopScan() async {
    if (_state == PrinterConnectionState.scanning) {
      _setState(PrinterConnectionState.disconnected);
    }
  }

  @override
  Future<void> connect(
    UsbPrinterDevice device, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _assertState(PrinterConnectionState.disconnected, 'connect');
    _setState(PrinterConnectionState.connecting);

    final SerialPort port = SerialPort(device.identifier);
    try {
      if (!port.openReadWrite()) {
        throw Exception(SerialPort.lastError?.message ?? 'Could not open port');
      }

      final SerialPortConfig config = SerialPortConfig()
        ..baudRate = kDefaultBaudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      port.config = config;

      // Send ESC @ to initialise the printer.
      port.write(Uint8List.fromList(cInit.codeUnits));

      _port = port;
      _setState(PrinterConnectionState.connected);
    } catch (e) {
      port.dispose();
      _setState(PrinterConnectionState.error);
      _setState(PrinterConnectionState.disconnected);
      throw PrinterConnectionException(
        'Failed to open serial port ${device.identifier}',
        cause: e,
      );
    }
  }

  @override
  Future<void> writeBytes(List<int> bytes) async {
    _assertState(PrinterConnectionState.connected, 'writeBytes');
    _setState(PrinterConnectionState.printing);
    try {
      _port!.write(Uint8List.fromList(bytes));
      _setState(PrinterConnectionState.connected);
    } catch (e) {
      _setState(PrinterConnectionState.error);
      _setState(PrinterConnectionState.disconnected);
      throw PrinterWriteException('USB serial write failed', cause: e);
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == PrinterConnectionState.disconnected) return;
    _setState(PrinterConnectionState.disconnecting);
    try {
      _reader?.close();
      _port?.close();
    } finally {
      _port?.dispose();
      _reader = null;
      _port = null;
      _setState(PrinterConnectionState.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
  }

  void _setState(PrinterConnectionState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _assertState(PrinterConnectionState required, String operation) {
    if (_state != required) {
      throw PrinterStateException(
        'Cannot $operation: expected $required but was $_state',
        currentState: _state,
        requiredState: required,
      );
    }
  }
}
