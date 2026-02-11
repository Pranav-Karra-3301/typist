import Foundation
import IOKit.hid
import TypistCore

final class DeviceClassifier {
    func classify(device: IOHIDDevice?) -> DeviceClass {
        guard let device else {
            return .unknown
        }

        if let builtIn = boolProperty(device: device, key: "Built-In" as CFString), builtIn {
            return .builtIn
        }

        let transport = stringProperty(device: device, key: kIOHIDTransportKey as CFString)?.lowercased()
        if let transport {
            if transport.contains("usb") || transport.contains("bluetooth") {
                return .external
            }
            if transport.contains("spi") || transport.contains("i2c") || transport.contains("internal") {
                return .builtIn
            }
        }

        if let product = stringProperty(device: device, key: kIOHIDProductKey as CFString)?.lowercased(), product.contains("internal") {
            return .builtIn
        }

        return .unknown
    }

    private func boolProperty(device: IOHIDDevice, key: CFString) -> Bool? {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }
        return value as? Bool
    }

    private func stringProperty(device: IOHIDDevice, key: CFString) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }
        return value as? String
    }
}
