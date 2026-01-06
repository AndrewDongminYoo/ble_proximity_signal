import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class BleProximitySignalMock extends BleProximitySignalPlatform {
  static const mockPlatformName = 'Mock';

  @override
  Future<String?> getPlatformName() async => mockPlatformName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('BleProximitySignalPlatformInterface', () {
    late BleProximitySignalPlatform bleProximitySignalPlatform;

    setUp(() {
      bleProximitySignalPlatform = BleProximitySignalMock();
      BleProximitySignalPlatform.instance = bleProximitySignalPlatform;
    });

    group('getPlatformName', () {
      test('returns correct name', () async {
        expect(
          await BleProximitySignalPlatform.instance.getPlatformName(),
          equals(BleProximitySignalMock.mockPlatformName),
        );
      });
    });
  });
}
