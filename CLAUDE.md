# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`ble_proximity_signal` is a **federated Flutter plugin** for foreground-only BLE proximity detection ("metal detector" UX): advertise a short token, scan for up to 5 target tokens, and emit a smoothed `Stream<ProximityEvent>` with an intensity (0..1) and proximity level (far / near / veryNear).

Explicit non-goals: background reliability, distance-in-meters, rolling IDs, and built-in sound/vibration/notifications (left to the app layer).

## Monorepo layout

The repo root is a **Dart pub workspace** + **melos** workspace (`pubspec.yaml` declares both). Four packages:

- `ble_proximity_signal/` — public Dart API + example app (`example/`)
- `ble_proximity_signal_platform_interface/` — shared contracts, models, and the default `MethodChannel` implementation
- `ble_proximity_signal_android/` — Android impl; native Kotlin in `android/src/main/kotlin/com/andrew/signal/`
- `ble_proximity_signal_ios/` — iOS impl; native Swift in `ios/.../Sources/`

Each package has its own `test/`. The app-facing package maps platforms via `flutter.plugin.platforms.{android,ios}.default_package` in `ble_proximity_signal/pubspec.yaml`.

## Common commands

Run from the repo root unless noted. Prefer melos scripts — they fan out across all packages.

```bash
melos bootstrap          # link workspace packages (run after dependency changes)
melos run test           # flutter test across packages with random ordering seed
melos run test:ci        # same, with --coverage
melos run format         # dart fix --apply + dart format --line-length 120
melos run format:ci      # format check only (--set-exit-if-changed)
melos run generate       # build_runner build for packages that depend on it

trunk fmt                # format NON-Dart files (Kotlin, Swift, YAML, MD, SVG...)
trunk check              # lint NON-Dart files
```

Single package / single test:

```bash
cd ble_proximity_signal && flutter test
cd ble_proximity_signal && flutter test test/ble_proximity_signal_test.dart --plain-name "substring of test name"
```

Example app + integration tests (BLE needs a real device):

```bash
cd ble_proximity_signal/example && flutter run
cd ble_proximity_signal/example && fluttium test flows/test_platform_name.yaml          # UI smoke test
cd ble_proximity_signal/example && patrol test -t integration_test/patrol_test.dart     # native permission / BLE scenarios
```

## Architecture: data flow

The plugin's value lives almost entirely **Dart-side**. Native layers only advertise and emit raw scan results.

1. Native scan callback → emitted over the `ble_proximity_signal/events` `EventChannel` as a map.
2. `RawScanResult.fromMap` (platform interface) validates/parses it. RSSI in dBm, wall-clock `timestampMs`. Extra fields (`deviceId`, `localName`, `serviceUuids`, manufacturer/service data) are debug-only.
3. `SignalProcessor` (`ble_proximity_signal/lib/src/signal_processor.dart`) consumes the raw stream and per target token applies:
   - **EMA smoothing** of RSSI (`SignalConfig.emaAlpha`, default 0.2)
   - **Hysteresis** for level transitions using separate enter/exit thresholds (`Thresholds`)
   - **Intensity** linear-mapped from smoothed RSSI between `minDbm`..`maxDbm`, clamped 0..1
   - a **stale timer** (`staleMs`, default 1500ms) that forces the target back to `far` / intensity 0 if no signal arrives
4. `BleProximitySignal` (the public API) owns the `SignalProcessor`, exposes `events`, and emits `ProximityEvent`s carrying transition flags (`enteredNear`, `exitedVeryNear`, etc.).

Beyond the proximity stream, `BleProximitySignal` exposes a **permission/availability surface** that delegates straight to the platform (no Dart-side processing): `checkPermissions()` and `requestPermissions()` return a `BlePermissionStatus`, `checkAvailability()` returns a `BleAvailability`, and `availabilityChanges` is a `Stream<BleAvailability>`. Both enums live in the platform interface and are re-exported from the app-facing package. On Android, `checkPermissions()` reports `denied` rather than `permanentlyDenied` (the rationale state is only known after a request).

Method/event channel names are the constants `'ble_proximity_signal'` (MethodChannel) and `'ble_proximity_signal/events'` (EventChannel) — **identical across the platform interface, android, and ios Dart classes**. Keep them in sync if you change one.

### Federated plugin contract

`BleProximitySignalPlatform` (platform interface) is the abstract contract; platform packages **extend** it (never `implements`) and call `registerWith()` to set `BleProximitySignalPlatform.instance`. Adding a method to the interface must be reflected in `MethodChannelBleProximitySignal`, `BleProximitySignalAndroid`, and `BleProximitySignalIOS` — plus the native Kotlin/Swift handlers.

### Token handling

Token normalization happens in the Dart wrapper (`_normalizeToken` in `ble_proximity_signal/lib/src/ble_proximity_signal.dart`), not natively: hex (even length, lowercased) or base64url/base64 (decoded to lowercase hex). Invalid input throws `FormatException`. The `targetTokens <= 5` limit is enforced here too (bypassed by `ScanConfig.debugAllowAll`).

## Conventions

- **Dart lint:** `very_good_analysis` (per-package `analysis_options.yaml`). Format width is **120 columns** (`dart format --line-length 120`) — note this differs from Dart's default 80.
- **Dart is deliberately disabled in trunk** (`.trunk/trunk.yaml`); run Dart formatting/analysis via melos/`flutter`. trunk owns Kotlin (ktlint), Swift (swiftformat), YAML, Markdown, SVG, and secret scanning. Both gates should pass before a PR.
- **Public members need doc comments** (very_good enforces this) — even trivial constructors carry `///` lines here.
- **Commits:** Conventional Commits with gitmoji, e.g. `feat: ✨ ...`, `chore: 🔨 ...`. No Co-Author lines.
- Each package is independently versioned (currently `0.2.0`).

## Testing notes

- Frameworks: `flutter_test` + `mocktail`. Name tests by behavior in `*_test.dart`.
- `SignalProcessor` takes an injectable `now` clock — use it to test stale-timeout and timestamp logic deterministically.
- Integration testing comparison and rationale (Fluttium for UI smoke, Patrol for native BLE/permission dialogs) is documented in `INTEGRATION_TESTING.md`.
