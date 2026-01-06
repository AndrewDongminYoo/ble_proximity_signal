import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// An implementation of [BleProximitySignalPlatform] that uses method channels.
class MethodChannelBleProximitySignal extends BleProximitySignalPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ble_proximity_signal');

  static const EventChannel _eventChannel = EventChannel('ble_proximity_signal/events');

  @override
  Stream<RawScanResult> get scanResults =>
      _eventChannel.receiveBroadcastStream().map((event) => RawScanResult.fromMap(_castEvent(event)));

  @override
  Future<void> startBroadcast({
    required String token,
    BroadcastConfig config = const BroadcastConfig(),
  }) {
    return methodChannel.invokeMethod<void>(
      'startBroadcast',
      <String, Object?>{
        'token': token,
        ...config.toMap(),
      },
    );
  }

  @override
  Future<void> startScan({
    required List<String> targetTokens,
    ScanConfig config = const ScanConfig(),
  }) {
    return methodChannel.invokeMethod<void>(
      'startScan',
      <String, Object?>{
        'targetTokens': targetTokens,
        ...config.toMap(),
      },
    );
  }

  @override
  Future<void> stopBroadcast() {
    return methodChannel.invokeMethod<void>('stopBroadcast');
  }

  @override
  Future<void> stopScan() {
    return methodChannel.invokeMethod<void>('stopScan');
  }
}

Map<Object?, Object?> _castEvent(Object? event) {
  if (event is Map<Object?, Object?>) {
    return event;
  }
  throw ArgumentError.value(event, 'event', 'Expected a map');
}
