// ignore_for_file: avoid_redundant_argument_values "For Test"

import 'dart:async';

import 'package:ble_proximity_signal/ble_proximity_signal.dart';
import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart'
    show BleProximitySignalPlatform;
import 'package:flutter_test/flutter_test.dart';

class FakeBleProximitySignalPlatform extends BleProximitySignalPlatform {
  final StreamController<RawScanResult> _controller = StreamController<RawScanResult>.broadcast(sync: true);

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
  });
}
