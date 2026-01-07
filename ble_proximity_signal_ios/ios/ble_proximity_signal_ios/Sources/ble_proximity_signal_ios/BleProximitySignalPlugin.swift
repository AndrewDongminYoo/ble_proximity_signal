import Flutter
import UIKit
import CoreBluetooth

public class BleProximitySignalPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate {

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  private var central: CBCentralManager?
  private var peripheral: CBPeripheralManager?

  private var targetTokenSet: Set<String> = []
  private var serviceUUID: CBUUID?
  private var debugAllowAll = false
  private var discoveredPeripherals: [String: CBPeripheral] = [:]
  private var pendingDiscovery: DiscoveryContext?

  private class DiscoveryContext {
    let deviceId: String
    let peripheral: CBPeripheral
    let result: FlutterResult
    var services: [CBService] = []
    var characteristics: [CBUUID: [CBCharacteristic]] = [:]
    var remainingCharacteristics = 0
    var timeoutTimer: Timer?

    init(deviceId: String, peripheral: CBPeripheral, result: @escaping FlutterResult) {
      self.deviceId = deviceId
      self.peripheral = peripheral
      self.result = result
    }
  }

  // MARK: - FlutterPlugin

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = BleProximitySignalPlugin()

    let method = FlutterMethodChannel(name: "ble_proximity_signal", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(name: "ble_proximity_signal/events", binaryMessenger: registrar.messenger())

    instance.methodChannel = method
    instance.eventChannel = events

    registrar.addMethodCallDelegate(instance, channel: method)
    events.setStreamHandler(instance)

    // Managers are lazily created to keep init lightweight
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {

      case "startBroadcast":
        guard let args = call.arguments as? [String: Any] else {
          return result(FlutterError(code: "invalid_args", message: "Missing args", details: nil))
        }
        guard let token = args["token"] as? String else {
          return result(FlutterError(code: "invalid_args", message: "Missing 'token'", details: nil))
        }
        guard let serviceUuidStr = args["serviceUuid"] as? String else {
          return result(FlutterError(code: "invalid_args", message: "Missing 'serviceUuid'", details: nil))
        }

        try startBroadcast(token: token, serviceUuidStr: serviceUuidStr)
        result(nil)

      case "stopBroadcast":
        stopBroadcast()
        result(nil)

      case "startScan":
        guard let args = call.arguments as? [String: Any] else {
          return result(FlutterError(code: "invalid_args", message: "Missing args", details: nil))
        }
        guard let tokens = args["targetTokens"] as? [String] else {
          return result(FlutterError(code: "invalid_args", message: "Missing 'targetTokens'", details: nil))
        }
        guard let serviceUuidStr = args["serviceUuid"] as? String else {
          return result(FlutterError(code: "invalid_args", message: "Missing 'serviceUuid'", details: nil))
        }
        let debugAllowAll = args["debugAllowAll"] as? Bool ?? false

        try startScan(targetTokens: tokens, serviceUuidStr: serviceUuidStr, debugAllowAll: debugAllowAll)
        result(nil)

      case "stopScan":
        stopScan()
        result(nil)

      case "debugDiscoverServices":
        guard let args = call.arguments as? [String: Any] else {
          return result(FlutterError(code: "invalid_args", message: "Missing args", details: nil))
        }
        guard let deviceId = args["deviceId"] as? String else {
          return result(FlutterError(code: "invalid_args", message: "Missing 'deviceId'", details: nil))
        }
        let timeoutMs = args["timeoutMs"] as? Int ?? 8000

        debugDiscoverServices(deviceId: deviceId, timeoutMs: timeoutMs, result: result)

      default:
        result(FlutterError(code: "not_implemented", message: "Method not implemented", details: nil))
      }
    } catch let err {
      result(FlutterError(code: "native_error", message: err.localizedDescription, details: nil))
    }
  }

  // MARK: - StreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - Broadcast (Advertising)

  private func startBroadcast(token: String, serviceUuidStr: String) throws {
    let uuid = CBUUID(string: serviceUuidStr)
    self.serviceUUID = uuid

    if peripheral == nil {
      peripheral = CBPeripheralManager(delegate: self, queue: nil)
    }

    guard let tokenBytes = decodeTokenToBytes(token) else {
      throw NSError(domain: "ble_proximity_signal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid token format (expected hex or base64url/base64)"])
    }

    // If not powered on yet, we can still store state; advertising will start in delegate callback.
    if peripheral?.state == .poweredOn {
      startAdvertisingNow(uuid: uuid, tokenBytes: tokenBytes)
    }
  }

  private func startAdvertisingNow(uuid: CBUUID, tokenBytes: Data) {
    stopBroadcast()

    guard let peripheral = peripheral, peripheral.state == .poweredOn else { return }

    let tokenHex = bytesToHexLower(tokenBytes)
    let payload: [String: Any] = [
      CBAdvertisementDataServiceUUIDsKey: [uuid],
      CBAdvertisementDataLocalNameKey: tokenHex
    ]
    peripheral.startAdvertising(payload)
  }

  private func stopBroadcast() {
    peripheral?.stopAdvertising()
  }

  // MARK: - Scan

  private func startScan(targetTokens: [String], serviceUuidStr: String, debugAllowAll: Bool) throws {
    if !debugAllowAll, targetTokens.count > 5 {
      throw NSError(domain: "ble_proximity_signal", code: 2, userInfo: [NSLocalizedDescriptionKey: "targetTokens must be <= 5"])
    }

    let uuid = CBUUID(string: serviceUuidStr)
    self.serviceUUID = uuid
    self.debugAllowAll = debugAllowAll

    // Normalize tokens to hex lowercase
    self.targetTokenSet = debugAllowAll ? [] : Set(targetTokens.compactMap { normalizeTokenToHex($0) })

    if central == nil {
      central = CBCentralManager(delegate: self, queue: nil)
    }

    // If already powered on, start immediately. Otherwise start in delegate callback.
    if central?.state == .poweredOn {
      startScanningNow(uuid: uuid)
    }
  }

  private func stopScanInternal(resetState: Bool) {
    central?.stopScan()
    if resetState {
      targetTokenSet = []
      debugAllowAll = false
    }
  }

  private func startScanningNow(uuid: CBUUID) {
    stopScanInternal(resetState: false)

    guard let central = central, central.state == .poweredOn else { return }

    // Allow duplicates so we get continuous RSSI updates (metal detector UX)
    let options: [String: Any] = [CBCentralManagerScanOptionAllowDuplicatesKey: true]
    if debugAllowAll {
      central.scanForPeripherals(withServices: nil, options: options)
    } else {
      central.scanForPeripherals(withServices: [uuid], options: options)
    }
  }

  private func stopScan() {
    stopScanInternal(resetState: true)
  }

  // MARK: - Debug Discovery

  private func debugDiscoverServices(
    deviceId: String,
    timeoutMs: Int,
    result: @escaping FlutterResult
  ) {
    if pendingDiscovery != nil {
      result(FlutterError(code: "busy", message: "Discovery already in progress", details: nil))
      return
    }
    if central == nil {
      central = CBCentralManager(delegate: self, queue: nil)
    }
    guard let central = central else {
      result(FlutterError(code: "unavailable", message: "Central manager unavailable", details: nil))
      return
    }
    guard central.state == .poweredOn else {
      result(FlutterError(code: "unavailable", message: "Bluetooth is off", details: nil))
      return
    }
    guard let uuid = UUID(uuidString: deviceId) else {
      result(FlutterError(code: "invalid_args", message: "Invalid deviceId", details: nil))
      return
    }

    let peripheral =
      discoveredPeripherals[deviceId]
        ?? central.retrievePeripherals(withIdentifiers: [uuid]).first
    guard let target = peripheral else {
      result(FlutterError(code: "not_found", message: "Device not found", details: nil))
      return
    }

    let context = DiscoveryContext(deviceId: deviceId, peripheral: target, result: result)
    context.timeoutTimer = Timer.scheduledTimer(withTimeInterval: Double(timeoutMs) / 1000.0, repeats: false) {
      [weak self] _ in
      self?.finishDiscovery(context: context, errorMessage: "Timeout after \(timeoutMs)ms")
    }
    pendingDiscovery = context
    target.delegate = self
    central.connect(target, options: nil)
  }

  // MARK: - CBCentralManagerDelegate

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    // If scanning was requested before BT became available, resume here
    if central.state == .poweredOn,
       let uuid = self.serviceUUID,
       (debugAllowAll || !self.targetTokenSet.isEmpty) {
      startScanningNow(uuid: uuid)
    }
  }

  public func centralManager(_ central: CBCentralManager,
                             didDiscover peripheral: CBPeripheral,
                             advertisementData: [String : Any],
                             rssi RSSI: NSNumber) {
    guard let uuid = self.serviceUUID else { return }
    let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
    let tokenBytes = serviceData?[uuid]
    let tokenHexFromServiceData = tokenBytes.map { bytesToHexLower($0) }
    let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let tokenHexFromLocalName = localName.flatMap { normalizeTokenToHex($0) }
    let tokenHex = tokenHexFromServiceData ?? tokenHexFromLocalName

    if !debugAllowAll {
      guard let tokenHex, targetTokenSet.contains(tokenHex) else { return }
    }

    let tsMs = Int(Date().timeIntervalSince1970 * 1000)
    let deviceId = peripheral.identifier.uuidString
    discoveredPeripherals[deviceId] = peripheral
    let manufacturerDataLen = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.count
    let manufacturerDataHex =
      (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { bytesToHexLower($0) }
    let serviceDataLen = serviceData?.reduce(0) { $0 + $1.value.count }
    let serviceDataUuids = serviceData?.keys.map { $0.uuidString }
    let serviceDataHex =
      serviceData?.reduce(into: [String: String]()) { partial, entry in
        partial[entry.key.uuidString] = bytesToHexLower(entry.value)
      }
    let serviceUuids =
      (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString }
    let targetToken = tokenHex ?? deviceId
    let localNameHex = localName?.data(using: .utf8).map { bytesToHexLower($0) }

    var payload: [String: Any] = [
      "targetToken": targetToken,
      "rssi": RSSI.intValue,
      "timestampMs": tsMs,
      "deviceId": deviceId
    ]
    if let localName {
      payload["localName"] = localName
    }
    if let localNameHex {
      payload["localNameHex"] = localNameHex
    }
    if let manufacturerDataLen {
      payload["manufacturerDataLen"] = manufacturerDataLen
    }
    if let manufacturerDataHex {
      payload["manufacturerDataHex"] = manufacturerDataHex
    }
    if let serviceDataLen, serviceDataLen > 0 {
      payload["serviceDataLen"] = serviceDataLen
    }
    if let serviceDataUuids, !serviceDataUuids.isEmpty {
      payload["serviceDataUuids"] = serviceDataUuids
    }
    if let serviceDataHex, !serviceDataHex.isEmpty {
      payload["serviceDataHex"] = serviceDataHex
    }
    if let serviceUuids, !serviceUuids.isEmpty {
      payload["serviceUuids"] = serviceUuids
    }

    eventSink?(payload)
  }

  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard let context = pendingDiscovery, context.peripheral == peripheral else { return }
    peripheral.discoverServices(nil)
  }

  public func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    guard let context = pendingDiscovery, context.peripheral == peripheral else { return }
    finishDiscovery(context: context, errorMessage: error?.localizedDescription ?? "Connect failed")
  }

  public func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    guard let context = pendingDiscovery, context.peripheral == peripheral else { return }
    if let error {
      finishDiscovery(context: context, errorMessage: error.localizedDescription)
    }
  }

  // MARK: - CBPeripheralDelegate

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let context = pendingDiscovery, context.peripheral == peripheral else { return }
    if let error {
      finishDiscovery(context: context, errorMessage: error.localizedDescription)
      return
    }
    let services = peripheral.services ?? []
    context.services = services
    if services.isEmpty {
      finishDiscovery(context: context, errorMessage: nil)
      return
    }
    context.remainingCharacteristics = services.count
    for service in services {
      peripheral.discoverCharacteristics(nil, for: service)
    }
  }

  public func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard let context = pendingDiscovery, context.peripheral == peripheral else { return }
    if let error {
      finishDiscovery(context: context, errorMessage: error.localizedDescription)
      return
    }
    context.characteristics[service.uuid] = service.characteristics ?? []
    context.remainingCharacteristics -= 1
    if context.remainingCharacteristics <= 0 {
      finishDiscovery(context: context, errorMessage: nil)
    }
  }

  private func finishDiscovery(context: DiscoveryContext, errorMessage: String?) {
    context.timeoutTimer?.invalidate()
    context.timeoutTimer = nil
    pendingDiscovery = nil
    central?.cancelPeripheralConnection(context.peripheral)

    if let errorMessage {
      context.result(FlutterError(code: "debug_discover_failed", message: errorMessage, details: nil))
      return
    }
    let dump = buildDiscoveryDump(context: context)
    context.result(dump)
  }

  private func buildDiscoveryDump(context: DiscoveryContext) -> String {
    var lines: [String] = []
    lines.append("deviceId: \(context.deviceId)")
    let name = context.peripheral.name ?? "unknown"
    lines.append("name: \(name)")
    for service in context.services {
      lines.append("service \(service.uuid.uuidString)")
      let characteristics = context.characteristics[service.uuid] ?? []
      for ch in characteristics {
        let props = describeProperties(ch.properties)
        lines.append("  char \(ch.uuid.uuidString) props=\(props)")
      }
    }
    return lines.joined(separator: "\n")
  }

  private func describeProperties(_ properties: CBCharacteristicProperties) -> String {
    var parts: [String] = []
    if properties.contains(.read) { parts.append("read") }
    if properties.contains(.write) { parts.append("write") }
    if properties.contains(.writeWithoutResponse) { parts.append("writeNoResponse") }
    if properties.contains(.notify) { parts.append("notify") }
    if properties.contains(.indicate) { parts.append("indicate") }
    if properties.contains(.authenticatedSignedWrites) { parts.append("signedWrite") }
    if properties.contains(.extendedProperties) { parts.append("extendedProps") }
    return parts.isEmpty ? "none" : parts.joined(separator: "|")
  }

  // MARK: - CBPeripheralManagerDelegate

  public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    // If broadcast was requested before BT became available, resume here
    if peripheral.state == .poweredOn, let uuid = self.serviceUUID {
      // We don't have the last token stored; v0.1.0 requires user to call startBroadcast again
      // If you want auto-resume, store last token bytes in a field.
    }
  }

  public func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager,
    error: Error?
  ) {
    if let error {
      print("didStartAdvertising error:", error)
    } else {
      print("Advertising started")
    }
  }

  // MARK: - Token helpers

  private func normalizeTokenToHex(_ token: String) -> String? {
    guard let bytes = decodeTokenToBytes(token) else { return nil }
    return bytesToHexLower(bytes)
  }

  private func decodeTokenToBytes(_ token: String) -> Data? {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

    // hex
    let hexSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
    if trimmed.count % 2 == 0, trimmed.rangeOfCharacter(from: hexSet.inverted) == nil {
      var data = Data(capacity: trimmed.count / 2)
      var idx = trimmed.startIndex
      while idx < trimmed.endIndex {
        let next = trimmed.index(idx, offsetBy: 2)
        let byteStr = String(trimmed[idx..<next])
        guard let b = UInt8(byteStr, radix: 16) else { return nil }
        data.append(b)
        idx = next
      }
      return data
    }

    // base64url/base64
    var normalized = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let mod = normalized.count % 4
    if mod == 2 { normalized += "==" }
    else if mod == 3 { normalized += "=" }

    return Data(base64Encoded: normalized)
  }

  private func bytesToHexLower(_ data: Data) -> String {
    return data.map { String(format: "%02x", $0) }.joined()
  }
}
