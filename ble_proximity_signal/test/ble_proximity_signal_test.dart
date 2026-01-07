// ignore_for_file: avoid_redundant_argument_values "For Test"

import 'dart:async';

import 'package:ble_proximity_signal/ble_proximity_signal.dart';
import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart'
    show BleProximitySignalPlatform;
import 'package:flutter_test/flutter_test.dart';

class FakeBleProximitySignalPlatform extends BleProximitySignalPlatform {
  final StreamController<RawScanResult> _controller = StreamController<RawScanResult>.broadcast(sync: true);
  String? lastBroadcastToken;
  BroadcastConfig? lastBroadcastConfig;
  List<String>? lastScanTokens;
  ScanConfig? lastScanConfig;
  String? lastDiscoverDeviceId;
  int? lastDiscoverTimeoutMs;
  int stopBroadcastCalls = 0;
  int stopScanCalls = 0;
  bool throwOnStartScan = false;

  @override
  Stream<RawScanResult> get scanResults => _controller.stream;

  void emit({
    required String token,
    required int rssi,
    int? timestampMs,
  }) {
    _controller.add(
      RawScanResult(
        targetToken: token,
        rssi: rssi,
        timestampMs: timestampMs ?? 0,
      ),
    );
  }

  Future<void> dispose() => _controller.close();

  @override
  Future<void> startBroadcast({
    required String token,
    BroadcastConfig config = const BroadcastConfig(),
  }) async {
    lastBroadcastToken = token;
    lastBroadcastConfig = config;
  }

  @override
  Future<void> startScan({
    required List<String> targetTokens,
    ScanConfig config = const ScanConfig(),
  }) async {
    lastScanTokens = targetTokens;
    lastScanConfig = config;
    if (throwOnStartScan) {
      throw StateError('startScan failed');
    }
  }

  @override
  Future<void> stopBroadcast() async {
    stopBroadcastCalls += 1;
  }

  @override
  Future<void> stopScan() async {
    stopScanCalls += 1;
  }

  @override
  Future<String> debugDiscoverServices({
    required String deviceId,
    int timeoutMs = 8000,
  }) async {
    lastDiscoverDeviceId = deviceId;
    lastDiscoverTimeoutMs = timeoutMs;
    return 'ok';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(BleProximitySignal, () {
    late FakeBleProximitySignalPlatform platform;
    late BleProximitySignal ble;

    setUp(() {
      platform = FakeBleProximitySignalPlatform();
      ble = BleProximitySignal(platform: platform);
    });

    tearDown(() async {
      await ble.stopScan();
      await platform.dispose();
    });

    test('uses the default platform instance when none supplied', () async {
      final previous = BleProximitySignalPlatform.instance;
      addTearDown(() {
        BleProximitySignalPlatform.instance = previous;
      });
      BleProximitySignalPlatform.instance = platform;

      ble = BleProximitySignal();

      await ble.startBroadcast(token: 'AABB');

      expect(platform.lastBroadcastToken, 'aabb');
    });

    test('raw scan results stream forwards platform events', () async {
      final rawEvents = <RawScanResult>[];
      final sub = ble.rawScanResults.listen(rawEvents.add);

      platform.emit(token: 'aa', rssi: -70);

      await pumpEventQueue();

      expect(rawEvents, hasLength(1));
      expect(rawEvents.single.targetToken, 'aa');

      await sub.cancel();
    });

    test('raw scan log buffers the latest entries', () async {
      final logs = <List<RawScanResult>>[];
      final sub = ble.rawScanLog(maxEntries: 2).listen(logs.add);

      platform.emit(token: 'aa', rssi: -80);
      platform.emit(token: 'aa', rssi: -70);
      platform.emit(token: 'aa', rssi: -60);

      await pumpEventQueue();

      expect(logs, hasLength(3));
      expect(logs.last, hasLength(2));
      expect(logs.last.first.rssi, -60);
      expect(logs.last.last.rssi, -70);

      await sub.cancel();
    });

    test('raw scan log rejects non-positive maxEntries', () {
      expect(
        () => ble.rawScanLog(maxEntries: 0),
        throwsArgumentError,
      );
    });

    test('startBroadcast normalizes base64 tokens with padding', () async {
      await ble.startBroadcast(token: 'AQ');
      expect(platform.lastBroadcastToken, '01');

      await ble.startBroadcast(token: 'AQI');
      expect(platform.lastBroadcastToken, '0102');
    });

    test('startBroadcast rejects invalid tokens', () async {
      await expectLater(
        ble.startBroadcast(token: '%%%'),
        throwsA(isA<FormatException>()),
      );
    });

    test('EMA smoothing dampens intensity spikes', () async {
      const signalConfig = SignalConfig(emaAlpha: 0.2, staleMs: 100000);
      await ble.startScan(targetTokens: ['aa'], signalConfig: signalConfig);

      final events = <ProximityEvent>[];
      final sub = ble.events.listen(events.add);

      platform.emit(token: 'aa', rssi: -80);
      platform.emit(token: 'aa', rssi: -50);

      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events.last.intensity, lessThan(0.3));

      await sub.cancel();
    });

    test('intensity clamps when thresholds are flat', () async {
      const thresholds = Thresholds(
        enterNearDbm: -50,
        exitNearDbm: -55,
        enterVeryNearDbm: -45,
        exitVeryNearDbm: -48,
        minDbm: -60,
        maxDbm: -60,
      );
      const signalConfig = SignalConfig(
        emaAlpha: 1,
        thresholds: thresholds,
        staleMs: 100000,
      );

      await ble.startScan(targetTokens: ['aa'], signalConfig: signalConfig);

      final events = <ProximityEvent>[];
      final sub = ble.events.listen(events.add);

      platform.emit(token: 'aa', rssi: -70);
      platform.emit(token: 'aa', rssi: -60);

      await pumpEventQueue();

      expect(events.first.intensity, 0);
      expect(events.last.intensity, 1);

      await sub.cancel();
    });

    test('hysteresis gates enter/exit transitions', () async {
      const thresholds = Thresholds(
        enterNearDbm: -60,
        exitNearDbm: -65,
        enterVeryNearDbm: -52,
        exitVeryNearDbm: -56,
        minDbm: -80,
        maxDbm: -45,
      );
      const signalConfig = SignalConfig(
        emaAlpha: 1,
        thresholds: thresholds,
        staleMs: 100000,
      );

      await ble.startScan(targetTokens: ['aa'], signalConfig: signalConfig);

      final events = <ProximityEvent>[];
      final sub = ble.events.listen(events.add);

      platform.emit(token: 'aa', rssi: -70); // far
      platform.emit(token: 'aa', rssi: -60); // enter near
      platform.emit(token: 'aa', rssi: -52); // enter very near
      platform.emit(token: 'aa', rssi: -57); // exit very near -> near
      platform.emit(token: 'aa', rssi: -66); // exit near -> far

      await pumpEventQueue();

      expect(events[1].level, ProximityLevel.near);
      expect(events[1].enteredNear, isTrue);

      expect(events[2].level, ProximityLevel.veryNear);
      expect(events[2].enteredVeryNear, isTrue);

      expect(events[3].level, ProximityLevel.near);
      expect(events[3].exitedVeryNear, isTrue);

      expect(events[4].level, ProximityLevel.far);
      expect(events[4].exitedNear, isTrue);

      await sub.cancel();
    });

    test('startScan rejects more than five target tokens', () async {
      final tokens = List<String>.generate(6, (index) => 'aa$index');

      await expectLater(
        ble.startScan(targetTokens: tokens),
        throwsArgumentError,
      );
    });

    test('startScan tears down processor when native start fails', () async {
      platform.throwOnStartScan = true;
      final events = <ProximityEvent>[];
      final sub = ble.events.listen(events.add);

      await expectLater(
        ble.startScan(targetTokens: ['aa']),
        throwsA(isA<StateError>()),
      );

      platform.emit(token: 'aa', rssi: -40);
      await pumpEventQueue();

      expect(events, isEmpty);

      await sub.cancel();
    });

    test('stale timeout drops level to far', () async {
      const signalConfig = SignalConfig(emaAlpha: 1, staleMs: 20);
      await ble.startScan(targetTokens: ['aa'], signalConfig: signalConfig);

      final events = <ProximityEvent>[];
      final sub = ble.events.listen(events.add);

      platform.emit(token: 'aa', rssi: -55);
      await pumpEventQueue();

      await Future<void>.delayed(const Duration(milliseconds: 40));
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events.last.level, ProximityLevel.far);
      expect(events.last.intensity, 0);
      expect(events.last.exitedNear, isTrue);

      await sub.cancel();
    });

    test('debugDiscoverServices forwards arguments and result', () async {
      final result = await ble.debugDiscoverServices(deviceId: 'device-1', timeoutMs: 1234);

      expect(result, 'ok');
      expect(platform.lastDiscoverDeviceId, 'device-1');
      expect(platform.lastDiscoverTimeoutMs, 1234);
    });

    test('dispose stops scanning, broadcasting, and closes stream', () async {
      await ble.startBroadcast(token: 'AABB');
      await ble.startScan(targetTokens: ['aa'], signalConfig: const SignalConfig(staleMs: 0));

      await ble.dispose();

      expect(platform.stopBroadcastCalls, greaterThanOrEqualTo(1));
      expect(platform.stopScanCalls, greaterThanOrEqualTo(1));
      await expectLater(ble.events, emitsDone);
    });
  });

  test('ProximityEvent.toString includes debug fields', () {
    final event = ProximityEvent(
      targetToken: 'aa',
      rssi: -40,
      smoothRssi: -41.5,
      intensity: 0.7,
      level: ProximityLevel.near,
      enteredNear: true,
      exitedNear: false,
      enteredVeryNear: false,
      exitedVeryNear: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      deviceId: 'dev',
      deviceName: 'name',
      localName: 'local',
      manufacturerDataLen: 3,
      serviceDataLen: 2,
      serviceDataUuids: const ['abcd'],
      serviceUuids: const ['1234'],
    );

    final description = event.toString();

    expect(description, contains('token=aa'));
    expect(description, contains('deviceName=name'));
    expect(description, contains('serviceUuids=[1234]'));
  });
}
