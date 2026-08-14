import Foundation
import IOKit
import IOUSBHost

final class DJIMicBatteryProvider {
    static let vendorID = 0x2CA3
    static let micMiniProductID = 0x4011

    private let ioQueue = DispatchQueue(label: "AudioInputSwitcher.dji-usb")

    func sample() -> WirelessMicBatteryStatus {
        guard let service = Self.findMicMiniInterface() else {
            return .receiverDisconnected
        }
        defer { IOObjectRelease(service) }

        do {
            let hostInterface = try IOUSBHostInterface(
                __ioService: service,
                options: [],
                queue: ioQueue,
                interestHandler: nil
            )
            defer { hostInterface.destroy() }

            let pipe = try hostInterface.copyPipe(withAddress: 0x86)
            var stream: [UInt8] = []
            var sawV1Heartbeat = false
            var sawConnectedTransmitter = false

            for _ in 0..<6 {
                guard let chunk = readChunk(from: pipe) else { continue }
                stream.append(contentsOf: chunk)
                for frame in Self.takeFrames(from: &stream) {
                    if Self.isV1Heartbeat(frame) {
                        sawV1Heartbeat = true
                    }
                    guard let parsed = Self.parseV2Status(frame) else { continue }
                    sawConnectedTransmitter = parsed.connected
                    if !parsed.batteries.isEmpty {
                        return .available(model: "DJI Mic Mini / Mini 2", transmitters: parsed.batteries)
                    }
                }
            }

            if sawConnectedTransmitter {
                return .unavailable(reason: "DJI 发射器已连接，但本次状态推送尚未包含电量")
            }
            if sawV1Heartbeat {
                return .unavailable(reason: "DJI 接收器仍使用 v1 固件；升级固件后才能读取发射器电量")
            }
            return .transmitterDisconnected(model: "DJI Mic Mini / Mini 2")
        } catch {
            return .unavailable(reason: "无法打开 DJI 接收器状态接口：\(error.localizedDescription)")
        }
    }

    static func parseV2Status(_ frame: [UInt8]) -> (connected: Bool, batteries: [WirelessMicTransmitterBattery])? {
        let headerLength = 52
        let slotLength = 32
        guard frame.count >= headerLength + 2,
              frame[0] == 0x55,
              frame[2] == 0x04,
              frame[9] == 0x5B,
              frame[10] == 0x03,
              frame[11] == 0x03 else { return nil }

        let slotBytes = frame.count - headerLength - 2
        guard slotBytes >= 0, slotBytes % slotLength == 0 else { return nil }
        let slotCount = min(slotBytes / slotLength, 2)
        let connectedMask = frame[44]
        var batteries: [WirelessMicTransmitterBattery] = []

        for slotPosition in 0..<slotCount {
            let offset = headerLength + slotPosition * slotLength
            guard frame[offset] == 0x02 else { continue }
            let unit = Int(frame[offset + 1])
            guard (1...2).contains(unit), connectedMask & (1 << (unit - 1)) != 0 else { continue }

            let flags = frame[offset + 7]
            let gauge = Int((flags >> 2) & 0x07)
            guard (1...7).contains(gauge) else { continue }
            batteries.append(
                WirelessMicTransmitterBattery(
                    label: "TX\(unit)",
                    amount: .djiGauge(gauge),
                    charging: flags & 0x02 != 0
                )
            )
        }

        batteries.sort { $0.label < $1.label }
        return (connectedMask != 0, batteries)
    }

    static func takeFrames(from stream: inout [UInt8]) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        while stream.count >= 4 {
            guard let marker = stream.indices.first(where: {
                stream[$0] == 0x55 && $0 + 2 < stream.count && stream[$0 + 2] == 0x04
            }) else {
                stream.removeAll(keepingCapacity: true)
                break
            }
            if marker > 0 {
                stream.removeFirst(marker)
            }

            let length = Int(stream[1])
            guard (14...178).contains(length) else {
                stream.removeFirst()
                continue
            }
            guard stream.count >= length else { break }
            frames.append(Array(stream.prefix(length)))
            stream.removeFirst(length)
        }
        return frames
    }

    private static func isV1Heartbeat(_ frame: [UInt8]) -> Bool {
        frame.count >= 12 && frame[9] == 0x5B && frame[10] == 0x03 && frame[11] == 0x00
    }

    private func readChunk(from pipe: IOUSBHostPipe) -> [UInt8]? {
        guard let data = NSMutableData(length: 512) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var completionStatus = kIOReturnError
        var bytesTransferred = 0

        do {
            try pipe.enqueueIORequest(
                with: data,
                completionTimeout: 0.25,
                completionHandler: { status, count in
                    completionStatus = status
                    bytesTransferred = count
                    semaphore.signal()
                }
            )
        } catch {
            return nil
        }

        guard semaphore.wait(timeout: .now() + 0.4) == .success,
              completionStatus == kIOReturnSuccess,
              bytesTransferred > 0 else { return nil }
        return Array(Data(bytes: data.bytes, count: bytesTransferred))
    }

    private static func findMicMiniInterface() -> io_service_t? {
        guard let matching = IOServiceMatching("IOUSBHostInterface") as NSMutableDictionary? else {
            return nil
        }
        matching["idVendor"] = NSNumber(value: vendorID)
        matching["idProduct"] = NSNumber(value: micMiniProductID)
        matching["bInterfaceNumber"] = NSNumber(value: 6)
        return IOServiceGetMatchingService(kIOMainPortDefault, matching)
    }
}
