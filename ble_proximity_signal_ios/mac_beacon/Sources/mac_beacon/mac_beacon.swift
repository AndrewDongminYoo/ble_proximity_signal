import Foundation
import CoreBluetooth

final class Beacon: NSObject, CBPeripheralManagerDelegate {
  private var pm: CBPeripheralManager!
  private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
  private let tokenHex: String = "a1b2c3d4"

  override init() {
    super.init()
    pm = CBPeripheralManager(delegate: self, queue: nil)
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    print("Peripheral state =", peripheral.state.rawValue)
    guard peripheral.state == .poweredOn else { return }

    guard let tokenData = Data(hex: tokenHex) else {
      print("Invalid hex token")
      return
    }

    let serviceData: [CBUUID: Data] = [serviceUUID: tokenData]
    let payload: [String: Any] = [
      CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
      CBAdvertisementDataServiceDataKey: serviceData
    ]

    pm.stopAdvertising()
    pm.startAdvertising(payload)
    print("Advertising started. token=\(tokenHex)")
  }
}

extension Data {
  init?(hex: String) {
    let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard s.count % 2 == 0 else { return nil }
    var data = Data()
    var idx = s.startIndex
    while idx < s.endIndex {
      let next = s.index(idx, offsetBy: 2)
      let byteStr = s[idx..<next]
      guard let b = UInt8(byteStr, radix: 16) else { return nil }
      data.append(b)
      idx = next
    }
    self = data
  }
}

let _ = Beacon()
RunLoop.main.run()
