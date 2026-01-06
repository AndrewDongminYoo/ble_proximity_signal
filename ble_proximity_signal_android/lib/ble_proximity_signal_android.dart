import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android implementation of [BleProximitySignalPlatform].
class BleProximitySignalAndroid extends BleProximitySignalPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ble_proximity_signal_android');

  /// Registers this class as the default instance of [BleProximitySignalPlatform]
  static void registerWith() {
    BleProximitySignalPlatform.instance = BleProximitySignalAndroid();
  }

  @override
  // TODO: implement scanResults
  Stream<RawScanResult> get scanResults => throw UnimplementedError();

  @override
  Future<void> startBroadcast({required String token, BroadcastConfig config = const BroadcastConfig()}) {
    // TODO: implement startBroadcast
    throw UnimplementedError();
  }

  @override
  Future<void> startScan({required List<String> targetTokens, ScanConfig config = const ScanConfig()}) {
    // TODO: implement startScan
    throw UnimplementedError();
  }

  @override
  Future<void> stopBroadcast() {
    // TODO: implement stopBroadcast
    throw UnimplementedError();
  }

  @override
  Future<void> stopScan() {
    // TODO: implement stopScan
    throw UnimplementedError();
  }
}
