import Foundation
import IOKit.hid

enum LarkMixBatteryStatus: Equatable {
    case available(percent: Int)
    case transmitterDisconnected
    case receiverDisconnected
    case unavailable

    var menuTitle: String {
        switch self {
        case .available(let percent):
            return "LARK MIX 发射器电量：\(percent)%"
        case .transmitterDisconnected:
            return "LARK MIX 发射器：未连接"
        case .receiverDisconnected:
            return "LARK MIX 接收器：未连接"
        case .unavailable:
            return "LARK MIX 电量：暂不可用"
        }
    }

    var toolTip: String {
        switch self {
        case .available:
            return "发射器已连接，点击刷新电量"
        case .transmitterDisconnected:
            return "接收器已连接，请检查发射器是否开机并完成配对"
        case .receiverDisconnected:
            return "未检测到 LARK MIX Type-C 接收器"
        case .unavailable:
            return "接收器未返回有效电量状态，点击重试"
        }
    }

    var symbolName: String {
        switch self {
        case .available(let percent):
            if percent >= 88 { return "battery.100percent" }
            if percent >= 63 { return "battery.75percent" }
            if percent >= 38 { return "battery.50percent" }
            if percent >= 13 { return "battery.25percent" }
            return "battery.0percent"
        case .transmitterDisconnected, .receiverDisconnected:
            return "battery.0percent"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }
}

private final class LarkMixReportCapture {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var status: LarkMixBatteryStatus?

    init() {
        buffer.initialize(repeating: 0, count: 64)
    }

    deinit {
        buffer.deallocate()
    }
}

private let larkMixInputReportCallback: IOHIDReportCallback = { context, result, _, _, reportID, report, length in
    guard result == kIOReturnSuccess, reportID == 0x55, let context else { return }
    let capture = Unmanaged<LarkMixReportCapture>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    capture.status = LarkMixBatteryProvider.parseStatusReport(bytes)
}

final class LarkMixBatteryProvider {
    static let vendorID = 13_639 // 0x3547, Shenzhen Hollyland Technology

    func sample() -> LarkMixBatteryStatus {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID
        ]
        guard let runLoop = CFRunLoopGetCurrent() else { return .unavailable }

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            return .unavailable
        }
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return .receiverDisconnected
        }
        let candidates = devices.filter(Self.isLarkMicrophone)
        guard !candidates.isEmpty else { return .receiverDisconnected }

        var fallbackStatus: LarkMixBatteryStatus?
        for device in candidates {
            guard let status = sample(device: device, runLoop: runLoop) else { continue }
            if case .available = status {
                return status
            }
            fallbackStatus = status
        }
        return fallbackStatus ?? .unavailable
    }

    private func sample(device: IOHIDDevice, runLoop: CFRunLoop) -> LarkMixBatteryStatus? {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return nil
        }

        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        let capture = LarkMixReportCapture()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            capture.buffer,
            64,
            larkMixInputReportCallback,
            Unmanaged.passUnretained(capture).toOpaque()
        )

        guard send(Self.makeQuery(command: 0x15, target: 0x40), to: device),
              send(Self.makeQuery(command: 0x10, target: 0x40), to: device) else {
            return nil
        }

        let deadline = Date().addingTimeInterval(0.3)
        repeat {
            CFRunLoopRunInMode(.defaultMode, 0.05, true)
        } while capture.status == nil && Date() < deadline

        return capture.status
    }

    private static func isLarkMicrophone(_ device: IOHIDDevice) -> Bool {
        guard let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String else {
            return false
        }
        let name = product.lowercased()
        return name.contains("lark") || name.contains("melo") || name.contains("wireless microphone") || name.contains("wireless mic")
    }

    static func makeQuery(command: UInt8, target: UInt8) -> [UInt8] {
        let checksum = 0xAA ^ 0xDD ^ command ^ target
        return [0x55, 0xAA, 0xDD, command, target, 0x00, 0x00, checksum]
    }

    static func parseStatusReport(_ report: [UInt8]) -> LarkMixBatteryStatus? {
        guard report.count >= 10 else { return nil }
        let packetStart = report[0] == 0x55 ? 1 : 0
        guard report.count >= packetStart + 9,
              report[packetStart] == 0xBB,
              report[packetStart + 1] == 0xDD,
              report[packetStart + 2] == 0x10 else { return nil }

        let payloadLength = Int(report[packetStart + 4]) << 8 | Int(report[packetStart + 5])
        let payloadStart = packetStart + 6
        guard payloadLength >= 3, report.count >= payloadStart + payloadLength else { return nil }
        guard report[payloadStart] == 1 else { return .transmitterDisconnected }

        let percent = Int(report[payloadStart + 2])
        guard (0...100).contains(percent) else { return .unavailable }
        return .available(percent: percent)
    }

    private func send(_ bytes: [UInt8], to device: IOHIDDevice) -> Bool {
        var report = [UInt8](repeating: 0, count: 64)
        report.replaceSubrange(0..<bytes.count, with: bytes)
        let result = report.withUnsafeMutableBytes { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0x55,
                buffer.bindMemory(to: UInt8.self).baseAddress!,
                buffer.count
            )
        }
        return result == kIOReturnSuccess
    }
}
