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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('ble_proximity_signal/events'),
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

    test('scanResults maps event channel data to RawScanResult', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('ble_proximity_signal/events'),
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(<Object?, Object?>{
              'targetToken': 'a1b2',
              'rssi': -44,
              'timestampMs': 1234,
            });
            events.endOfStream();
          },
        ),
      );

      await expectLater(
        methodChannelBleProximitySignal.scanResults,
        emitsInOrder(<Matcher>[
          isA<RawScanResult>()
              .having((result) => result.targetToken, 'targetToken', 'a1b2')
              .having((result) => result.rssi, 'rssi', -44)
              .having((result) => result.timestampMs, 'timestampMs', 1234),
          emitsDone,
        ]),
      );
    });

    test('scanResults throws when event is not a map', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        const EventChannel('ble_proximity_signal/events'),
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success('not-a-map');
            events.endOfStream();
          },
        ),
      );

      await expectLater(
        methodChannelBleProximitySignal.scanResults.first,
        throwsArgumentError,
      );
    });

    test('debugDiscoverServices returns empty string when platform returns null', () async {
      final result = await methodChannelBleProximitySignal.debugDiscoverServices(
        deviceId: 'device-1',
      );

      expect(result, isEmpty);
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'debugDiscoverServices',
            arguments: <String, Object?>{
              'deviceId': 'device-1',
              'timeoutMs': 8000,
            },
          ),
        ],
      );
    });

    test('debugDiscoverServices returns platform value when present', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannelBleProximitySignal.methodChannel,
        (methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'debugDiscoverServices') {
            return 'ok';
          }
          return null;
        },
      );

      final result = await methodChannelBleProximitySignal.debugDiscoverServices(
        deviceId: 'device-2',
        timeoutMs: 2500,
      );

      expect(result, 'ok');
      expect(
        log,
        <Matcher>[
          isMethodCall(
            'debugDiscoverServices',
            arguments: <String, Object?>{
              'deviceId': 'device-2',
              'timeoutMs': 2500,
            },
          ),
        ],
      );
    });
  });
}
