import 'dart:async';

import 'package:flutter/services.dart';

/// Platform channel wrapper for the native Android USB Printer Class path.
///
/// Used by [UsbConnectorImpl] on Android to talk to printers that don't
/// expose a CDC / serial-chip interface and therefore can't be opened by
/// the `usb_serial` package. The native side opens the device via
/// `UsbManager`, claims the interface with class `0x07`, and writes via
/// `UsbDeviceConnection.bulkTransfer`.
class UsbPlatformChannelAndroid {
  UsbPlatformChannelAndroid._();

  static final UsbPlatformChannelAndroid instance =
      UsbPlatformChannelAndroid._();

  static const MethodChannel _method = MethodChannel(
    'com.elriztechnology.unified_esc_pos_printer/methods',
  );

  /// Returns the full list of USB devices currently attached, including
  /// each device's interface classes and whether the app already has
  /// permission to open it.
  ///
  /// Each entry contains: `vid`, `pid`, `deviceName`, `productName`,
  /// `manufacturerName`, `interfaceClasses` (list of ints),
  /// `hasPrinterClass` (bool), `hasPermission` (bool).
  Future<List<Map<String, dynamic>>> listUsbDevices() async {
    final raw = await _method.invokeMethod('usbListDevices');
    return (raw as List)
        .cast<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Open the USB Printer Class device with the given VID/PID. Requests
  /// USB permission from the user if not already granted.
  Future<void> openPrinterClass({required int vid, required int pid}) async {
    await _method.invokeMethod('usbOpenPrinterClass', {'vid': vid, 'pid': pid});
  }

  /// Write raw bytes to the connected printer's bulk-OUT endpoint.
  Future<void> write(List<int> bytes) async {
    await _method.invokeMethod('usbWrite', {
      'data': Uint8List.fromList(bytes),
    });
  }

  /// Release the interface and close the underlying USB device.
  Future<void> close() async {
    await _method.invokeMethod('usbClose');
  }
}
