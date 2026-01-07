import 'package:ble_proximity_signal_android/ble_proximity_signal_android.dart';
import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleProximitySignalAndroid', () {
    late BleProximitySignalAndroid bleProximitySignal;
    late List<MethodCall> log;

    setUp(() async {
      bleProximitySignal = BleProximitySignalAndroid();

      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        bleProximitySignal.methodChannel,
        (
          methodCall,
        ) async {
          log.add(methodCall);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        bleProximitySignal.methodChannel,
        null,
      );
      log.clear();
    });

    test('can be registered', () {
      BleProximitySignalAndroid.registerWith();
      expect(
        BleProximitySignalPlatform.instance,
        isA<BleProximitySignalAndroid>(),
      );
    });

    test('startBroadcast sends expected arguments', () async {
      const config = BroadcastConfig(serviceUuid: '00000000-0000-0000-0000-000000000000', txPower: 3);
      await bleProximitySignal.startBroadcast(token: 'a1b2', config: config);
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'startBroadcast',
            arguments: <String, Object?>{
              'token': 'a1b2',
              'serviceUuid': config.serviceUuid,
              'txPower': config.txPower,
            },
          ),
        ],
      );
    });

    test('startScan sends expected arguments', () async {
      const config = ScanConfig(
        serviceUuid: '11111111-1111-1111-1111-111111111111',
        debugAllowAll: true,
      );
      await bleProximitySignal.startScan(
        targetTokens: <String>['aa', 'bb'],
        config: config,
      );
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'startScan',
            arguments: <String, Object?>{
              'targetTokens': <String>['aa', 'bb'],
              'serviceUuid': config.serviceUuid,
              'debugAllowAll': config.debugAllowAll,
            },
          ),
        ],
      );
    });

    test('stopBroadcast and stopScan invoke methods', () async {
      await bleProximitySignal.stopBroadcast();
      await bleProximitySignal.stopScan();
      expect(
        log,
        <Matcher>[
          isMethodCall('stopBroadcast', arguments: null),
          isMethodCall('stopScan', arguments: null),
        ],
      );
    });
  });
}
