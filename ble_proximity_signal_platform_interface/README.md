# ble_proximity_signal_platform_interface

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

A common platform interface for the `ble_proximity_signal` federated plugin.

This package defines:

- Platform contract (`BleProximitySignalPlatform`)
- Shared configuration models (`ScanConfig`, `BroadcastConfig`)
- Shared raw model (`RawScanResult`)

If you are a plugin user, you typically **do not depend on this package directly**.
If you are implementing a new platform (or maintaining Android/iOS implementations), this is the source of truth.

---

## Overview

### Contract shape

Platform implementations must provide:

- `startBroadcast(token:, config:)` / `stopBroadcast()`
- `startScan(targetTokens:, config:)` / `stopScan()`
- `debugDiscoverServices(deviceId:, timeoutMs:)` (debug helper)
- `Stream<RawScanResult> get scanResults` (event stream)

The `ble_proximity_signal` Dart wrapper consumes this stream and applies smoothing/hysteresis
to produce `Stream<ProximityEvent>`.

---

## `RawScanResult` payload contract

Platforms must emit `RawScanResult.fromMap(...)` compatible maps over the event channel.
Minimum required fields:

- `targetToken` (String)
- `rssi` (int)
- `timestampMs` (int, epoch millis)

Optional fields (best-effort, may be null):

- `deviceId`, `deviceName`, `localName`, `localNameHex`
- `manufacturerDataLen`, `manufacturerDataHex`
- `serviceDataLen`, `serviceDataUuids`, `serviceDataHex`
- `serviceUuids`

### Notes

- `timestampMs` uses **Unix epoch ms** for cross-platform consistency.
- `targetToken` is the identifier extracted from the advertising payload.
  In debug modes, implementations may fall back to `deviceId`.
- `localNameHex`, `serviceDataHex`, and `manufacturerDataHex` should contain hex-encoded payloads for debugging; keep them compact and best-effort.

---

## Config models

### `BroadcastConfig`

- `serviceUuid` (String, 128-bit UUID)
- `txPower` (int? hint; platform may ignore)

### `ScanConfig`

- `serviceUuid` (String)
- `debugAllowAll` (bool)

The Dart wrapper enforces `targetTokens.length <= 5` when `debugAllowAll == false`.
Platforms may enforce as well.

---

## Implementing a new platform

Create a package and extend `BleProximitySignalPlatform`.

Key rules:

1. Register your implementation by setting `BleProximitySignalPlatform.instance = ...`
2. Stream raw scan events via `scanResults`
3. Match map keys exactly for `RawScanResult.fromMap`

Recommended checklist:

- [ ] Event channel emits required keys (`targetToken`, `rssi`, `timestampMs`)
- [ ] `timestampMs` uses epoch milliseconds
- [ ] `startScan` can accept up to 5 target tokens
- [ ] Best-effort populate optional debug fields
- [ ] `stopScan` and `stopBroadcast` are idempotent
- [ ] Debug discovery returns a human-readable dump string

Example debug discovery output:

```log
deviceId: <id>
name: <device name>
service <uuid>
  char <uuid> props=read|notify
```

---

[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
