import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';

/// The Android implementation of [BleProximitySignalPlatform].
///
/// The method/event channel behavior is identical to the default
/// [MethodChannelBleProximitySignal]; this subclass only exists so the
/// federated plugin can register an Android-specific instance.
class BleProximitySignalAndroid extends MethodChannelBleProximitySignal {
  /// Registers this class as the default instance of [BleProximitySignalPlatform].
  static void registerWith() {
    BleProximitySignalPlatform.instance = BleProximitySignalAndroid();
  }
}
