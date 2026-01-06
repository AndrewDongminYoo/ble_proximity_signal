/// Thresholds for proximity hysteresis and intensity mapping.
class Thresholds {
  /// Thresholds for proximity hysteresis and intensity mapping.
  const Thresholds({
    this.enterNearDbm = -60,
    this.exitNearDbm = -65,
    this.enterVeryNearDbm = -52,
    this.exitVeryNearDbm = -56,
    this.minDbm = -80,
    this.maxDbm = -45,
  });

  /// dBm threshold to enter near.
  final int enterNearDbm;

  /// dBm threshold to exit near.
  final int exitNearDbm;

  /// dBm threshold to enter very near.
  final int enterVeryNearDbm;

  /// dBm threshold to exit very near.
  final int exitVeryNearDbm;

  /// Minimum dBm used to map intensity to 0.
  final int minDbm;

  /// Maximum dBm used to map intensity to 1.
  final int maxDbm;
}

/// Dart-side signal processing configuration.
class SignalConfig {
  /// Dart-side signal processing configuration.
  const SignalConfig({
    this.emaAlpha = 0.2,
    this.thresholds = const Thresholds(),
    this.staleMs = 1500,
  });

  /// Exponential moving average alpha (0..1).
  final double emaAlpha;

  /// Hysteresis thresholds + intensity mapping bounds.
  final Thresholds thresholds;

  /// Stale timeout in milliseconds.
  final int staleMs;
}
