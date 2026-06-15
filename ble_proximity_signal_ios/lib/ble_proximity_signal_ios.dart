import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';

/// The iOS implementation of [BleProximitySignalPlatform].
///
/// The method/event channel behavior is identical to the default
/// [MethodChannelBleProximitySignal]; this subclass only exists so the
/// federated plugin can register an iOS-specific instance.
class BleProximitySignalIOS extends MethodChannelBleProximitySignal {
  /// Registers this class as the default instance of [BleProximitySignalPlatform].
  static void registerWith() {
    BleProximitySignalPlatform.instance = BleProximitySignalIOS();
  }
}
