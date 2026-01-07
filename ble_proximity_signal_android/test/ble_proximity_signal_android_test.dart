import 'dart:async';

import 'package:ble_proximity_signal_android/ble_proximity_signal_android.dart';
import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleProximitySignalAndroid', () {
    late BleProximitySignalAndroid bleProximitySignal;
    late List<MethodCall> log;
    late List<MethodCall> eventLog;
    late TestDefaultBinaryMessenger messenger;
    const eventChannelName = 'ble_proximity_signal/events';
    const methodCodec = StandardMethodCodec();

    void sendEvent(Object? event) {
      unawaited(messenger.handlePlatformMessage(
        eventChannelName,
        methodCodec.encodeSuccessEnvelope(event),
        (ByteData? _) {},
      ));
    }

    setUp(() async {
      bleProximitySignal = BleProximitySignalAndroid();
      messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      log = <MethodCall>[];
      eventLog = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        bleProximitySignal.methodChannel,
        (
          methodCall,
        ) async {
          log.add(methodCall);
          return null;
        },
      );
      messenger.setMockMessageHandler(
        eventChannelName,
        (ByteData? message) async {
          final methodCall = methodCodec.decodeMethodCall(message);
          eventLog.add(methodCall);
          return methodCodec.encodeSuccessEnvelope(null);
        },
      );
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(
        bleProximitySignal.methodChannel,
        null,
      );
      messenger.setMockMessageHandler(eventChannelName, null);
      log.clear();
      eventLog.clear();
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

    test('debugDiscoverServices returns method result', () async {
      messenger.setMockMethodCallHandler(
        bleProximitySignal.methodChannel,
        (methodCall) async {
          log.add(methodCall);
          if (methodCall.method == 'debugDiscoverServices') {
            return 'ok';
          }
          return null;
        },
      );

      final result = await bleProximitySignal.debugDiscoverServices(
        deviceId: 'device-1',
        timeoutMs: 9000,
      );

      expect(result, 'ok');
      expect(
        log,
        contains(
          isMethodCall(
            'debugDiscoverServices',
            arguments: <String, Object?>{
              'deviceId': 'device-1',
              'timeoutMs': 9000,
            },
          ),
        ),
      );
    });

    test('scanResults maps events to RawScanResult', () async {
      final expectation = expectLater(
        bleProximitySignal.scanResults,
        emits(
          isA<RawScanResult>()
              .having((result) => result.targetToken, 'targetToken', 'aa')
              .having((result) => result.rssi, 'rssi', -42)
              .having((result) => result.timestampMs, 'timestampMs', 123),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      sendEvent(<Object?, Object?>{
        'targetToken': 'aa',
        'rssi': -42,
        'timestampMs': 123,
      });

      await expectation;
      expect(eventLog.first.method, 'listen');
    });

    test('scanResults throws when event is not a map', () async {
      final expectation = expectLater(
        bleProximitySignal.scanResults,
        emitsError(isA<ArgumentError>()),
      );

      await Future<void>.delayed(Duration.zero);
      sendEvent('bad');
      await expectation;
    });
  });
}
