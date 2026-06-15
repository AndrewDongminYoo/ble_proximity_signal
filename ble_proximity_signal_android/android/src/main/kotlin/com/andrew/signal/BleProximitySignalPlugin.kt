package com.andrew.signal

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import androidx.annotation.RequiresPermission
import androidx.core.app.ActivityCompat
import androidx.core.util.isEmpty
import androidx.core.util.size
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.Base64
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class BleProximitySignalPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val TAG = "BleProximitySignal"
        private const val DEFAULT_DISCOVERY_TIMEOUT_MS = 8000
        private const val MAX_TARGET_TOKENS = 5
        private const val DEFAULT_TX_POWER = AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM
        private const val PERMISSION_REQUEST_CODE = 0xB1E
    }

    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var availabilityChannel: EventChannel

    // Thread-safety: lock for synchronized access to mutable state
    private val lock = Any()
    private var eventSink: EventChannel.EventSink? = null
    private var availabilitySink: EventChannel.EventSink? = null

    // Activity binding for runtime permission requests (ActivityAware)
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    // Receiver for Bluetooth adapter on/off state changes
    private var bluetoothStateReceiver: BroadcastReceiver? = null

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

    // Debug: discovered devices for connect + discover (thread-safe)
    private val discoveredDevices: ConcurrentHashMap<String, BluetoothDevice> = ConcurrentHashMap()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingDiscovery: DiscoveryRequest? = null

    private data class DiscoveryRequest(
        val deviceId: String,
        val result: MethodChannel.Result,
        var gatt: BluetoothGatt? = null,
        var timeout: Runnable? = null,
    )

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "ble_proximity_signal")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "ble_proximity_signal/events")
        eventChannel.setStreamHandler(this)

        availabilityChannel = EventChannel(binding.binaryMessenger, "ble_proximity_signal/availability")
        availabilityChannel.setStreamHandler(availabilityStreamHandler)

        val bm = applicationContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bm.adapter
    }

    @RequiresPermission(
        allOf = [Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_SCAN],
    )
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Cancel all pending Handler callbacks to prevent memory leaks
        mainHandler.removeCallbacksAndMessages(null)

        stopScanInternal(resetState = true)
        stopBroadcastInternal()

        // Clean up pending discovery
        pendingDiscovery?.let {
            it.timeout?.let { timeout -> mainHandler.removeCallbacks(timeout) }
            it.gatt?.disconnect()
            it.gatt?.close()
        }
        pendingDiscovery = null
        discoveredDevices.clear()

        unregisterBluetoothStateReceiver()

        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        availabilityChannel.setStreamHandler(null)
        synchronized(lock) {
            eventSink = null
            availabilitySink = null
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        synchronized(lock) {
            eventSink = events
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) {
            eventSink = null
        }
    }

    // ----------------------------
    // ActivityAware (runtime permission requests)
    // ----------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        // Fail any in-flight request so the Dart future never hangs.
        pendingPermissionResult?.error(
            "activity_detached",
            "Activity detached before the permission request completed",
            null,
        )
        pendingPermissionResult = null
    }

    @RequiresPermission(
        allOf = [Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT],
    )
    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
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
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: DEFAULT_DISCOVERY_TIMEOUT_MS
                    debugDiscoverServicesInternal(deviceId, timeoutMs, result)
                }

                "checkPermissions" -> {
                    result.success(currentPermissionStatus())
                }

                "requestPermissions" -> {
                    // Resolves the result asynchronously via onRequestPermissionsResult.
                    requestPermissionsInternal(result)
                }

                "checkAvailability" -> {
                    result.success(computeAvailability())
                }

                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: SecurityException) {
            result.error("permission_denied", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("illegal_state", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("invalid_args", e.message, null)
        } catch (e: Exception) {
            result.error("native_error", e.message, e.toString())
        }
    }

    // ----------------------------
    // Broadcast (Advertising)
    // ----------------------------

    @RequiresPermission(
        allOf = [Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT],
    )
    private fun startBroadcastInternal(
        token: String,
        serviceUuidStr: String,
        txPower: Int?,
    ) {
        // Check runtime permissions on Android 12+
        if (!checkBluetoothPermissions()) {
            throw SecurityException(
                "Missing Bluetooth permissions. On Android 12+, you need: " +
                    "BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT, BLUETOOTH_SCAN",
            )
        }

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
                .setTxPowerLevel(DEFAULT_TX_POWER)

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

        val parcelUuid = ParcelUuid(uuid)

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
                    sendError("advertise_failed", "Advertising failed: $errorCode")
                }
            }

        advertiser?.startAdvertising(settingsBuilder.build(), data, advertiseCallback)
    }

    @RequiresPermission(allOf = [Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE])
    private fun stopBroadcastInternal() {
        val adv = advertiser ?: return
        val cb = advertiseCallback ?: return
        try {
            adv.stopAdvertising(cb)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to stop advertising", e)
        } finally {
            advertiseCallback = null
        }
    }

    // ----------------------------
    // Scan
    // ----------------------------

    @RequiresPermission(allOf = [Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_SCAN])
    private fun startScanInternal(
        targetTokens: List<String>,
        serviceUuidStr: String,
        debugAllowAll: Boolean,
    ) {
        // Check runtime permissions on Android 12+
        if (!checkBluetoothPermissions()) {
            throw SecurityException(
                "Missing Bluetooth permissions. On Android 12+, you need: " +
                    "BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT, BLUETOOTH_SCAN",
            )
        }

        val adapter = bluetoothAdapter ?: throw IllegalStateException("Bluetooth not supported")
        if (!adapter.isEnabled) throw IllegalStateException("Bluetooth is off")

        if (!debugAllowAll && targetTokens.size > MAX_TARGET_TOKENS) {
            throw IllegalArgumentException("targetTokens must be <= $MAX_TARGET_TOKENS")
        }

        stopScanInternal(resetState = false) // idempotent start

        this.debugAllowAll = debugAllowAll
        val uuid = UUID.fromString(serviceUuidStr)
        currentServiceUuid = uuid

        // Normalize tokens to hex lowercase to compare
        targetTokenSet =
            if (debugAllowAll) emptySet() else targetTokens.map { normalizeTokenToHex(it) }.toSet()

        scanner =
            adapter.bluetoothLeScanner ?: throw IllegalStateException("BLE scanner not available")

        val parcelUuid = ParcelUuid(uuid)

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
                @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
                override fun onScanResult(
                    callbackType: Int,
                    result: ScanResult,
                ) {
                    val record = result.scanRecord ?: return

                    // Store discovered device for debug/discovery
                    result.device?.address?.let { address ->
                        discoveredDevices[address] = result.device
                    }

                    // Build and send payload (returns null if filtered out)
                    buildScanPayload(result, record, parcelUuid)?.let { payload ->
                        sendEvent(payload)
                    }
                }

                override fun onScanFailed(errorCode: Int) {
                    sendError("scan_failed", "Scan failed: $errorCode")
                }
            }

        scanner?.startScan(filters, settings, scanCallback)
    }

    @RequiresPermission(Manifest.permission.BLUETOOTH_SCAN)
    private fun stopScanInternal(resetState: Boolean) {
        val sc = scanner
        val cb = scanCallback
        if (sc != null && cb != null) {
            try {
                sc.stopScan(cb)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to stop scan", e)
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
        if (data.isEmpty()) return null
        var total = 0
        for (i in 0 until data.size) {
            val bytes = data.valueAt(i)
            total += bytes?.size ?: 0
        }
        return total
    }

    private fun manufacturerDataHex(record: ScanRecord): String? {
        val data = record.manufacturerSpecificData ?: return null
        if (data.isEmpty()) return null
        val parts = mutableListOf<String>()
        for (i in 0 until data.size) {
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

    @SuppressLint("MissingPermission")
    private fun debugDiscoverServicesInternal(
        deviceId: String,
        timeoutMs: Int,
        result: MethodChannel.Result,
    ) {
        // Check runtime permissions on Android 12+
        if (!checkBluetoothPermissions()) {
            result.error(
                "permission_denied",
                "Missing Bluetooth permissions. On Android 12+, you need: " +
                    "BLUETOOTH_ADVERTISE, BLUETOOTH_CONNECT, BLUETOOTH_SCAN",
                null,
            )
            return
        }

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
                @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
                override fun onConnectionStateChange(
                    gatt: BluetoothGatt,
                    status: Int,
                    newState: Int,
                ) {
                    if (pendingDiscovery?.gatt != gatt) {
                        // Orphaned connection - clean it up to prevent resource leak
                        gatt.disconnect()
                        gatt.close()
                        return
                    }
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

                @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
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
                device.connectGatt(
                    applicationContext,
                    false,
                    callback,
                    BluetoothDevice.TRANSPORT_LE,
                )
            } catch (_: SecurityException) {
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

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    private fun finishDiscoverySuccess(dump: String) {
        val request = pendingDiscovery ?: return
        pendingDiscovery = null
        request.timeout?.let { mainHandler.removeCallbacks(it) }
        request.result.success(dump)
        request.gatt?.disconnect()
        request.gatt?.close()
    }

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    private fun finishDiscoveryError(message: String) {
        val request = pendingDiscovery ?: return
        pendingDiscovery = null
        request.timeout?.let { mainHandler.removeCallbacks(it) }
        request.result.error("debug_discover_failed", message, null)
        request.gatt?.disconnect()
        request.gatt?.close()
    }

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
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

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    private fun normalizeTokenToHex(token: String): String {
        val bytes = decodeTokenToBytes(token)
        return bytesToHexLower(bytes)
    }

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
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
        } catch (_: Exception) {
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

    /**
     * Checks if all required Bluetooth permissions are granted.
     *
     * - Android 12+ (API 31+): BLUETOOTH_SCAN, BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE.
     * - Android 6-11 (API 23-30): BLE scanning requires ACCESS_FINE_LOCATION at
     *   runtime. minSdk for this plugin is 26, so API 26-30 all share this path.
     *
     * @return true if all required permissions are granted, false otherwise
     */
    private fun checkBluetoothPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val hasConnect =
                applicationContext.checkSelfPermission(
                    Manifest.permission.BLUETOOTH_CONNECT,
                ) == PackageManager.PERMISSION_GRANTED

            val hasScan =
                applicationContext.checkSelfPermission(
                    Manifest.permission.BLUETOOTH_SCAN,
                ) == PackageManager.PERMISSION_GRANTED

            val hasAdvertise =
                applicationContext.checkSelfPermission(
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                ) == PackageManager.PERMISSION_GRANTED

            return hasConnect && hasScan && hasAdvertise
        }
        // API 23-30: ACCESS_FINE_LOCATION is required at runtime for BLE scanning.
        return applicationContext.checkSelfPermission(
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
    }

    // ----------------------------
    // Permissions + availability
    // ----------------------------

    /** Maps the current grant state to the Dart [BlePermissionStatus] wire name. */
    private fun currentPermissionStatus(): String = if (checkBluetoothPermissions()) "granted" else "denied"

    /**
     * Requests the Bluetooth runtime permissions and resolves [result] once the
     * user has responded (via [onRequestPermissionsResult]).
     *
     * The permission set depends on the platform:
     * - API 31+: BLUETOOTH_SCAN, BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE.
     * - API 26-30: ACCESS_FINE_LOCATION (required at runtime for BLE scanning).
     */
    private fun requestPermissionsInternal(result: MethodChannel.Result) {
        if (checkBluetoothPermissions()) {
            result.success("granted")
            return
        }
        val act = activity
        if (act == null) {
            result.error(
                "no_activity",
                "requestPermissions requires a foreground Activity",
                null,
            )
            return
        }
        if (pendingPermissionResult != null) {
            result.error("busy", "A permission request is already in progress", null)
            return
        }
        pendingPermissionResult = result
        val permissions =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                arrayOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT,
                    Manifest.permission.BLUETOOTH_ADVERTISE,
                )
            } else {
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        ActivityCompat.requestPermissions(act, permissions, PERMISSION_REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val result = pendingPermissionResult ?: return false
        pendingPermissionResult = null

        val allGranted =
            grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        val status =
            when {
                allGranted -> {
                    "granted"
                }

                else -> {
                    val act = activity
                    val permanentlyDenied =
                        act != null &&
                            permissions.indices.any { i ->
                                grantResults.getOrNull(i) != PackageManager.PERMISSION_GRANTED &&
                                    !ActivityCompat.shouldShowRequestPermissionRationale(act, permissions[i])
                            }
                    if (permanentlyDenied) "permanentlyDenied" else "denied"
                }
            }
        result.success(status)
        // Authorization just changed; push the new availability so subscribers to
        // availabilityChanges see ready/unauthorized without waiting for an adapter
        // ACTION_STATE_CHANGED broadcast or a resubscribe.
        sendAvailability(computeAvailability())
        return true
    }

    /** Computes the current [BleAvailability] wire name. */
    private fun computeAvailability(): String {
        val adapter = bluetoothAdapter ?: return "unsupported"
        if (!checkBluetoothPermissions()) return "unauthorized"
        return if (adapter.isEnabled) "ready" else "poweredOff"
    }

    private val availabilityStreamHandler =
        object : EventChannel.StreamHandler {
            override fun onListen(
                arguments: Any?,
                events: EventChannel.EventSink?,
            ) {
                synchronized(lock) { availabilitySink = events }
                registerBluetoothStateReceiver()
                // Emit the current state immediately so listeners get an initial value.
                sendAvailability(computeAvailability())
            }

            override fun onCancel(arguments: Any?) {
                synchronized(lock) { availabilitySink = null }
                unregisterBluetoothStateReceiver()
            }
        }

    private fun registerBluetoothStateReceiver() {
        if (bluetoothStateReceiver != null) return
        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(
                    context: Context?,
                    intent: Intent?,
                ) {
                    if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                        sendAvailability(computeAvailability())
                    }
                }
            }
        bluetoothStateReceiver = receiver
        applicationContext.registerReceiver(
            receiver,
            IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED),
        )
    }

    private fun unregisterBluetoothStateReceiver() {
        bluetoothStateReceiver?.let { receiver ->
            try {
                applicationContext.unregisterReceiver(receiver)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "Receiver was not registered", e)
            }
        }
        bluetoothStateReceiver = null
    }

    private fun sendAvailability(status: String) {
        val sink = synchronized(lock) { availabilitySink } ?: return
        mainHandler.post { sink.success(status) }
    }

    /**
     * Thread-safe helper to send success events to Flutter.
     * Ensures eventSink access is synchronized and events are posted on main thread.
     *
     * @param payload The event data to send
     */
    private fun sendEvent(payload: Map<String, Any>) {
        val sink = synchronized(lock) { eventSink } ?: return
        mainHandler.post {
            sink.success(payload)
        }
    }

    /**
     * Thread-safe helper to send error events to Flutter.
     * Ensures eventSink access is synchronized and errors are posted on main thread.
     *
     * @param code Error code
     * @param message Error message
     */
    private fun sendError(
        code: String,
        message: String,
    ) {
        val sink = synchronized(lock) { eventSink } ?: return
        mainHandler.post {
            sink.error(code, message, null)
        }
    }

    /**
     * Builds scan result payload from ScanResult and ScanRecord.
     * Applies token filtering if debugAllowAll is false.
     *
     * @param result The BLE scan result
     * @param record The scan record containing advertising data
     * @param parcelUuid The service UUID being scanned for
     * @return Payload map to send to Flutter, or null if filtered out
     */
    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    private fun buildScanPayload(
        result: ScanResult,
        record: ScanRecord,
        parcelUuid: ParcelUuid,
    ): Map<String, Any>? {
        // Extract token from service data or local name
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

        // Apply token filtering if not in debug mode
        if (!debugAllowAll) {
            if (tokenHex == null || !targetTokenSet.contains(tokenHex)) return null
        }

        // Extract metadata
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
        val serviceUuids =
            record.serviceUuids?.map { it.uuid.toString() } ?: emptyList()
        val targetToken = tokenHex ?: deviceId ?: localName ?: ""
        val localNameHex =
            localName?.let { bytesToHexLower(it.toByteArray(Charsets.UTF_8)) }

        // Build payload
        val payload =
            hashMapOf<String, Any>(
                "targetToken" to targetToken,
                "rssi" to result.rssi,
                "timestampMs" to System.currentTimeMillis(),
            )

        // Add optional fields
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

        return payload
    }
}
