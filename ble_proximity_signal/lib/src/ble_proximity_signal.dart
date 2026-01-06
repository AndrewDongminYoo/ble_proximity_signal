import 'dart:async';
import 'dart:convert';

import 'package:ble_proximity_signal/src/proximity_event.dart';
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
  Future<void> startScan({
    required List<String> targetTokens,
    ScanConfig config = const ScanConfig(),
  }) async {
    if (targetTokens.length > 5) {
      throw ArgumentError.value(
        targetTokens.length,
        'targetTokens',
        'must be <= 5',
      );
    }

    final normalizedTokens = targetTokens.map(_normalizeToken).toSet();

    await _processor?.stop();
    _processor = SignalProcessor(
      rawStream: _platform.scanResults,
      targetTokens: normalizedTokens,
      config: config,
      onEvent: _eventsController.add,
      onError: _eventsController.addError,
    )..start();

    try {
      await _platform.startScan(
        targetTokens: normalizedTokens.toList(),
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
