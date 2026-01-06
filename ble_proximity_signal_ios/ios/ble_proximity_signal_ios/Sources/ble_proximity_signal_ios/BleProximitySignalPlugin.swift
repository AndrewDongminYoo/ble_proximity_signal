import Flutter
import UIKit
import CoreBluetooth

public class BleProximitySignalPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CBCentralManagerDelegate, CBPeripheralManagerDelegate {

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?

  private var central: CBCentralManager?
  private var peripheral: CBPeripheralManager?

  private var targetTokenSet: Set<String> = []
  private var serviceUUID: CBUUID?
  private var debugAllowAll = false

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

    let serviceData: [CBUUID: Data] = [uuid: tokenBytes]
    let payload: [String: Any] = [
      CBAdvertisementDataServiceUUIDsKey: [uuid],
      CBAdvertisementDataServiceDataKey: serviceData
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

  private func startScanningNow(uuid: CBUUID) {
    stopScan()

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
    central?.stopScan()
    targetTokenSet = []
    debugAllowAll = false
  }

  // MARK: - CBCentralManagerDelegate

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    // If scanning was requested before BT became available, resume here
    if central.state == .poweredOn, let uuid = self.serviceUUID, !self.targetTokenSet.isEmpty {
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
    let tokenHex = tokenBytes.map { bytesToHexLower($0) }

    if !debugAllowAll {
      guard let tokenHex, targetTokenSet.contains(tokenHex) else { return }
    }

    let tsMs = Int(Date().timeIntervalSince1970 * 1000)
    let deviceId = peripheral.identifier.uuidString
    let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let manufacturerDataLen = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.count
    let targetToken = tokenHex ?? deviceId

    var payload: [String: Any] = [
      "targetToken": targetToken,
      "rssi": RSSI.intValue,
      "timestampMs": tsMs,
      "deviceId": deviceId
    ]
    if let localName {
      payload["localName"] = localName
    }
    if let manufacturerDataLen {
      payload["manufacturerDataLen"] = manufacturerDataLen
    }

    eventSink?(payload)
  }

  // MARK: - CBPeripheralManagerDelegate

  public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    // If broadcast was requested before BT became available, resume here
    if peripheral.state == .poweredOn, let uuid = self.serviceUUID {
      // We don't have the last token stored; v0.1.0 requires user to call startBroadcast again
      // If you want auto-resume, store last token bytes in a field.
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
