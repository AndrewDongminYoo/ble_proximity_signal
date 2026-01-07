package com.andrew.signal

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
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

    // Debug: discovered devices for connect + discover
    private val discoveredDevices: MutableMap<String, BluetoothDevice> = mutableMapOf()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingDiscovery: DiscoveryRequest? = null

    private data class DiscoveryRequest(
        val deviceId: String,
        val result: MethodChannel.Result,
        var gatt: BluetoothGatt? = null,
        var timeout: Runnable? = null,
    )

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
        pendingDiscovery?.gatt?.disconnect()
        pendingDiscovery?.gatt?.close()
        pendingDiscovery = null
        discoveredDevices.clear()

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

                "debugDiscoverServices" -> {
                    val deviceId =
                        call.argument<String>("deviceId")
                            ?: return result.error("invalid_args", "Missing 'deviceId'", null)
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 8000
                    debugDiscoverServicesInternal(deviceId, timeoutMs, result)
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
                    result.device?.address?.let { address ->
                        discoveredDevices[address] = result.device
                    }
                    val serviceData = record.getServiceData(parcelUuid)
                    val tokenHexFromServiceData = serviceData?.let { bytesToHexLower(it) }

                    val deviceId = result.device?.address
                    val deviceName = result.device?.name
                    val localName = record.deviceName
                    val tokenHexFromLocalName =
                        localName?.let { name ->
                            runCatching { normalizeTokenToHex(name) }.getOrNull()
                        }
                    val tokenHex = tokenHexFromServiceData ?: tokenHexFromLocalName

                    if (!debugAllowAll) {
                        if (tokenHex == null || !targetTokenSet.contains(tokenHex)) return
                    }

                    val manufacturerDataLen = manufacturerDataLength(record)
                    val manufacturerDataHex = manufacturerDataHex(record)
                    val sd = record.serviceData
                    val serviceDataLen = sd?.values?.sumOf { it.size } ?: 0
                    val serviceDataUuids = sd?.keys?.map { it.uuid.toString() } ?: emptyList()
                    val serviceDataHex =
                        sd
                            ?.entries
                            ?.associate { entry ->
                                entry.key.uuid.toString() to bytesToHexLower(entry.value)
                            }.orEmpty()
                    val serviceUuids = record.serviceUuids?.map { it.uuid.toString() } ?: emptyList()
                    val targetToken = tokenHex ?: deviceId ?: localName ?: ""
                    val localNameHex =
                        localName?.let { bytesToHexLower(it.toByteArray(Charsets.UTF_8)) }

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
                    localNameHex?.let { payload["localNameHex"] = it }
                    manufacturerDataLen?.let { payload["manufacturerDataLen"] = it }
                    manufacturerDataHex?.let { payload["manufacturerDataHex"] = it }
                    if (serviceDataLen > 0) {
                        payload["serviceDataLen"] = serviceDataLen
                    }
                    if (serviceDataUuids.isNotEmpty()) {
                        payload["serviceDataUuids"] = serviceDataUuids
                    }
                    if (serviceDataHex.isNotEmpty()) {
                        payload["serviceDataHex"] = serviceDataHex
                    }
                    if (serviceUuids.isNotEmpty()) {
                        payload["serviceUuids"] = serviceUuids
                    }
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
            discoveredDevices.clear()
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

    private fun manufacturerDataHex(record: ScanRecord): String? {
        val data = record.manufacturerSpecificData ?: return null
        if (data.size() == 0) return null
        val parts = mutableListOf<String>()
        for (i in 0 until data.size()) {
            val id = data.keyAt(i)
            val bytes = data.valueAt(i) ?: continue
            val hex = bytesToHexLower(bytes)
            parts.add(String.format(Locale.US, "%04x:%s", id, hex))
        }
        return if (parts.isEmpty()) null else parts.joinToString(",")
    }

    // ----------------------------
    // Debug connect + discover
    // ----------------------------

    private fun debugDiscoverServicesInternal(
        deviceId: String,
        timeoutMs: Int,
        result: MethodChannel.Result,
    ) {
        if (pendingDiscovery != null) {
            result.error("busy", "Discovery already in progress", null)
            return
        }
        val adapter =
            bluetoothAdapter ?: run {
                result.error("unsupported", "Bluetooth not supported", null)
                return
            }
        val device =
            discoveredDevices[deviceId]
                ?: runCatching { adapter.getRemoteDevice(deviceId) }.getOrNull()
        if (device == null) {
            result.error("not_found", "Device not found: $deviceId", null)
            return
        }

        val request = DiscoveryRequest(deviceId = deviceId, result = result)
        pendingDiscovery = request

        val callback =
            object : BluetoothGattCallback() {
                override fun onConnectionStateChange(
                    gatt: BluetoothGatt,
                    status: Int,
                    newState: Int,
                ) {
                    if (pendingDiscovery?.gatt != gatt) return
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        finishDiscoveryError("Connection failed: $status")
                        return
                    }
                    if (newState == BluetoothProfile.STATE_CONNECTED) {
                        gatt.discoverServices()
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        finishDiscoveryError("Disconnected")
                    }
                }

                override fun onServicesDiscovered(
                    gatt: BluetoothGatt,
                    status: Int,
                ) {
                    if (pendingDiscovery?.gatt != gatt) return
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        finishDiscoveryError("Service discovery failed: $status")
                        return
                    }
                    val dump = buildGattDump(gatt, deviceId)
                    finishDiscoverySuccess(dump)
                }
            }

        val gatt =
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    device.connectGatt(applicationContext, false, callback, BluetoothDevice.TRANSPORT_LE)
                } else {
                    device.connectGatt(applicationContext, false, callback)
                }
            } catch (e: SecurityException) {
                pendingDiscovery = null
                result.error("permission_denied", "Missing BLUETOOTH_CONNECT permission", null)
                return
            }
        if (gatt == null) {
            pendingDiscovery = null
            result.error("connect_failed", "Unable to connect to $deviceId", null)
            return
        }
        request.gatt = gatt
        val timeout =
            Runnable {
                finishDiscoveryError("Timeout after ${timeoutMs}ms")
            }
        request.timeout = timeout
        mainHandler.postDelayed(timeout, timeoutMs.toLong())
    }

    private fun finishDiscoverySuccess(dump: String) {
        val request = pendingDiscovery ?: return
        pendingDiscovery = null
        request.timeout?.let { mainHandler.removeCallbacks(it) }
        request.result.success(dump)
        request.gatt?.disconnect()
        request.gatt?.close()
    }

    private fun finishDiscoveryError(message: String) {
        val request = pendingDiscovery ?: return
        pendingDiscovery = null
        request.timeout?.let { mainHandler.removeCallbacks(it) }
        request.result.error("debug_discover_failed", message, null)
        request.gatt?.disconnect()
        request.gatt?.close()
    }

    private fun buildGattDump(
        gatt: BluetoothGatt,
        deviceId: String,
    ): String {
        val sb = StringBuilder()
        sb.append("deviceId: ").append(deviceId).append('\n')
        val name = gatt.device?.name ?: "unknown"
        sb.append("name: ").append(name).append('\n')
        val services = gatt.services
        for (service in services) {
            val typeLabel =
                if (service.type == BluetoothGattService.SERVICE_TYPE_PRIMARY) "primary" else "secondary"
            sb
                .append("service ")
                .append(service.uuid)
                .append(" (")
                .append(typeLabel)
                .append(')')
                .append('\n')
            for (ch in service.characteristics) {
                sb.append("  char ").append(ch.uuid)
                sb.append(" props=").append(describeGattProperties(ch.properties)).append('\n')
            }
        }
        return sb.toString().trimEnd()
    }

    private fun describeGattProperties(properties: Int): String {
        val parts = mutableListOf<String>()
        if (properties and BluetoothGattCharacteristic.PROPERTY_READ != 0) parts.add("read")
        if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) parts.add("write")
        if (properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0) {
            parts.add("writeNoResponse")
        }
        if (properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) parts.add("notify")
        if (properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) parts.add("indicate")
        if (properties and BluetoothGattCharacteristic.PROPERTY_SIGNED_WRITE != 0) {
            parts.add("signedWrite")
        }
        if (properties and BluetoothGattCharacteristic.PROPERTY_EXTENDED_PROPS != 0) {
            parts.add("extendedProps")
        }
        return if (parts.isEmpty()) "none" else parts.joinToString("|")
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
