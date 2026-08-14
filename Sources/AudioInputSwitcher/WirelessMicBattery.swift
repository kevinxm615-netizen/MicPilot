import Foundation

enum WirelessMicBrand: CaseIterable, Hashable {
    case hollyland
    case dji

    static func detect(fromAudioDeviceName name: String) -> WirelessMicBrand? {
        let normalized = name.lowercased()
        if normalized.contains("dji") || normalized.contains("wireless mic rx") {
            return .dji
        }
        if normalized.contains("hollyland") || normalized.contains("lark") || normalized.contains("melo") || normalized == "wireless microphone" {
            return .hollyland
        }
        return nil
    }

    var displayName: String {
        switch self {
        case .hollyland: return "猛犸"
        case .dji: return "大疆"
        }
    }
}

enum WirelessMicBatteryAmount: Equatable {
    case percent(Int)
    case djiGauge(Int)

    var displayText: String {
        switch self {
        case .percent(let percent):
            return "\(percent)%"
        case .djiGauge(let gauge):
            switch gauge {
            case 1: return "满电"
            case 2...4: return "良好"
            case 5: return "低"
            case 6: return "极低"
            case 7: return "危急"
            default: return "--"
            }
        }
    }

    var symbolName: String {
        switch self {
        case .percent(let percent):
            if percent >= 88 { return "battery.100percent" }
            if percent >= 63 { return "battery.75percent" }
            if percent >= 38 { return "battery.50percent" }
            if percent >= 13 { return "battery.25percent" }
            return "battery.0percent"
        case .djiGauge(let gauge):
            switch gauge {
            case 1: return "battery.100percent"
            case 2: return "battery.75percent"
            case 3...4: return "battery.50percent"
            case 5: return "battery.25percent"
            default: return "battery.0percent"
            }
        }
    }
}

struct WirelessMicTransmitterBattery: Equatable {
    let label: String
    let amount: WirelessMicBatteryAmount
    let charging: Bool
}

enum WirelessMicBatteryStatus: Equatable {
    case available(model: String, transmitters: [WirelessMicTransmitterBattery])
    case transmitterDisconnected(model: String)
    case receiverDisconnected
    case unavailable(reason: String)

    var toolTip: String {
        switch self {
        case .available(let model, let transmitters):
            let detail = transmitters.map {
                "\($0.label) \($0.amount.displayText)\($0.charging ? "（充电中）" : "")"
            }.joined(separator: "，")
            return "\(model)：\(detail)"
        case .transmitterDisconnected(let model):
            return "\(model) 接收器已连接，请检查发射器是否开机并完成配对"
        case .receiverDisconnected:
            return "未检测到对应的无线麦克风接收器"
        case .unavailable(let reason):
            return reason
        }
    }
}

final class WirelessMicBatteryProvider {
    private let hollylandProvider = LarkMixBatteryProvider()
    private let djiProvider = DJIMicBatteryProvider()
    private let standardHIDProvider = StandardHIDBatteryProvider()

    func sample() -> [WirelessMicBrand: WirelessMicBatteryStatus] {
        let hollylandStatus = hollylandProvider.sample().wirelessMicStatus
        let djiStatus = djiProvider.sample()
        return [
            .hollyland: standardFallback(
                for: hollylandStatus,
                brand: .hollyland,
                vendorID: LarkMixBatteryProvider.vendorID
            ),
            .dji: standardFallback(
                for: djiStatus,
                brand: .dji,
                vendorID: DJIMicBatteryProvider.vendorID
            )
        ]
    }

    private func standardFallback(
        for status: WirelessMicBatteryStatus,
        brand: WirelessMicBrand,
        vendorID: Int
    ) -> WirelessMicBatteryStatus {
        if case .available = status { return status }
        guard let batteries = standardHIDProvider.sample(vendorID: vendorID) else { return status }
        return .available(model: "\(brand.displayName)无线麦克风", transmitters: batteries)
    }
}

extension LarkMixBatteryStatus {
    var wirelessMicStatus: WirelessMicBatteryStatus {
        switch self {
        case .available(let percent):
            return .available(
                model: "Hollyland LARK",
                transmitters: [
                    WirelessMicTransmitterBattery(
                        label: "TX",
                        amount: .percent(percent),
                        charging: false
                    )
                ]
            )
        case .transmitterDisconnected:
            return .transmitterDisconnected(model: "Hollyland LARK")
        case .receiverDisconnected:
            return .receiverDisconnected
        case .unavailable:
            return .unavailable(reason: "猛犸接收器未返回有效电量状态")
        }
    }
}
