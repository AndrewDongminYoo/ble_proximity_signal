# ble_proximity_signal

[![Very Good Ventures][logo_white]][very_good_ventures_link_dark]
[![Very Good Ventures][logo_black]][very_good_ventures_link_light]

Developed with 💙 by [Very Good Ventures][very_good_ventures_link] 🦄

![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-3-Clause][license_badge]][license_link]

`ble_proximity_signal` is a **foreground-only** BLE proximity module for a “metal detector” style UX.

- **Broadcast:** advertise a short token
- **Scan:** scan nearby tokens (up to **5 targets**) and track signal strength
- **Signal processing:** smooth RSSI (EMA) and map it to **intensity (0..1)** + proximity levels

This package contains:

- The public Dart API (`BleProximitySignal`)
- Signal processing (smoothing/hysteresis/intensity mapping)
- Shared models used by the example app

> This plugin is designed for immediate feedback while the app is in the foreground.
> It does **not** claim background reliability or distance-in-meters.

---

## Quickstart

### 1) Start broadcasting a token

```dart
final ble = BleProximitySignal();

await ble.startBroadcast(token: 'a1b2c3d4'); // hex or base64url/base64
```

### 2) Scan and listen to proximity events

```dart
final ble = BleProximitySignal();

await ble.startScan(targetTokens: ['a1b2c3d4']); // max 5 tokens

final sub = ble.events.listen((event) {
  // event.intensity: 0..1
  // event.level: far / near / veryNear
  // event.rssi + event.smoothRssi
  print('level=${event.level} intensity=${event.intensity} rssi=${event.rssi}');
});
```

Stop when done:

```dart
await sub.cancel();
await ble.stopScan();
await ble.stopBroadcast();
await ble.dispose();
```

---

## Token format

`token` (broadcast) and `targetTokens` (scan) accept:

- **Hex string** (even length): `a1b2c3d4`
- **base64url / base64** (padding optional): decoded and normalized to hex internally

Normalization behavior:

- hex input is lowercased
- base64url/base64 input is decoded to bytes and converted to hex lowercase

If the token cannot be parsed, the Dart wrapper throws `FormatException`.

---

## API overview

### `BleProximitySignal`

- `startBroadcast(token:, config:)` / `stopBroadcast()`
- `startScan(targetTokens:, config:, signalConfig:)` / `stopScan()`
- `Stream<ProximityEvent> get events`
  Smoothed/hysteresis-applied stream intended for UX.
- `Stream<RawScanResult> get rawScanResults`
  Debug-only. Raw scan events coming from native.
- `rawScanLog(maxEntries:)`
  Debug buffer utility.
- `debugDiscoverServices(deviceId:)`
  Debug helper: connect + dump services/characteristics.

### `ProximityEvent` (high level event)

- `intensity` (0..1)
- `level` (`far/near/veryNear`)
- `rssi`, `smoothRssi`
- `deviceId`, `deviceName`, etc. (best-effort, platform dependent)

---

## Configuration

### `ScanConfig` (native filtering)

- `serviceUuid` (default: `BroadcastConfig.defaultServiceUuid`)
- `debugAllowAll` (if true, scan all peripherals without UUID/token filtering)

### `SignalConfig` (Dart-side signal processing)

Controls EMA smoothing + thresholds/hysteresis (see source).

---

## Limitations / Non-goals (v0.1.0)

- Foreground-only (no background guarantees)
- No distance-in-meters
- No rolling IDs (v0.2+)
- No built-in sound/vibration/notifications (left to the app layer)

---

## Example app

The example app (`example/`) provides:

- Start/stop scan
- Start/stop broadcast
- “metal detector” UX using intensity (beep/visual)
- Debug mode: scan all peripherals + visible device list
- Debug probe: tap a device to run a **service/characteristic discovery dump**

Run:

```sh
cd example
flutter run
```

---

## Integration tests 🧪 (Fluttium)

This repository uses [fluttium][fluttium_link] for integration tests (located in the example app).

Install the CLI: [fluttium_cli install guide][fluttium_install]

Run the flow:

```sh
cd example
fluttium test flows/test_platform_name.yaml
```

> Note: the provided flow is a UI smoke test for the example app.
> If you change UI labels/buttons, update the flow steps accordingly.

---

## Troubleshooting (fast path)

- Bluetooth ON?
- Permissions granted? (Android 12+ requires runtime permissions for scan/connect)
- Device supports BLE advertising? (some devices do not)
- If scan/broadcast silently fails, try toggling Bluetooth and re-run.

---

## Permissions (practical)

Permissions vary by OS version and vendor.

### Android 12+

- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `BLUETOOTH_ADVERTISE`

These require runtime permission prompts on modern Android.

### iOS

- `NSBluetoothAlwaysUsageDescription` in `Info.plist`

---

[coverage_badge]: coverage_badge.svg
[license_badge]: https://img.shields.io/badge/license-BSD-green.svg
[license_link]: https://opensource.org/license/bsd-3-clause
[logo_black]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_black.png#gh-light-mode-only
[logo_white]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_white.png#gh-dark-mode-only
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[very_good_ventures_link]: https://verygood.ventures/?utm_source=github&utm_medium=banner&utm_campaign=core
[very_good_ventures_link_dark]: https://verygood.ventures/?utm_source=github&utm_medium=banner&utm_campaign=core#gh-dark-mode-only
[very_good_ventures_link_light]: https://verygood.ventures/?utm_source=github&utm_medium=banner&utm_campaign=core#gh-light-mode-only
[fluttium_link]: https://fluttium.dev/
[fluttium_install]: https://fluttium.dev/docs/getting-started/installing-cli
