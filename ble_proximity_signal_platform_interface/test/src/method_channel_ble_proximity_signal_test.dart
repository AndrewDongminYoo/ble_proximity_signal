import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:ble_proximity_signal_platform_interface/src/method_channel_ble_proximity_signal.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('$MethodChannelBleProximitySignal', () {
    late MethodChannelBleProximitySignal methodChannelBleProximitySignal;
    final log = <MethodCall>[];

    setUp(() async {
      methodChannelBleProximitySignal = MethodChannelBleProximitySignal();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelBleProximitySignal.methodChannel,
        (methodCall) async {
          log.add(methodCall);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelBleProximitySignal.methodChannel,
        null,
      );
      log.clear();
    });

    test('startBroadcast invokes method channel', () async {
      const config = BroadcastConfig(
        serviceUuid: '00000000-0000-0000-0000-000000000000',
        txPower: 1,
      );
      await methodChannelBleProximitySignal.startBroadcast(
        token: 'a1b2',
        config: config,
      );
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

    test('startScan invokes method channel', () async {
      const config = ScanConfig(
        serviceUuid: '11111111-1111-1111-1111-111111111111',
        debugAllowAll: true,
      );
      await methodChannelBleProximitySignal.startScan(
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

    test('stopBroadcast and stopScan invoke method channel', () async {
      await methodChannelBleProximitySignal.stopBroadcast();
      await methodChannelBleProximitySignal.stopScan();
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
