import 'dart:async';

import 'package:ble_proximity_signal_platform_interface/src/method_channel_ble_proximity_signal.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Configuration for broadcasting messages or events.
class BroadcastConfig {
  /// Configuration for broadcasting messages or events.
  const BroadcastConfig({
    this.serviceUuid = defaultServiceUuid,
    this.txPower,
  });

  /// Default 128-bit UUID (v0.1.0). Change if you want a custom UUID.
  static const String defaultServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// BLE service UUID used in advertising / scanning filter.
  final String serviceUuid;

  /// Optional tx power hint. Platform may ignore.
  final int? txPower;

  /// Creates a map with keys 'serviceUuid' and 'txPower' mapped to their respective values.
  Map<String, Object?> toMap() => <String, Object?>{
    'serviceUuid': serviceUuid,
    'txPower': txPower,
  };
}

/// Scan configuration for native filtering.
class ScanConfig {
  /// Scan configuration for native filtering.
  const ScanConfig({
    this.serviceUuid = BroadcastConfig.defaultServiceUuid,
    this.debugAllowAll = false,
  });

  /// BLE service UUID used to filter scan results.
  final String serviceUuid;

  /// Debug: scan all peripherals (no UUID/token filtering).
  final bool debugAllowAll;

  /// Converts this config to a platform channel map.
  Map<String, Object?> toMap() => <String, Object?>{
    'serviceUuid': serviceUuid,
    'debugAllowAll': debugAllowAll,
  };
}

/// Raw scan result from native layer.
/// Dart-side will smooth RSSI and compute intensity / hysteresis.
class RawScanResult {
  /// Raw scan result from native layer.
  const RawScanResult({
    required this.targetToken,
    required this.rssi,
    required this.timestampMs,
    this.deviceId,
    this.deviceName,
    this.localName,
    this.manufacturerDataLen,
    this.serviceDataLen,
    this.serviceDataUuids,
  });

  /// Converts a map to a `RawScanResult` object by validating and extracting specific fields.
  factory RawScanResult.fromMap(Map<Object?, Object?> map) {
    final token = map['targetToken'];
    final rssi = map['rssi'];
    final ts = map['timestampMs'];
    final deviceId = map['deviceId'];
    final deviceName = map['deviceName'];
    final localName = map['localName'];
    final manufacturerDataLen = map['manufacturerDataLen'];
    final serviceDataLen = map['serviceDataLen'];
    final serviceDataUuids = map['serviceDataUuids'];

    if (token is! String) {
      throw ArgumentError.value(token, 'targetToken', 'must be a String');
    }
    if (rssi is! int) {
      throw ArgumentError.value(rssi, 'rssi', 'must be an int');
    }
    if (ts is! int) {
      throw ArgumentError.value(ts, 'timestampMs', 'must be an int');
    }
    if (deviceId != null && deviceId is! String) {
      throw ArgumentError.value(deviceId, 'deviceId', 'must be a String');
    }
    if (deviceName != null && deviceName is! String) {
      throw ArgumentError.value(deviceName, 'deviceName', 'must be a String');
    }
    if (localName != null && localName is! String) {
      throw ArgumentError.value(localName, 'localName', 'must be a String');
    }
    if (manufacturerDataLen != null && manufacturerDataLen is! int) {
      throw ArgumentError.value(
        manufacturerDataLen,
        'manufacturerDataLen',
        'must be an int',
      );
    }
    if (serviceDataLen != null && serviceDataLen is! int) {
      throw ArgumentError.value(
        serviceDataLen,
        'serviceDataLen',
        'must be an int',
      );
    }
    if (serviceDataUuids != null) {
      if (serviceDataUuids is! List) {
        throw ArgumentError.value(
          serviceDataUuids,
          'serviceDataUuids',
          'must be a List<String>',
        );
      }
      for (final entry in serviceDataUuids) {
        if (entry is! String) {
          throw ArgumentError.value(
            serviceDataUuids,
            'serviceDataUuids',
            'must contain only String values',
          );
        }
      }
    }

    return RawScanResult(
      targetToken: token,
      rssi: rssi,
      timestampMs: ts,
      deviceId: deviceId as String?,
      deviceName: deviceName as String?,
      localName: localName as String?,
      manufacturerDataLen: manufacturerDataLen as int?,
      serviceDataLen: serviceDataLen as int?,
      serviceDataUuids: serviceDataUuids as List<String>?,
    );
  }

  /// The identifier extracted from advertising payload.
  /// In debug mode, this may fall back to the device identifier.
  final String targetToken;

  /// RSSI in dBm (negative int, e.g. -55).
  final int rssi;

  /// Epoch milliseconds from native when the scan callback was received.
  /// Uses wall-clock time (Unix epoch) for cross-platform consistency.
  final int timestampMs;

  /// Debug: device identifier (may be randomized on Android).
  final String? deviceId;

  /// Debug: device name if available.
  final String? deviceName;

  /// Debug: advertised local name if available.
  final String? localName;

  /// Debug: manufacturer data length if available.
  final int? manufacturerDataLen;

  /// Debug: total service data length if available.
  final int? serviceDataLen;

  /// Debug: service data UUID keys if available.
  final List<String>? serviceDataUuids;

  @override
  String toString() {
    return 'RawScanResult(token=$targetToken, rssi=$rssi, ts=$timestampMs, '
        'deviceId=$deviceId, deviceName=$deviceName, localName=$localName, '
        'serviceDataLen=$serviceDataLen, serviceDataUuids=$serviceDataUuids, '
        'manufacturerDataLen=$manufacturerDataLen)';
  }
}

/// {@template ble_proximity_signal_platform}
/// The interface that implementations of ble_proximity_signal must implement.
///
/// Platform implementations should extend this class
/// rather than implement it as `BleProximitySignal`.
///
/// Extending this class (using `extends`) ensures that the subclass will get
/// the default implementation, while platform implementations that `implements`
/// this interface will be broken by newly added [BleProximitySignalPlatform] methods.
/// {@endtemplate}
abstract class BleProximitySignalPlatform extends PlatformInterface {
  /// {@macro ble_proximity_signal_platform}
  BleProximitySignalPlatform() : super(token: _token);

  static final Object _token = Object();

  static BleProximitySignalPlatform _instance = MethodChannelBleProximitySignal();

  /// The default instance of [BleProximitySignalPlatform] to use.
  static BleProximitySignalPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [BleProximitySignalPlatform] when they register themselves.
  static set instance(BleProximitySignalPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Starts BLE advertising with the given token.
  ///
  /// Foreground-only (v0.1.0). Platform may reject if BLE is unavailable/off.
  Future<void> startBroadcast({
    required String token,
    BroadcastConfig config = const BroadcastConfig(),
  });

  /// Stops BLE advertising.
  Future<void> stopBroadcast();

  /// Starts scanning BLE advertisements and filters only [targetTokens].
  ///
  /// `targetTokens.length` must be <= 5 (enforced in the Dart wrapper package,
  /// but platforms may also validate).
  /// If [ScanConfig.debugAllowAll] is true, platforms may scan all peripherals
  /// and ignore UUID/token filtering for debugging.
  Future<void> startScan({
    required List<String> targetTokens,
    ScanConfig config = const ScanConfig(),
  });

  /// Stops scanning.
  Future<void> stopScan();

  /// Raw scan result stream from native.
  ///
  /// Dart-side will do smoothing/threshold/intensity mapping.
  Stream<RawScanResult> get scanResults;
}
