/// Proximity buckets derived from RSSI.
enum ProximityLevel { far, near, veryNear }

/// Smoothed proximity signal for a single target token.
class ProximityEvent {
  const ProximityEvent({
    required this.targetToken,
    required this.rssi,
    required this.smoothRssi,
    required this.intensity,
    required this.level,
    required this.enteredNear,
    required this.exitedNear,
    required this.enteredVeryNear,
    required this.exitedVeryNear,
    required this.timestamp,
  });

  /// Token (normalized hex) for the advertising device.
  final String targetToken;

  /// Raw RSSI in dBm.
  final int rssi;

  /// Smoothed RSSI in dBm (EMA).
  final double smoothRssi;

  /// Mapped intensity from 0..1.
  final double intensity;

  /// Current proximity level.
  final ProximityLevel level;

  /// True when crossing into near (far -> near/veryNear).
  final bool enteredNear;

  /// True when crossing out of near (near/veryNear -> far).
  final bool exitedNear;

  /// True when crossing into very near.
  final bool enteredVeryNear;

  /// True when crossing out of very near.
  final bool exitedVeryNear;

  /// Event timestamp (Dart-side clock).
  final DateTime timestamp;

  @override
  String toString() {
    return 'ProximityEvent(token=$targetToken, rssi=$rssi, '
        'smooth=$smoothRssi, intensity=$intensity, '
        'level=$level, ts=$timestamp)';
  }
}
