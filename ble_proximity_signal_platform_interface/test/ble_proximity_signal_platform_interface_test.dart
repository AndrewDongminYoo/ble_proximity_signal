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
  });
}
