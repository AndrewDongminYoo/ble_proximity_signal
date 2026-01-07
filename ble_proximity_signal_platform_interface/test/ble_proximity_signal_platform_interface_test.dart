import 'dart:async';

import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test double for [BleProximitySignalPlatform].
class BleProximitySignalMock extends BleProximitySignalPlatform {
  final StreamController<RawScanResult> _controller = StreamController<RawScanResult>.broadcast();

  @override
  Stream<RawScanResult> get scanResults => _controller.stream;

  @override
  Future<void> startBroadcast({
    required String token,
    BroadcastConfig config = const BroadcastConfig(),
  }) async {}

  @override
  Future<void> startScan({
    required List<String> targetTokens,
    ScanConfig config = const ScanConfig(),
  }) async {}

  @override
  Future<void> stopBroadcast() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<String> debugDiscoverServices({
    required String deviceId,
    int timeoutMs = 8000,
  }) async {
    return 'ok';
  }

  Future<void> dispose() => _controller.close();
}

/// Entry point for platform interface tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('BleProximitySignalPlatformInterface', () {
    late BleProximitySignalPlatform bleProximitySignalPlatform;

    setUp(() {
      bleProximitySignalPlatform = BleProximitySignalMock();
      BleProximitySignalPlatform.instance = bleProximitySignalPlatform;
    });

    tearDown(() async {
      await (bleProximitySignalPlatform as BleProximitySignalMock).dispose();
    });

    test('scanResults is a RawScanResult stream', () {
      expect(
        BleProximitySignalPlatform.instance.scanResults,
        isA<Stream<RawScanResult>>(),
      );
    });

    test('start/stop methods complete', () async {
      await BleProximitySignalPlatform.instance.startBroadcast(
        token: 'a1b2',
      );
      await BleProximitySignalPlatform.instance.stopBroadcast();
      await BleProximitySignalPlatform.instance.startScan(
        targetTokens: <String>['aa'],
      );
      await BleProximitySignalPlatform.instance.stopScan();
    });

    test('BroadcastConfig.toMap includes defaults', () {
      const config = BroadcastConfig();

      expect(
        config.toMap(),
        <String, Object?>{
          'serviceUuid': BroadcastConfig.defaultServiceUuid,
          'txPower': null,
        },
      );
    });

    test('ScanConfig.toMap includes debug flags', () {
      const config = ScanConfig(
        serviceUuid: '00000000-0000-0000-0000-000000000000',
        debugAllowAll: true,
      );

      expect(
        config.toMap(),
        <String, Object?>{
          'serviceUuid': '00000000-0000-0000-0000-000000000000',
          'debugAllowAll': true,
        },
      );
    });

    test('RawScanResult.fromMap parses optional fields', () {
      final map = <Object?, Object?>{
        'targetToken': 'aa',
        'rssi': -44,
        'timestampMs': 1234,
        'deviceId': 'dev',
        'deviceName': 'name',
        'localName': 'local',
        'localNameHex': '6c6f63616c',
        'manufacturerDataLen': 2,
        'manufacturerDataHex': 'beef',
        'serviceDataLen': 1,
        'serviceDataUuids': <String>['1234'],
        'serviceDataHex': <String, String>{'1234': '01'},
        'serviceUuids': <String>['abcd'],
      };

      final result = RawScanResult.fromMap(map);

      expect(result.targetToken, 'aa');
      expect(result.rssi, -44);
      expect(result.timestampMs, 1234);
      expect(result.deviceId, 'dev');
      expect(result.deviceName, 'name');
      expect(result.localName, 'local');
      expect(result.localNameHex, '6c6f63616c');
      expect(result.manufacturerDataLen, 2);
      expect(result.manufacturerDataHex, 'beef');
      expect(result.serviceDataLen, 1);
      expect(result.serviceDataUuids, <String>['1234']);
      expect(result.serviceDataHex, <String, String>{'1234': '01'});
      expect(result.serviceUuids, <String>['abcd']);
    });

    test('RawScanResult.fromMap validates field types', () {
      final base = <Object?, Object?>{
        'targetToken': 'aa',
        'rssi': -44,
        'timestampMs': 1234,
      };
      final cases = <Map<Object?, Object?>>[
        <Object?, Object?>{...base, 'targetToken': 7},
        <Object?, Object?>{...base, 'rssi': 'bad'},
        <Object?, Object?>{...base, 'timestampMs': 'bad'},
        <Object?, Object?>{...base, 'deviceId': 1},
        <Object?, Object?>{...base, 'deviceName': 1},
        <Object?, Object?>{...base, 'localName': 1},
        <Object?, Object?>{...base, 'localNameHex': 1},
        <Object?, Object?>{...base, 'manufacturerDataLen': 'bad'},
        <Object?, Object?>{...base, 'manufacturerDataHex': 1},
        <Object?, Object?>{...base, 'serviceDataLen': 'bad'},
        <Object?, Object?>{...base, 'serviceDataUuids': 'bad'},
        <Object?, Object?>{...base, 'serviceDataUuids': <Object?>['ok', 1]},
        <Object?, Object?>{...base, 'serviceDataHex': 'bad'},
        <Object?, Object?>{...base, 'serviceDataHex': <Object?, Object?>{1: 'ok'}},
        <Object?, Object?>{...base, 'serviceDataHex': <Object?, Object?>{'ok': 1}},
        <Object?, Object?>{...base, 'serviceUuids': 'bad'},
        <Object?, Object?>{...base, 'serviceUuids': <Object?>['ok', 1]},
      ];

      for (final map in cases) {
        expect(
          () => RawScanResult.fromMap(map),
          throwsArgumentError,
        );
      }
    });

    test('RawScanResult.toString includes debug fields', () {
      const result = RawScanResult(
        targetToken: 'aa',
        rssi: -40,
        timestampMs: 1,
        deviceId: 'dev',
        deviceName: 'name',
        localName: 'local',
        localNameHex: '6c6f63616c',
        manufacturerDataLen: 2,
        manufacturerDataHex: 'beef',
        serviceDataLen: 1,
        serviceDataUuids: <String>['1234'],
        serviceDataHex: <String, String>{'1234': '01'},
        serviceUuids: <String>['abcd'],
      );

      final description = result.toString();

      expect(description, contains('token=aa'));
      expect(description, contains('deviceName=name'));
      expect(description, contains('serviceUuids=[abcd]'));
      expect(description, contains('manufacturerDataHex=beef'));
    });
  });
}
