package com.elriztechnology.unified_esc_pos_printer

import android.app.Activity
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry

class UnifiedEscPosPrinterPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var bleScanEventChannel: EventChannel
    private lateinit var btScanEventChannel: EventChannel
    private lateinit var connectionStateEventChannel: EventChannel

    private lateinit var permissionHandler: PermissionHandler
    private lateinit var bleManager: BleManager
    private lateinit var bluetoothClassicManager: BluetoothClassicManager
    private lateinit var usbPrinterClassManager: UsbPrinterClassManager

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger
        val context = binding.applicationContext

        methodChannel = MethodChannel(messenger, "com.elriztechnology.unified_esc_pos_printer/methods")
        methodChannel.setMethodCallHandler(this)

        bleScanEventChannel = EventChannel(messenger, "com.elriztechnology.unified_esc_pos_printer/ble_scan")
        btScanEventChannel = EventChannel(messenger, "com.elriztechnology.unified_esc_pos_printer/bt_scan")
        connectionStateEventChannel = EventChannel(messenger, "com.elriztechnology.unified_esc_pos_printer/connection_state")

        permissionHandler = PermissionHandler()
        bleManager = BleManager(context)
        bluetoothClassicManager = BluetoothClassicManager(context)
        usbPrinterClassManager = UsbPrinterClassManager(context)

        bleScanEventChannel.setStreamHandler(bleManager.scanStreamHandler)
        btScanEventChannel.setStreamHandler(bluetoothClassicManager.scanStreamHandler)
        connectionStateEventChannel.setStreamHandler(ConnectionStateStreamHandler(bleManager, bluetoothClassicManager))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        bleScanEventChannel.setStreamHandler(null)
        btScanEventChannel.setStreamHandler(null)
        connectionStateEventChannel.setStreamHandler(null)
        bleManager.dispose()
        bluetoothClassicManager.dispose()
        usbPrinterClassManager.dispose()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        permissionHandler.setActivity(binding.activity)
        bluetoothClassicManager.setActivity(binding.activity)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activity = null
        activityBinding = null
        permissionHandler.setActivity(null)
        bluetoothClassicManager.setActivity(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        permissionHandler.setActivity(binding.activity)
        bluetoothClassicManager.setActivity(binding.activity)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activity = null
        activityBinding = null
        permissionHandler.setActivity(null)
        bluetoothClassicManager.setActivity(null)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        return permissionHandler.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Permissions
            "requestPermissions" -> permissionHandler.requestPermissions(result)

            // BLE
            "startBleScan" -> {
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 5000
                bleManager.startScan(timeoutMs.toLong(), result)
            }
            "stopBleScan" -> bleManager.stopScan(result)
            "getBondedBleDevices" -> bleManager.getBondedBleDevices(result)
            "bleConnect" -> {
                val deviceId = call.argument<String>("deviceId")!!
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000
                val serviceUuid = call.argument<String>("serviceUuid")
                val characteristicUuid = call.argument<String>("characteristicUuid")
                bleManager.connect(deviceId, timeoutMs.toLong(), serviceUuid, characteristicUuid, result)
            }
            "bleGetMtu" -> bleManager.getMtu(result)
            "bleSupportsWriteWithoutResponse" -> bleManager.supportsWriteWithoutResponse(result)
            "bleWrite" -> {
                val data = call.argument<ByteArray>("data")!!
                val withoutResponse = call.argument<Boolean>("withoutResponse") ?: false
                bleManager.write(data, withoutResponse, result)
            }
            "bleDisconnect" -> bleManager.disconnect(result)

            // Bluetooth Classic
            "getBondedDevices" -> bluetoothClassicManager.getBondedDevices(result)
            "startBtDiscovery" -> {
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 5000
                bluetoothClassicManager.startDiscovery(timeoutMs.toLong(), result)
            }
            "stopBtDiscovery" -> bluetoothClassicManager.stopDiscovery(result)
            "btConnect" -> {
                val address = call.argument<String>("address")!!
                val timeoutMs = call.argument<Int>("timeoutMs") ?: 10000
                bluetoothClassicManager.connect(address, timeoutMs.toLong(), result)
            }
            "btWrite" -> {
                val data = call.argument<ByteArray>("data")!!
                bluetoothClassicManager.write(data, result)
            }
            "btDisconnect" -> bluetoothClassicManager.disconnect(result)

            // USB Printer Class (interface class 0x07) — fallback for printers
            // that don't expose a CDC / serial-chip interface and therefore
            // cannot be opened by the `usb_serial` package.
            "usbListDevices" -> usbPrinterClassManager.listUsbDevices(result)
            "usbOpenPrinterClass" -> {
                val vid = call.argument<Int>("vid")!!
                val pid = call.argument<Int>("pid")!!
                usbPrinterClassManager.openPrinterClass(vid, pid, result)
            }
            "usbWrite" -> {
                val data = call.argument<ByteArray>("data")!!
                usbPrinterClassManager.write(data, result)
            }
            "usbClose" -> usbPrinterClassManager.close(result)

            else -> result.notImplemented()
        }
    }
}

/// Merges connection state events from both BLE and Classic managers.
class ConnectionStateStreamHandler(
    private val bleManager: BleManager,
    private val btManager: BluetoothClassicManager
) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        bleManager.connectionStateCallback = { state ->
            events?.success(mapOf("type" to "ble", "state" to state))
        }
        btManager.connectionStateCallback = { state ->
            events?.success(mapOf("type" to "bt", "state" to state))
        }
    }

    override fun onCancel(arguments: Any?) {
        bleManager.connectionStateCallback = null
        btManager.connectionStateCallback = null
        eventSink = null
    }
}
