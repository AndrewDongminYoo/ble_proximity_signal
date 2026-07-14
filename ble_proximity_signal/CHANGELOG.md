# Changelog

## 0.2.1

- Document the permission/availability API (`requestPermissions`,
  `checkPermissions`, `checkAvailability`, `availabilityChanges`) in the README
  and drop stale version labels. Docs only; no API changes.

## 0.2.0

- Add `checkPermissions`, `requestPermissions`, and `checkAvailability` plus an
  `availabilityChanges` stream to `BleProximitySignal`.
- Re-export `BleAvailability` and `BlePermissionStatus`.

## 0.1.0+1

- Initial release.
- Foreground-only BLE API for broadcast/scan with `Stream<ProximityEvent>`.
- Signal processing: EMA smoothing, hysteresis, intensity mapping, stale timeout handling.
- Debug utilities: raw scan stream/log and GATT service discovery dump helper.
