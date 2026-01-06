import 'package:ble_proximity_signal/ble_proximity_signal.dart';
import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBleProximitySignalPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements BleProximitySignalPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(BleProximitySignalPlatform, () {
    late BleProximitySignalPlatform bleProximitySignalPlatform;

    setUp(() {
      bleProximitySignalPlatform = MockBleProximitySignalPlatform();
      BleProximitySignalPlatform.instance = bleProximitySignalPlatform;
    });

    group('getPlatformName', () {
      test('returns correct name when platform implementation exists',
          () async {
        const platformName = '__test_platform__';
        when(
          () => bleProximitySignalPlatform.getPlatformName(),
        ).thenAnswer((_) async => platformName);

        final actualPlatformName = await getPlatformName();
        expect(actualPlatformName, equals(platformName));
      });

      test('throws exception when platform implementation is missing',
          () async {
        when(
          () => bleProximitySignalPlatform.getPlatformName(),
        ).thenAnswer((_) async => null);

        expect(getPlatformName, throwsException);
      });
    });
  });
}
