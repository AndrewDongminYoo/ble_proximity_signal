package com.andrew.signal

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.Base64
import java.util.Locale
import java.util.UUID

class BleProximitySignalPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var eventSink: EventChannel.EventSink? = null

    private var bluetoothAdapter: BluetoothAdapter? = null
    private var scanner: BluetoothLeScanner? = null
    private var advertiser: BluetoothLeAdvertiser? = null

    private var scanCallback: ScanCallback? = null
    private var advertiseCallback: AdvertiseCallback? = null

    // Normalized (hex lowercase) target token set (max 5 expected)
    private var targetTokenSet: Set<String> = emptySet()
    private var debugAllowAll: Boolean = false

    // Current service UUID used for scan/broadcast
    private var currentServiceUuid: UUID? = null

    override fun onAttachedToEngine(
        @NonNull binding: FlutterPlugin.FlutterPluginBinding,
    ) {
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "ble_proximity_signal")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "ble_proximity_signal/events")
        eventChannel.setStreamHandler(this)

        val bm = applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bm.adapter
    }

    override fun onDetachedFromEngine(
        @NonNull binding: FlutterPlugin.FlutterPluginBinding,
    ) {
        stopScanInternal()
        stopBroadcastInternal()

        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(
        @NonNull call: MethodCall,
        @NonNull result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "startBroadcast" -> {
                    val tokenStr =
                        call.argument<String>("token")
                            ?: return result.error("invalid_args", "Missing 'token'", null)
                    val serviceUuidStr =
                        call.argument<String>("serviceUuid")
                            ?: return result.error("invalid_args", "Missing 'serviceUuid'", null)

                    val txPower: Int? = call.argument<Int>("txPower") // optional (may be ignored)

                    startBroadcastInternal(tokenStr, serviceUuidStr, txPower)
                    result.success(null)
                }

                "stopBroadcast" -> {
                    stopBroadcastInternal()
                    result.success(null)
                }

                "startScan" -> {
                    val targetTokens =
                        call.argument<List<String>>("targetTokens")
                            ?: return result.error("invalid_args", "Missing 'targetTokens'", null)
                    val serviceUuidStr =
                        call.argument<String>("serviceUuid")
                            ?: return result.error("invalid_args", "Missing 'serviceUuid'", null)
                    val debugAllowAllArg = call.argument<Boolean>("debugAllowAll") ?: false

                    startScanInternal(targetTokens, serviceUuidStr, debugAllowAllArg)
                    result.success(null)
                }

                "stopScan" -> {
                    stopScanInternal(resetState = true)
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Throwable) {
            result.error("native_error", e.message, e.toString())
        }
    }

    // ----------------------------
    // Broadcast (Advertising)
    // ----------------------------

    private fun startBroadcastInternal(
        token: String,
        serviceUuidStr: String,
        txPower: Int?,
    ) {
        val adapter = bluetoothAdapter ?: throw IllegalStateException("Bluetooth not supported")
        if (!adapter.isEnabled) throw IllegalStateException("Bluetooth is off")

        val uuid = UUID.fromString(serviceUuidStr)
        currentServiceUuid = uuid

        val tokenBytes = decodeTokenToBytes(token)
        advertiser = adapter.bluetoothLeAdvertiser
            ?: throw IllegalStateException("BLE advertising not supported on this device")

        stopBroadcastInternal() // idempotent start

        val settingsBuilder =
            AdvertiseSettings
                .Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(false)
                .setTimeout(0)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)

        // Optional: map txPower hint crudely if given
        if (txPower != null) {
            val level =
                when {
                    txPower >= 3 -> AdvertiseSettings.ADVERTISE_TX_POWER_HIGH
                    txPower <= -6 -> AdvertiseSettings.ADVERTISE_TX_POWER_LOW
                    else -> AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM
                }
            settingsBuilder.setTxPowerLevel(level)
        }

        val parcelUuid = android.os.ParcelUuid(uuid)

        val data =
            AdvertiseData
                .Builder()
                .addServiceUuid(parcelUuid)
                .addServiceData(parcelUuid, tokenBytes)
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .build()

        advertiseCallback =
            object : AdvertiseCallback() {
                override fun onStartFailure(errorCode: Int) {
                    eventSink?.error("advertise_failed", "Advertising failed: $errorCode", null)
                }
            }

        advertiser?.startAdvertising(settingsBuilder.build(), data, advertiseCallback)
    }

    private fun stopBroadcastInternal() {
        val adv = advertiser ?: return
        val cb = advertiseCallback ?: return
        try {
            adv.stopAdvertising(cb)
        } catch (_: Throwable) {
            // ignore
        } finally {
            advertiseCallback = null
        }
    }

    // ----------------------------
    // Scan
    // ----------------------------

    private fun startScanInternal(
        targetTokens: List<String>,
        serviceUuidStr: String,
        debugAllowAll: Boolean,
    ) {
        val adapter = bluetoothAdapter ?: throw IllegalStateException("Bluetooth not supported")
        if (!adapter.isEnabled) throw IllegalStateException("Bluetooth is off")

        if (!debugAllowAll && targetTokens.size > 5) {
            throw IllegalArgumentException("targetTokens must be <= 5")
        }

        stopScanInternal(resetState = false) // idempotent start

        this.debugAllowAll = debugAllowAll
        val uuid = UUID.fromString(serviceUuidStr)
        currentServiceUuid = uuid

        // Normalize tokens to hex lowercase to compare
        targetTokenSet = if (debugAllowAll) emptySet() else targetTokens.map { normalizeTokenToHex(it) }.toSet()

        scanner = adapter.bluetoothLeScanner ?: throw IllegalStateException("BLE scanner not available")

        val parcelUuid = android.os.ParcelUuid(uuid)

        val filters =
            if (debugAllowAll) {
                emptyList()
            } else {
                listOf(
                    ScanFilter.Builder().setServiceUuid(parcelUuid).build(),
                )
            }

        val settings =
            ScanSettings
                .Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setReportDelay(0L)
                .build()

        scanCallback =
            object : ScanCallback() {
                override fun onScanResult(
                    callbackType: Int,
                    result: ScanResult,
                ) {
                    val record = result.scanRecord ?: return
                    val serviceData = record.getServiceData(parcelUuid)
                    val tokenHex = serviceData?.let { bytesToHexLower(it) }

                    if (!debugAllowAll) {
                        if (tokenHex == null || !targetTokenSet.contains(tokenHex)) return
                    }

                    val deviceId = result.device?.address
                    val deviceName = result.device?.name
                    val localName = record.deviceName
                    val manufacturerDataLen = manufacturerDataLength(record)
                    val targetToken = tokenHex ?: deviceId ?: ""

                    val payload =
                        hashMapOf<String, Any>(
                            "targetToken" to targetToken,
                            "rssi" to result.rssi,
                            // Use epoch ms to match iOS and public contract.
                            "timestampMs" to System.currentTimeMillis(),
                        )
                    deviceId?.let { payload["deviceId"] = it }
                    deviceName?.let { payload["deviceName"] = it }
                    localName?.let { payload["localName"] = it }
                    manufacturerDataLen?.let { payload["manufacturerDataLen"] = it }
                    eventSink?.success(payload)
                }

                override fun onScanFailed(errorCode: Int) {
                    eventSink?.error("scan_failed", "Scan failed: $errorCode", null)
                }
            }

        scanner?.startScan(filters, settings, scanCallback)
    }

    private fun stopScanInternal(resetState: Boolean) {
        val sc = scanner
        val cb = scanCallback
        if (sc != null && cb != null) {
            try {
                sc.stopScan(cb)
            } catch (_: Throwable) {
            }
        }
        scanCallback = null
        if (resetState) {
            targetTokenSet = emptySet()
            debugAllowAll = false
        }
    }

    private fun manufacturerDataLength(record: ScanRecord): Int? {
        val data = record.manufacturerSpecificData ?: return null
        if (data.size() == 0) return null
        var total = 0
        for (i in 0 until data.size()) {
            val bytes = data.valueAt(i)
            total += bytes?.size ?: 0
        }
        return total
    }

    // ----------------------------
    // Token helpers
    // ----------------------------

    private fun normalizeTokenToHex(token: String): String {
        val bytes = decodeTokenToBytes(token)
        return bytesToHexLower(bytes)
    }

    private fun decodeTokenToBytes(token: String): ByteArray {
        // Try hex first
        val hex = token.trim()
        if (hex.matches(Regex("^[0-9a-fA-F]+$")) && hex.length % 2 == 0) {
            return hexToBytes(hex)
        }

        // Then try base64url/base64
        return try {
            // base64url may be missing padding
            val normalized = token.replace('-', '+').replace('_', '/')
            val padded =
                when (normalized.length % 4) {
                    2 -> "$normalized=="
                    3 -> "$normalized="
                    else -> normalized
                }
            Base64.getDecoder().decode(padded)
        } catch (e: Throwable) {
            throw IllegalArgumentException("Invalid token format (expected hex or base64url/base64)")
        }
    }

    private fun hexToBytes(hex: String): ByteArray {
        val clean = hex.lowercase(Locale.US)
        val len = clean.length
        val out = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            val b = clean.substring(i, i + 2).toInt(16)
            out[i / 2] = b.toByte()
            i += 2
        }
        return out
    }

    private fun bytesToHexLower(bytes: ByteArray): String {
        val sb = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }
}
