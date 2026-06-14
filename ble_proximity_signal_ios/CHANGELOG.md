# Changelog

## 0.2.0

- Implement `checkPermissions` / `requestPermissions` (non-prompting
  `CBManager.authorization` reads; implicit prompt via the central manager) and
  `checkAvailability`.
- Forward availability changes from `centralManagerDidUpdateState` on the
  `ble_proximity_signal/availability` stream.
- Reduce the Dart implementation to a thin `MethodChannelBleProximitySignal`
  subclass.

## 0.1.0+1

- Initial release.
- iOS BLE advertising with service UUID + local name token.
- Scanning with optional UUID filtering and local name token fallback.
- Raw scan payload includes device identifiers and debug hex payloads.
- Debug GATT discovery helper for service/characteristic dumps.
