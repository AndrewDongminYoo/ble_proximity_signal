import 'dart:async';

import 'package:ble_proximity_signal_platform_interface/ble_proximity_signal_platform_interface.dart';

import 'proximity_event.dart';

class SignalProcessor {
  SignalProcessor({
    required Stream<RawScanResult> rawStream,
    required Set<String> targetTokens,
    required ScanConfig config,
    required void Function(ProximityEvent) onEvent,
    required void Function(Object, StackTrace) onError,
    DateTime Function()? now,
  })  : _rawStream = rawStream,
        _targetTokens = targetTokens,
        _config = config,
        _onEvent = onEvent,
        _onError = onError,
        _now = now ?? DateTime.now;

  final Stream<RawScanResult> _rawStream;
  final Set<String> _targetTokens;
  final ScanConfig _config;
  final void Function(ProximityEvent) _onEvent;
  final void Function(Object, StackTrace) _onError;
  final DateTime Function() _now;

  final Map<String, _TargetState> _states = <String, _TargetState>{};

  StreamSubscription<RawScanResult>? _subscription;

  void start() {
    _subscription ??= _rawStream.listen(_handleRaw, onError: _onError);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final state in _states.values) {
      state.staleTimer?.cancel();
      state.staleTimer = null;
    }
    _states.clear();
  }

  void _handleRaw(RawScanResult raw) {
    if (_targetTokens.isNotEmpty && !_targetTokens.contains(raw.targetToken)) {
      return;
    }

    final now = _now();
    final state = _states.putIfAbsent(
      raw.targetToken,
      () => _TargetState(
        smoothRssi: null,
        lastRssi: raw.rssi,
        level: ProximityLevel.far,
      ),
    );

    final prevLevel = state.level;

    final smooth = _applyEma(
      previous: state.smoothRssi,
      current: raw.rssi,
      alpha: _config.emaAlpha,
    );

    state
      ..smoothRssi = smooth
      ..lastRssi = raw.rssi
      ..staleTimer?.cancel();

    state.staleTimer = _scheduleStale(raw.targetToken);

    final nextLevel = _applyHysteresis(prevLevel, smooth, _config.thresholds);
    state.level = nextLevel;

    final intensity = _mapIntensity(smooth, _config.thresholds);

    final enteredNear =
        prevLevel == ProximityLevel.far && nextLevel != ProximityLevel.far;
    final exitedNear =
        prevLevel != ProximityLevel.far && nextLevel == ProximityLevel.far;
    final enteredVeryNear =
        prevLevel != ProximityLevel.veryNear &&
            nextLevel == ProximityLevel.veryNear;
    final exitedVeryNear =
        prevLevel == ProximityLevel.veryNear &&
            nextLevel != ProximityLevel.veryNear;

    _onEvent(
      ProximityEvent(
        targetToken: raw.targetToken,
        rssi: raw.rssi,
        smoothRssi: smooth,
        intensity: intensity,
        level: nextLevel,
        enteredNear: enteredNear,
        exitedNear: exitedNear,
        enteredVeryNear: enteredVeryNear,
        exitedVeryNear: exitedVeryNear,
        timestamp: now,
      ),
    );
  }

  Timer? _scheduleStale(String token) {
    if (_config.staleMs <= 0) {
      return null;
    }

    return Timer(Duration(milliseconds: _config.staleMs), () {
      final state = _states[token];
      if (state == null || state.level == ProximityLevel.far) {
        return;
      }

      final now = _now();
      final prevLevel = state.level;
      final lastSmooth = state.smoothRssi ?? state.lastRssi.toDouble();
      state
        ..level = ProximityLevel.far
        ..smoothRssi = null;

      final exitedNear = prevLevel != ProximityLevel.far;
      final exitedVeryNear = prevLevel == ProximityLevel.veryNear;

      _onEvent(
        ProximityEvent(
          targetToken: token,
          rssi: state.lastRssi,
          smoothRssi: lastSmooth,
          intensity: 0,
          level: ProximityLevel.far,
          enteredNear: false,
          exitedNear: exitedNear,
          enteredVeryNear: false,
          exitedVeryNear: exitedVeryNear,
          timestamp: now,
        ),
      );
    });
  }

  double _applyEma({
    required double? previous,
    required int current,
    required double alpha,
  }) {
    final bounded = alpha.clamp(0, 1).toDouble();
    if (previous == null || !previous.isFinite || !bounded.isFinite) {
      return current.toDouble();
    }
    if (bounded >= 1) {
      return current.toDouble();
    }
    if (bounded <= 0) {
      return previous;
    }
    return (bounded * current) + ((1 - bounded) * previous);
  }

  ProximityLevel _applyHysteresis(
    ProximityLevel currentLevel,
    double smoothRssi,
    Thresholds thresholds,
  ) {
    final enterNear = thresholds.enterNearDbm.toDouble();
    final exitNear = thresholds.exitNearDbm.toDouble();
    final enterVeryNear = thresholds.enterVeryNearDbm.toDouble();
    final exitVeryNear = thresholds.exitVeryNearDbm.toDouble();

    switch (currentLevel) {
      case ProximityLevel.far:
        if (smoothRssi >= enterVeryNear) {
          return ProximityLevel.veryNear;
        }
        if (smoothRssi >= enterNear) {
          return ProximityLevel.near;
        }
        return ProximityLevel.far;
      case ProximityLevel.near:
        if (smoothRssi >= enterVeryNear) {
          return ProximityLevel.veryNear;
        }
        if (smoothRssi <= exitNear) {
          return ProximityLevel.far;
        }
        return ProximityLevel.near;
      case ProximityLevel.veryNear:
        if (smoothRssi <= exitVeryNear) {
          if (smoothRssi <= exitNear) {
            return ProximityLevel.far;
          }
          return ProximityLevel.near;
        }
        return ProximityLevel.veryNear;
    }
  }

  double _mapIntensity(double smoothRssi, Thresholds thresholds) {
    final minDbm = thresholds.minDbm.toDouble();
    final maxDbm = thresholds.maxDbm.toDouble();
    final denom = maxDbm - minDbm;
    if (denom == 0) {
      return smoothRssi >= maxDbm ? 1 : 0;
    }
    final raw = (smoothRssi - minDbm) / denom;
    if (raw <= 0) {
      return 0;
    }
    if (raw >= 1) {
      return 1;
    }
    return raw;
  }
}

class _TargetState {
  _TargetState({
    required this.smoothRssi,
    required this.lastRssi,
    required this.level,
  });

  double? smoothRssi;
  int lastRssi;
  ProximityLevel level;
  Timer? staleTimer;
}
