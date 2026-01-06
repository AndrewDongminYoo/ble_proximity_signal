import 'package:ble_proximity_signal_ios/ble_proximity_signal_ios.dart';
import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleProximitySignalIOS', () {
    const kPlatformName = 'iOS';
    late BleProximitySignalIOS bleProximitySignal;
    late List<MethodCall> log;

    setUp(() async {
      bleProximitySignal = BleProximitySignalIOS();

      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bleProximitySignal.methodChannel, (methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'getPlatformName':
            return kPlatformName;
          default:
            return null;
        }
      });
    });

    test('can be registered', () {
      BleProximitySignalIOS.registerWith();
      expect(BleProximitySignalPlatform.instance, isA<BleProximitySignalIOS>());
    });

    test('getPlatformName returns correct name', () async {
      final name = await bleProximitySignal.getPlatformName();
      expect(
        log,
        <Matcher>[isMethodCall('getPlatformName', arguments: null)],
      );
      expect(name, equals(kPlatformName));
    });
  });
}
