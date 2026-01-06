# ble_proximity_signal — PLAN

## 0) Goal (v0.1.0 Definition of Done)

**Foreground-only** BLE proximity module for “metal detector” style UX.

**Done when:**

- iOS/Android 최신 폰에서 (앱 전경 상태)
  - (A) 내 토큰을 BLE advertising 할 수 있고
  - (B) 주변에서 advertising 중인 토큰들을 scan 하여
  - (C) 지정한 타깃(최대 5개)만 필터링하고
  - (D) 각 타깃의 RSSI를 안정화(필터)해서 `intensity: 0..1`로 매핑하며
  - (E) `Stream<ProximityEvent>`로 지속 방출한다.
- 플러그인은 **소리/진동/알림 자체는 하지 않는다**. (앱이 intensity를 사용해 구현)
- 단위 테스트: RSSI 필터/히스테리시스/강도 매핑 로직 커버.
- Example 앱에서
  - Broadcast 토큰 설정/시작/중지
  - Scan 타깃 최대 5개 입력/시작/중지
  - 타깃별 RSSI/intensity/proximityLevel 표시

---

## 1) Scope / Non-goals

### In scope

- Foreground scanning + foreground advertising
- Target up to 5 identifiers (tokens)
- RSSI smoothing (EMA) + hysteresis 기반 near/far state
- iOS (CoreBluetooth), Android (BluetoothLeScanner / Advertiser)

### Out of scope (v0.1.0)

- 백그라운드 동작 보장(알림/포그라운드 서비스/region monitoring 등)
- “정확한 거리(m)” 계산(환경 영향이 커서 강도 기반으로만 제공)
- 암호학적 rolling id (v0.2+에서 옵션으로)
- 오디오/진동/푸시 통합(앱 레이어에서 처리)

---

## 2) Architecture (Federated plugin)

- `ble_proximity_signal`
  - Public API (Dart)
  - RSSI -> intensity mapping
  - smoothing + hysteresis + enter/exit event generation
- `ble_proximity_signal_platform_interface`
  - PlatformInterface + models + method/event contracts
- `ble_proximity_signal_android`
  - Android native scanning/advertising implementation
- `ble_proximity_signal_ios`
  - iOS native scanning/advertising implementation

### **Transport**

- v0.1.0: `MethodChannel` + `EventChannel`
- (Optional later) Pigeon으로 타입 안정성 강화

---

## 3) Public API (Draft)

### Core concepts

- Token: 타깃 식별자. 추적 위험을 줄이기 위해 **세션 토큰(임시)** 권장.
- Plugin emits proximity signal only; app decides UX.

### Proposed Dart API (ble_proximity_signal)

```dart
class BleProximitySignal {
  Future<void> startBroadcast({
    required String token, // base64url/hex
    BroadcastConfig config = const BroadcastConfig(),
  });

  Future<void> stopBroadcast();

  Future<void> startScan({
    required List<String> targetTokens, // max 5
    ScanConfig config = const ScanConfig(),
  });

  Future<void> stopScan();

  Stream<ProximityEvent> get events;
}
```

### Config & event models

```dart
class BroadcastConfig {
  final int? txPower; // optional hint, platform-specific
  final String serviceUuid; // default fixed UUID
}

class ScanConfig {
  final String serviceUuid; // same as broadcast
  final double emaAlpha; // default 0.2
  final Thresholds thresholds; // hysteresis thresholds
  final int staleMs; // last-seen timeout (e.g. 1500ms)
}

class Thresholds {
  // Use dBm thresholds, not meters.
  // Example: enterNear=-60, exitNear=-65
  final int enterNearDbm;
  final int exitNearDbm;
  final int enterVeryNearDbm;
  final int exitVeryNearDbm;

  // intensity mapping range
  // intensity=0 at minDbm, intensity=1 at maxDbm
  final int minDbm;
  final int maxDbm;
}

enum ProximityLevel { far, near, veryNear }

class ProximityEvent {
  final String targetToken;
  final int rssi;         // raw dBm
  final double smoothRssi;// EMA dBm
  final double intensity; // 0..1
  final ProximityLevel level;
  final bool enteredNear;
  final bool exitedNear;
  final bool enteredVeryNear;
  final bool exitedVeryNear;
  final DateTime timestamp;
}
```

---

## 4) BLE payload specification (v0.1.0)

### **Default approach: Service UUID + Service Data** (foreground 안정성/구현 단순)

- Advertise:
  - `serviceUuid`: fixed UUID string (default provided in Dart)
  - `serviceData`: token bytes (8~16 bytes 권장)

- Scan:
  - Filter by `serviceUuid`
  - Extract `serviceData` => token
  - Only forward if token matches `targetTokens`

### **Token encoding**

- Dart API는 `String token`으로 받되,
  - 내부에서 `hex` or `base64url` 디코드해서 bytes로 내려준다.

- v0.1.0에서는 간단히:
  - `hex` 우선 지원, 실패 시 base64url 시도 (문서화)

---

## 5) Signal processing (Dart-side)

### EMA smoothing

- `smooth = alpha * rssi + (1-alpha) * prevSmooth`
- per-target state map 유지:
  - lastSeenAt
  - smoothRssi
  - level (with hysteresis)

### Hysteresis (flapping 방지)

- `near`:
  - enter when smoothRssi >= enterNearDbm
  - exit when smoothRssi <= exitNearDbm

- `veryNear` similarly

### Intensity mapping (0..1)

- clamp:
  - `t = (smoothRssi - minDbm) / (maxDbm - minDbm)`
  - `intensity = clamp(t, 0, 1)`

- 앱에서 “삐-삐-” 주기/볼륨/진동 강도 등에 사용

### Stale handling

- scan 결과가 끊기면:
  - `now - lastSeenAt > staleMs` => level=far, intensity=0 (exit 이벤트 발생 가능)

---

## 6) Platform implementations

### Android (ble_proximity_signal_android)

- Permissions (API level에 따라 분기):
  - Android 12+:
    - `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`

  - 필요 시 `ACCESS_FINE_LOCATION` (스캔 동작/정책에 따라)

- Advertising:
  - `BluetoothLeAdvertiser.startAdvertising(...)`
  - `AdvertiseData.Builder().addServiceUuid(...)`
  - `addServiceData(ParcelUuid, tokenBytes)`

- Scanning:
  - `BluetoothLeScanner.startScan(filters, settings, callback)`
  - Filter: service UUID
  - Parse: `ScanRecord.getServiceData(ParcelUuid)`

- EventChannel로 scan result push:
  - `{ token: <hex>, rssi: -55, ts: ... }`

### iOS (ble_proximity_signal_ios)

- `CoreBluetooth`
- Advertising:
  - `CBPeripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: ..., CBAdvertisementDataServiceDataKey: ...])`

- Scanning:
  - `CBCentralManager.scanForPeripherals(withServices: [serviceUUID], options: ...)`
  - 광고 데이터에서 service data 추출

- EventChannel로 scan result push:
  - `{ token: <hex>, rssi: -55, ts: ... }`

**Note:** v0.1.0은 foreground-only이므로 background 모드/옵션은 넣지 않는다.

---

## 7) Repository tasks (Implementation order)

### Milestone 1 — Platform interface contract

- [ ] `ble_proximity_signal_platform_interface`
  - [ ] `BleProximitySignalPlatform` 정의
  - [ ] models (raw scan event)
  - [ ] default method channel impl scaffold

### Milestone 2 — Native scan + advertise (raw)

- [ ] Android: advertise + scan + raw event stream
- [ ] iOS: advertise + scan + raw event stream
- [ ] Example app에서 raw rssi 이벤트 확인

### Milestone 3 — Dart signal processing

- [ ] per-target smoothing map + stale handling
- [ ] hysteresis + intensity mapping
- [ ] ProximityEvent stream 구현
- [ ] 테스트: EMA/히스테리시스/intensity/clamp/stale

### Milestone 4 — Docs & release prep

- [ ] README: setup, permissions, limitations, troubleshooting
- [ ] pubspec topics/metadata 정리
- [ ] v0.1.0 tag + changelog

---

## 8) Default values (initial suggestion)

- `emaAlpha = 0.2`
- thresholds (실내 기준 “감도” 중간값):
  - enterNearDbm = -60
  - exitNearDbm = -65
  - enterVeryNearDbm = -52
  - exitVeryNearDbm = -56

- mapping range:
  - minDbm = -80 (0)
  - maxDbm = -45 (1)

- staleMs = 1500

(환경에 따라 다르므로, Example 앱에서 슬라이더로 조절 가능하면 베스트)

---

## 9) Privacy notes

- 고정 ID 광고는 추적 위험이 있다.
- 권장: 게임 세션 시작 시 서버/QR로 교환한 **임시 토큰**을 사용하고, 세션 종료 시 폐기.
- v0.2+: rolling token 옵션 추가 고려.

---

## 10) Troubleshooting checklist

- 권한 거부 / 스캔 결과 없음:
  - Android 12+ 권한 3종 부여 여부
  - iOS Bluetooth permission string 추가 여부

- advertise 시작 실패:
  - 기기 BLE advertiser 지원 여부
  - 다른 앱이 BLE 기능 점유 중인지 확인

- RSSI 튐:
  - emaAlpha 낮추기 (0.1)
  - hysteresis 폭 키우기 (enter/exit 간격 확대)

---
