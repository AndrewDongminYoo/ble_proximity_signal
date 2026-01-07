import 'dart:async';
import 'dart:convert';

import 'package:ble_proximity_signal/src/proximity_event.dart';
import 'package:ble_proximity_signal/src/signal_config.dart';
import 'package:ble_proximity_signal/src/signal_processor.dart';
import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';

/// BLE proximity signal API (foreground-only).
class BleProximitySignal {
  /// BLE proximity signal API (foreground-only).
  BleProximitySignal({BleProximitySignalPlatform? platform})
    : _platform = platform ?? BleProximitySignalPlatform.instance;

  final BleProximitySignalPlatform _platform;
  final StreamController<ProximityEvent> _eventsController = StreamController<ProximityEvent>.broadcast();

  SignalProcessor? _processor;

  /// Smoothed proximity stream.
  Stream<ProximityEvent> get events => _eventsController.stream;

  /// Debug: raw scan stream from native (no smoothing or hysteresis).
  Stream<RawScanResult> get rawScanResults => _platform.scanResults;

  /// Starts BLE advertising with the given token.
  Future<void> startBroadcast({
    required String token,
    BroadcastConfig config = const BroadcastConfig(),
  }) async {
    final normalized = _normalizeToken(token);
    await _platform.startBroadcast(token: normalized, config: config);
  }

  /// Stops BLE advertising.
  Future<void> stopBroadcast() => _platform.stopBroadcast();

  /// Starts BLE scan for the given target tokens.
  ///
  /// [config] configures native scan filters, while [signalConfig] tunes the
  /// Dart-side smoothing/hysteresis behavior.
  Future<void> startScan({
    required List<String> targetTokens,
    ScanConfig config = const ScanConfig(),
    SignalConfig signalConfig = const SignalConfig(),
  }) async {
    if (!config.debugAllowAll && targetTokens.length > 5) {
      throw ArgumentError.value(
        targetTokens.length,
        'targetTokens',
        'must be <= 5',
      );
    }

    final normalizedTokens = config.debugAllowAll ? <String>{} : targetTokens.map(_normalizeToken).toSet();

    try {
      await _platform.stopScan();
      await _processor?.stop();
    } on Object catch (_) {
      // best-effort stop previous native scan
    }
    _processor = SignalProcessor(
      rawStream: _platform.scanResults,
      targetTokens: normalizedTokens,
      config: signalConfig,
      onEvent: _eventsController.add,
      onError: _eventsController.addError,
    )..start();

    try {
      await _platform.startScan(
        targetTokens: config.debugAllowAll ? <String>[] : normalizedTokens.toList(),
        config: config,
      );
    } catch (_) {
      await _processor?.stop();
      _processor = null;
      rethrow;
    }
  }

  /// Stops BLE scanning.
  Future<void> stopScan() async {
    try {
      await _platform.stopScan();
    } finally {
      await _processor?.stop();
      _processor = null;
    }
  }

  /// Clean Up Internal Resources
  Future<void> dispose() async {
    await stopScan();
    await stopBroadcast();
    await _eventsController.close();
  }
}

String _normalizeToken(String token) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Token must not be empty.');
  }

  final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
  if (hexRegex.hasMatch(trimmed) && trimmed.length.isEven) {
    return trimmed.toLowerCase();
  }

  final normalized = trimmed.replaceAll('-', '+').replaceAll('_', '/');
  final padded = switch (normalized.length % 4) {
    2 => '$normalized==',
    3 => '$normalized=',
    _ => normalized,
  };

  try {
    final bytes = base64.decode(padded);
    return _bytesToHexLower(bytes);
  } on FormatException {
    throw const FormatException(
      'Invalid token format (expected hex or base64url/base64).',
    );
  }
}

String _bytesToHexLower(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
