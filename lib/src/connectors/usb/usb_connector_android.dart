import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:usb_serial/usb_serial.dart';

import '../../core/commands.dart';
import '../../exceptions/printer_exception.dart';
import '../../models/printer_connection_state.dart';
import '../../models/printer_device.dart';
import '../../platform/usb_platform_channel_android.dart';
import 'usb_connector_interface.dart';

/// USB connector for Android.
///
/// Tries two paths in order based on the printer's USB interface class:
///
/// 1. **CDC / serial-chip path (default):** uses the `usb_serial` plugin.
///    Works for FTDI, CP210x, PL2303, CH34x, and USB CDC ACM devices.
/// 2. **USB Printer Class path (fallback):** uses the native Android
///    `UsbManager` + `bulkTransfer` via [UsbPlatformChannelAndroid].
///    Engaged when the device exposes an interface with class `0x07`
///    (USB_CLASS_PRINTER). Covers most generic ESC/POS thermal printers.
class UsbConnectorImpl extends UsbConnectorBase {
  UsbPort? _port;
  bool _usingPrinterClass = false;

  PrinterConnectionState _state = PrinterConnectionState.disconnected;
  final StreamController<PrinterConnectionState> _stateController =
      StreamController<PrinterConnectionState>.broadcast();

  final UsbPlatformChannelAndroid _native = UsbPlatformChannelAndroid.instance;

  @override
  Stream<PrinterConnectionState> get stateStream => _stateController.stream;

  @override
  PrinterConnectionState get state => _state;

  @override
  Stream<List<UsbPrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    _setState(PrinterConnectionState.scanning);
    final List<UsbDevice> devices = await UsbSerial.listDevices();
    _setState(PrinterConnectionState.disconnected);

    if (devices.isNotEmpty) {
      yield devices
          .map((d) => UsbPrinterDevice(
                name: d.productName ?? 'USB Device ${d.vid}:${d.pid}',
                identifier: '${d.vid}:${d.pid}',
                usbPlatform: UsbPlatform.android,
              ))
          .toList();
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

    final parts = device.identifier.split(':');
    final int? vid = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final int? pid = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (vid == null || pid == null) {
      _failConnect();
      throw PrinterConnectionException(
        'Invalid USB device identifier: ${device.identifier}',
      );
    }

    // Probe the device's interface classes via the native channel so we
    // can pick the right path up front. If the native probe fails for any
    // reason (older host, plugin issue), fall through to the usb_serial
    // path so behavior is no worse than before this connector supported
    // Printer Class.
    bool isPrinterClass = false;
    try {
      final list = await _native.listUsbDevices();
      for (final d in list) {
        if (d['vid'] == vid && d['pid'] == pid) {
          isPrinterClass = (d['hasPrinterClass'] as bool?) ?? false;
          break;
        }
      }
    } catch (_) {
      // Native unavailable; fall back to usb_serial path below.
    }

    if (isPrinterClass) {
      try {
        await _native.openPrinterClass(vid: vid, pid: pid);
        await _native.write(cInit.codeUnits);
        _usingPrinterClass = true;
        _setState(PrinterConnectionState.connected);
        return;
      } catch (e) {
        _failConnect();
        throw PrinterConnectionException(
          'Failed to open USB printer-class device ${device.identifier}',
          cause: e,
        );
      }
    }

    // CDC / serial-chip path via usb_serial.
    final List<UsbDevice> devices = await UsbSerial.listDevices();
    UsbDevice? found;
    for (final UsbDevice d in devices) {
      if ('${d.vid}:${d.pid}' == device.identifier) {
        found = d;
        break;
      }
    }

    if (found == null) {
      _failConnect();
      throw PrinterNotFoundException(
        'USB device ${device.identifier} not found',
      );
    }

    UsbPort? port;
    try {
      port = await found.create();
      if (port == null) throw Exception('Could not create UsbPort');

      final bool opened = await port.open();
      if (!opened) throw Exception('UsbPort.open() returned false');

      await port.setDTR(true);
      await port.setRTS(true);
      port.setPortParameters(
        kDefaultBaudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      await port.write(Uint8List.fromList(cInit.codeUnits));

      _port = port;
      _setState(PrinterConnectionState.connected);
    } catch (e) {
      await port?.close();
      _failConnect();
      throw PrinterConnectionException(
        'Failed to open USB device ${device.identifier}',
        cause: e,
      );
    }
  }

  @override
  Future<void> writeBytes(List<int> bytes) async {
    _assertState(PrinterConnectionState.connected, 'writeBytes');
    _setState(PrinterConnectionState.printing);
    try {
      if (_usingPrinterClass) {
        await _native.write(bytes);
      } else {
        await _port!.write(Uint8List.fromList(bytes));
      }
      _setState(PrinterConnectionState.connected);
    } catch (e) {
      _setState(PrinterConnectionState.error);
      _setState(PrinterConnectionState.disconnected);
      throw PrinterWriteException('USB write failed', cause: e);
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == PrinterConnectionState.disconnected) return;
    _setState(PrinterConnectionState.disconnecting);
    try {
      if (_usingPrinterClass) {
        await _native.close();
      } else {
        await _port?.close();
      }
    } finally {
      _port = null;
      _usingPrinterClass = false;
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

  void _failConnect() {
    _setState(PrinterConnectionState.error);
    _setState(PrinterConnectionState.disconnected);
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
