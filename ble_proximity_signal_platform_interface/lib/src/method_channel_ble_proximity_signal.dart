import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// An implementation of [BleProximitySignalPlatform] that uses method channels.
class MethodChannelBleProximitySignal extends BleProximitySignalPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ble_proximity_signal');

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
