import AppKit
import Darwin

if CommandLine.arguments.contains("--self-test") {
    var failures: [String] = []

    let query = LarkMixBatteryProvider.makeQuery(command: 0x10, target: 0x40)
    if query != [0x55, 0xAA, 0xDD, 0x10, 0x40, 0x00, 0x00, 0x27] {
        failures.append("状态查询报文")
    }

    var connectedReport: [UInt8] = [
        0x55, 0xBB, 0xDD, 0x10, 0x80, 0x00, 0x09,
        0x01, 0x00, 0x3B, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00
    ]
    connectedReport.append(contentsOf: repeatElement(0, count: 64 - connectedReport.count))
    if LarkMixBatteryProvider.parseStatusReport(connectedReport) != .available(percent: 59) {
        failures.append("59% 电量响应")
    }

    var disconnectedReport = connectedReport
    disconnectedReport[7] = 0
    disconnectedReport[9] = 0
    if LarkMixBatteryProvider.parseStatusReport(disconnectedReport) != .transmitterDisconnected {
        failures.append("发射器断开响应")
    }

    let statusBarIcon = StatusBarIcon.make()
    if statusBarIcon.size != StatusBarIcon.size || !statusBarIcon.isTemplate || statusBarIcon.tiffRepresentation == nil {
        failures.append("菜单栏图标")
    }

    let abbreviationChecks = [
        DeviceAbbreviation.make(from: "Wireless microphone") == "WM",
        DeviceAbbreviation.make(from: "MacBook Pro麦克风") == "MBP",
        DeviceAbbreviation.make(from: "BlackHole 2ch") == "BH",
        DeviceAbbreviation.make(from: "“iPhone”的麦克风") == "iPhone"
    ]
    if abbreviationChecks.contains(false) {
        failures.append("设备简称")
    }

    let brandChecks = [
        WirelessMicBrand.detect(fromAudioDeviceName: "Wireless microphone") == .hollyland,
        WirelessMicBrand.detect(fromAudioDeviceName: "Hollyland LARK M2S") == .hollyland,
        WirelessMicBrand.detect(fromAudioDeviceName: "Wireless Mic Rx") == .dji,
        WirelessMicBrand.detect(fromAudioDeviceName: "DJI Mic 3") == .dji
    ]
    if brandChecks.contains(false) {
        failures.append("无线麦克风品牌识别")
    }

    var djiStatusFrame = [UInt8](repeating: 0, count: 118)
    djiStatusFrame[0] = 0x55
    djiStatusFrame[1] = 118
    djiStatusFrame[2] = 0x04
    djiStatusFrame[9] = 0x5B
    djiStatusFrame[10] = 0x03
    djiStatusFrame[11] = 0x03
    djiStatusFrame[44] = 0x03
    djiStatusFrame[52] = 0x02
    djiStatusFrame[53] = 0x01
    djiStatusFrame[57] = 0x1A
    djiStatusFrame[59] = 0x24 // TX1 gauge 1
    djiStatusFrame[84] = 0x02
    djiStatusFrame[85] = 0x02
    djiStatusFrame[89] = 0x1A
    djiStatusFrame[91] = 0x3A // TX2 gauge 6 + charging

    let djiStatus = DJIMicBatteryProvider.parseV2Status(djiStatusFrame)
    let expectedDJIBatteries = [
        WirelessMicTransmitterBattery(label: "TX1", amount: .djiGauge(1), charging: false),
        WirelessMicTransmitterBattery(label: "TX2", amount: .djiGauge(6), charging: true)
    ]
    if djiStatus?.connected != true || djiStatus?.batteries != expectedDJIBatteries {
        failures.append("DJI 双发射器电量响应")
    }

    var fragmentedStream = Array(djiStatusFrame.prefix(40))
    if !DJIMicBatteryProvider.takeFrames(from: &fragmentedStream).isEmpty {
        failures.append("DJI USB 分帧等待")
    }
    fragmentedStream.append(contentsOf: djiStatusFrame.dropFirst(40))
    if DJIMicBatteryProvider.takeFrames(from: &fragmentedStream).count != 1 {
        failures.append("DJI USB 完整分帧")
    }

    if failures.isEmpty {
        print("Self-test passed: 9 checks")
        exit(EXIT_SUCCESS)
    }

    fputs("Self-test failed: \(failures.joined(separator: ", "))\n", stderr)
    exit(EXIT_FAILURE)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
