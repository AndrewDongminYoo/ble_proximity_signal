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
  Future<String?> getPlatformName() {
    return methodChannel.invokeMethod<String>('getPlatformName');
  }
}
