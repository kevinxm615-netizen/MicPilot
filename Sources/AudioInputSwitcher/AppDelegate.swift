import AppKit
import CoreAudio
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let menu = NSMenu(title: "MicPilot")
    private let batteryProvider = WirelessMicBatteryProvider()
    private let batteryQueue = DispatchQueue(label: "AudioInputSwitcher.wireless-mic-battery", qos: .utility)

    private var statusItem: NSStatusItem?
    private var devices: [(id: AudioDeviceID, name: String)] = []
    private var batteryStatuses: [WirelessMicBrand: WirelessMicBatteryStatus] = [
        .hollyland: .unavailable(reason: "正在读取猛犸麦克风电量"),
        .dji: .unavailable(reason: "正在读取大疆麦克风电量")
    ]
    private var wirelessMicrophoneMenuItems: [(item: NSMenuItem, name: String, brand: WirelessMicBrand)] = []
    private var batteryTimer: Timer?
    private var batteryRefreshInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = StatusBarIcon.make()
            button.imagePosition = .imageLeading
            button.title = "--"
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.toolTip = "MicPilot · 麦克风切换"
            button.setAccessibilityLabel("MicPilot 麦克风切换")
        }
        item.menu = menu
        statusItem = item

        menu.delegate = self
        refreshDevices()
        refreshBattery()
        CoreAudioDevices.addChangeListeners(queue: .main) { [weak self] in
            self?.refreshDevices()
        }

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshBattery()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        batteryTimer?.invalidate()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshDevices()
        refreshBattery()
    }

    private func refreshDevices() {
        devices = CoreAudioDevices.inputDevices()
        updateStatusItem()
        rebuildMenu()
    }

    private func updateStatusItem() {
        let defaultDeviceID = CoreAudioDevices.defaultInputDeviceID()
        let currentDeviceName = devices.first { $0.id == defaultDeviceID }?.name
        let abbreviation = DeviceAbbreviation.make(from: currentDeviceName)

        guard let button = statusItem?.button else { return }
        button.title = abbreviation
        button.toolTip = currentDeviceName.map { "当前麦克风：\($0)" } ?? "未检测到当前麦克风"
        button.setAccessibilityLabel("当前麦克风：\(currentDeviceName ?? "未知")")
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        wirelessMicrophoneMenuItems.removeAll(keepingCapacity: true)

        let header = NSMenuItem(title: "音频输入设备（\(devices.count)）", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let defaultDeviceID = CoreAudioDevices.defaultInputDeviceID()
        if devices.isEmpty {
            let emptyItem = NSMenuItem(title: "无可用输入设备", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for device in devices {
                let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = NSNumber(value: device.id)
                item.state = device.id == defaultDeviceID ? .on : .off
                if let brand = WirelessMicBrand.detect(fromAudioDeviceName: device.name) {
                    wirelessMicrophoneMenuItems.append((item, device.name, brand))
                    updateWirelessMicrophoneItem(
                        item,
                        deviceName: device.name,
                        brand: brand,
                        status: batteryStatuses[brand] ?? .receiverDisconnected
                    )
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "声音设置…", action: #selector(openSoundSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(refreshDevicesFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let launchItem = NSMenuItem(title: "开机自启", action: #selector(toggleAutoLaunch(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = autoLaunchEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func refreshBattery() {
        guard !batteryRefreshInFlight else { return }
        batteryRefreshInFlight = true

        batteryQueue.async { [weak self] in
            guard let self else { return }
            let statuses = self.batteryProvider.sample()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.batteryRefreshInFlight = false
                self.batteryStatuses = statuses
                self.updateBatteryMenuItems()
            }
        }
    }

    private func updateBatteryMenuItems() {
        for entry in wirelessMicrophoneMenuItems {
            updateWirelessMicrophoneItem(
                entry.item,
                deviceName: entry.name,
                brand: entry.brand,
                status: batteryStatuses[entry.brand] ?? .receiverDisconnected
            )
        }
    }

    private func updateWirelessMicrophoneItem(
        _ item: NSMenuItem,
        deviceName: String,
        brand: WirelessMicBrand,
        status: WirelessMicBatteryStatus
    ) {
        let title = NSMutableAttributedString(string: deviceName)
        title.append(NSAttributedString(string: "  "))
        var toolTip = status.toolTip

        switch status {
        case .available(_, let transmitters):
            for (index, transmitter) in transmitters.enumerated() {
                if index > 0 {
                    title.append(NSAttributedString(string: "   "))
                }
                if transmitters.count > 1 {
                    title.append(NSAttributedString(string: "\(transmitter.label) "))
                }
                appendBatteryIcon(
                    transmitter.amount.symbolName,
                    accessibilityDescription: "\(brand.displayName) \(transmitter.label) 电量",
                    to: title
                )
                title.append(NSAttributedString(string: transmitter.amount.displayText))
            }
        case .transmitterDisconnected:
            appendBatteryIcon("battery.0percent", accessibilityDescription: "发射器未连接", to: title)
            title.append(NSAttributedString(string: "未连接"))
        case .receiverDisconnected:
            title.append(NSAttributedString(string: "暂不可读"))
            toolTip = "已识别为\(brand.displayName)无线麦克风，但该接收器未暴露可读取的电量接口"
        case .unavailable:
            title.append(NSAttributedString(string: "暂不可读"))
        }

        item.attributedTitle = title
        item.toolTip = toolTip
    }

    private func appendBatteryIcon(
        _ symbolName: String,
        accessibilityDescription: String,
        to title: NSMutableAttributedString
    ) {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(symbolConfiguration) else { return }

        image.isTemplate = true
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -1, width: 19, height: 11)
        title.append(NSAttributedString(attachment: attachment))
        title.append(NSAttributedString(string: " "))
    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        if !CoreAudioDevices.setDefaultInputDevice(number.uint32Value) {
            NSSound.beep()
        }
        refreshDevices()
    }

    @objc private func openSoundSettings() {
        let workspace = NSWorkspace.shared
        if let modernURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input"),
           workspace.open(modernURL) {
            return
        }
        if let legacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.sound?input") {
            workspace.open(legacyURL)
        }
    }

    @objc private func refreshDevicesFromMenu() {
        refreshDevices()
        refreshBattery()
    }

    @objc private func toggleAutoLaunch(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else {
            NSSound.beep()
            return
        }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        sender.state = autoLaunchEnabled ? .on : .off
    }

    private var autoLaunchEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
