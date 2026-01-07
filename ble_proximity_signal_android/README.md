# ble_proximity_signal_android

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

Android implementation of the `ble_proximity_signal` federated plugin.

This is an **endorsed** implementation package. Plugin users should depend on
`ble_proximity_signal` only — this package is pulled automatically by Flutter.

---

## What this package does

- BLE advertising:
  - Adds service UUID
  - Encodes the token into service data
- BLE scanning:
  - Optionally filters by service UUID (when `debugAllowAll == false`)
  - Allows duplicates (continuous RSSI updates for “metal detector” UX)
  - Extracts token from:
    - service data for the configured UUID, or
    - (fallback) local name if it looks like a token

It emits raw scan events to Dart via the event channel (`RawScanResult` maps).

---

## Permissions / requirements (practical)

BLE permissions and policy vary by Android version and device OEM.

Common required permissions (Android 12+):

- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH_ADVERTISE`

Common gotchas:

- Android 12+ typically requires runtime permissions for scan/connect.
- Some devices require location services enabled for reliable scanning.
- Not all devices support BLE advertising.

If scan/broadcast fails:

1. Check Bluetooth state (ON)
2. Check runtime permissions
3. Verify the device supports advertising
4. Try toggling Bluetooth and retry

---

## Debug: GATT discovery

This implementation supports `debugDiscoverServices(deviceId:)`:

- Connects to the device by address
- Discovers services/characteristics
- Returns a textual dump like:

```log
deviceId: XX:XX:XX:XX:XX:XX
name: some device
service <uuid> (primary)
char <uuid> props=read|write|notify

```

Notes:

- Discovery is best-effort and may fail due to permissions, device policy, or timeouts.
- The example app intentionally rate-limits/dedupes logging of discovery dumps.

---

## Development notes

- Scanning uses `ScanSettings.SCAN_MODE_LOW_LATENCY`
- Duplicates enabled for continuous RSSI updates
- `deviceId` is typically a Bluetooth address, but may be unstable on newer Android/privacy regimes.
- Build targets: minSdk 19, compileSdk 34

---

## Usage

This package is [endorsed][endorsed_link], which means you can simply use `ble_proximity_signal` normally. This package will be automatically included.

[endorsed_link]: https://flutter.dev/docs/development/packages-and-plugins/developing-packages#endorsed-federated-plugin
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
