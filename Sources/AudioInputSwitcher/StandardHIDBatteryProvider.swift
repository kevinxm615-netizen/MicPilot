import Foundation
import IOKit.hid

struct StandardHIDBatteryProvider {
    func sample(vendorID: Int) -> [WirelessMicTransmitterBattery]? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [kIOHIDVendorIDKey as String: vendorID]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        var percentages: [Int] = []

        for device in devices {
            guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
                continue
            }
            defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

            guard let elements = IOHIDDeviceCopyMatchingElements(
                device,
                [kIOHIDElementUsagePageKey as String: 0x85] as CFDictionary,
                IOOptionBits(kIOHIDOptionsTypeNone)
            ) as? [IOHIDElement] else { continue }

            for element in elements {
                let usage = IOHIDElementGetUsage(element)
                guard usage == 0x64 || usage == 0x65 || usage == 0x66 else { continue }

                let valuePointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
                defer { valuePointer.deallocate() }
                guard IOHIDDeviceGetValue(device, element, valuePointer) == kIOReturnSuccess else {
                    continue
                }
                let value = valuePointer.pointee.takeUnretainedValue()
                let raw = IOHIDValueGetIntegerValue(value)
                let minimum = IOHIDElementGetLogicalMin(element)
                let maximum = IOHIDElementGetLogicalMax(element)
                guard maximum > minimum else { continue }

                let percent = Int(((Double(raw - minimum) / Double(maximum - minimum)) * 100).rounded())
                guard (0...100).contains(percent) else { continue }
                percentages.append(percent)
                if percentages.count == 2 { break }
            }
            if percentages.count == 2 { break }
        }

        guard !percentages.isEmpty else { return nil }
        return percentages.enumerated().map { index, percent in
            WirelessMicTransmitterBattery(
                label: percentages.count == 1 ? "TX" : "TX\(index + 1)",
                amount: .percent(percent),
                charging: false
            )
        }
    }
}
