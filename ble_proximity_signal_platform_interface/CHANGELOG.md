# Changelog

## 0.2.0

- Add `BleAvailability` and `BlePermissionStatus` enums with wire-name parsing.
- Add `checkPermissions`, `requestPermissions`, `checkAvailability`, and the
  `availabilityChanges` stream to the platform contract.
- Export `MethodChannelBleProximitySignal`; add the
  `ble_proximity_signal/availability` event channel.

## 0.1.0+1

- Initial release.
- Platform contract for broadcast/scan plus `scanResults` event stream.
- Shared models: `BroadcastConfig`, `ScanConfig`, and `RawScanResult`.
- Debug fields for local name / service data / manufacturer data (including hex payloads).
- Debug `debugDiscoverServices` contract for GATT discovery dumps.
