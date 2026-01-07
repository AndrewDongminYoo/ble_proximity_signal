# ble_proximity_signal_ios

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

iOS implementation of the `ble_proximity_signal` federated plugin.

This is an **endorsed** implementation package. Plugin users should depend on
`ble_proximity_signal` only — this package is pulled automatically by Flutter.

---

## What this package does

- BLE advertising (foreground):
  - Advertises the configured service UUID
  - Encodes token hex into advertising payload (local name)
- BLE scanning:
  - Optionally filters by service UUID (when `debugAllowAll == false`)
  - Allows duplicates (continuous RSSI updates)
  - Extracts token from:
    - service data for the configured UUID, or
    - (fallback) local name if it looks like a token

It emits raw scan events to Dart via the event channel (`RawScanResult` maps).

---

## Foreground-only (by design)

This plugin targets a “metal detector” UX. It is built for **foreground usage**:

- scanning/advertising should be considered best-effort
- background behavior is not a goal for v0.1.0

---

## Info.plist permissions

Your app typically needs Bluetooth usage description strings, e.g.:

- `NSBluetoothAlwaysUsageDescription`

(Exact requirements can vary by iOS version and app configuration.)

If scanning/broadcasting fails:

1. Confirm Bluetooth is ON
2. Confirm permission prompts were shown/accepted
3. Reinstall the app if permission state is stuck

---

## Debug: GATT discovery

This implementation supports `debugDiscoverServices(deviceId:)`:

- Connects to a discovered peripheral
- Discovers services + characteristics
- Returns a textual dump like:

```log

deviceId: <UUID>
name: <peripheral name>
service <uuid>
char <uuid> props=read|write|notify

```

Notes:

- Only works if the peripheral is discoverable/available.
- Discovery is best-effort and can time out (default 8000ms in Dart).

---

## Why Local Name?

CoreBluetooth advertising often omits service data on Apple platforms.
To avoid "silent" payload drops, this plugin uses `CBAdvertisementDataLocalNameKey` to carry the token and falls back to local name when scanning.

---

## Usage

This package is [endorsed][endorsed_link], which means you can simply use `ble_proximity_signal` normally. This package will be automatically included.

[endorsed_link]: https://flutter.dev/docs/development/packages-and-plugins/developing-packages#endorsed-federated-plugin
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
