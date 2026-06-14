# Changelog

## 0.2.0

- Implement `checkPermissions` / `requestPermissions` (ActivityAware runtime flow
  with `permanentlyDenied` detection) and `checkAvailability`.
- Emit adapter on/off changes on the `ble_proximity_signal/availability` stream
  via a `BluetoothAdapter.ACTION_STATE_CHANGED` receiver.
- Reduce the Dart implementation to a thin `MethodChannelBleProximitySignal`
  subclass.

## 0.1.0+1

- Initial release.
- Android BLE advertising with service UUID + service data token.
- Scanning with optional UUID filtering and local name token fallback.
- Raw scan payload includes device identifiers and debug hex payloads.
- Debug GATT discovery helper for service/characteristic dumps.
