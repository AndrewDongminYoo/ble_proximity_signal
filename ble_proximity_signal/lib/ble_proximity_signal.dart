import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';

BleProximitySignalPlatform get _platform => BleProximitySignalPlatform.instance;

/// Returns the name of the current platform.
Future<String> getPlatformName() async {
  final platformName = await _platform.getPlatformName();
  if (platformName == null) throw Exception('Unable to get platform name.');
  return platformName;
}
