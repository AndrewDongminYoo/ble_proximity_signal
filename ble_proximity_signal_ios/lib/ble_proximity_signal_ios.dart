import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The iOS implementation of [BleProximitySignalPlatform].
class BleProximitySignalIOS extends BleProximitySignalPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ble_proximity_signal_ios');

  /// Registers this class as the default instance of [BleProximitySignalPlatform]
  static void registerWith() {
    BleProximitySignalPlatform.instance = BleProximitySignalIOS();
  }

  @override
  Future<String?> getPlatformName() {
    return methodChannel.invokeMethod<String>('getPlatformName');
  }
}
