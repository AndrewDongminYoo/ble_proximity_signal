import 'package:ble_proximity_signal_platform_interface/src/method_channel_ble_proximity_signal.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

  static BleProximitySignalPlatform _instance =
      MethodChannelBleProximitySignal();

  /// The default instance of [BleProximitySignalPlatform] to use.
  ///
  /// Defaults to [MethodChannelBleProximitySignal].
  static BleProximitySignalPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [BleProximitySignalPlatform] when they register themselves.
  static set instance(BleProximitySignalPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Return the current platform name.
  Future<String?> getPlatformName();
}
