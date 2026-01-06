/// Proximity buckets derived from RSSI.
enum ProximityLevel {
  /// Far (No signal)
  far,

  /// Close (Signal detected)
  near,

  /// Very close (Signal increasing)
  veryNear,
}

/// Smoothed proximity signal for a single target token.
class ProximityEvent {
  /// Smoothed proximity signal for a single target token.
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
    this.deviceId,
    this.deviceName,
    this.localName,
    this.manufacturerDataLen,
  });

  /// Token (normalized hex) for the advertising device.
  /// In debug mode, this may fall back to the device identifier.
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

  /// Debug: device identifier (may be randomized on Android).
  final String? deviceId;

  /// Debug: device name if available.
  final String? deviceName;

  /// Debug: advertised local name if available.
  final String? localName;

  /// Debug: manufacturer data length if available.
  final int? manufacturerDataLen;

  @override
  String toString() {
    return 'ProximityEvent(token=$targetToken, rssi=$rssi, '
        'smooth=$smoothRssi, intensity=$intensity, '
        'level=$level, ts=$timestamp, deviceId=$deviceId, '
        'deviceName=$deviceName, localName=$localName, '
        'manufacturerDataLen=$manufacturerDataLen)';
  }
}
