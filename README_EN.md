# MicPilot

[简体中文](README.md) | [English](README_EN.md)

<img src="Resources/AppIconMaster.png" width="120" alt="MicPilot app icon" align="right" />

A lightweight native macOS menu bar app for switching the system's default audio input device. MicPilot keeps the current microphone visible at a glance and can show transmitter battery status for compatible Hollyland and DJI wireless microphones.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange.svg)](#)

## Features

- **Always visible:** Shows a microphone icon and the current input device abbreviation in the menu bar.
- **One-click switching:** Lists all available input devices and changes the system default without opening System Settings.
- **Transmitter battery status:** Displays a battery icon and charge level for compatible wireless microphones, refreshed every 10 seconds.
- **Dual-transmitter support:** Shows `TX1` and `TX2` separately when both transmitters are available.
- **Clear fallback states:** Reports disconnected or unreadable devices instead of displaying a made-up `0%` value.
- **Native and lightweight:** Built with AppKit, with no main window, no Dock icon, and no third-party dependencies.

## Wireless microphone support

### Hollyland

MicPilot detects LARK and MELO series HID receivers using vendor ID `0x3547`. Recognized families include LARK MIX, LARK M2, LARK M2S, LARK A1, LARK A2, LARK MAX, LARK MAX 2, LARK C1, LARK M1, LARK 150, and MELO P1.

It first attempts the LARK status-query protocol for an exact battery percentage, then falls back to the standard HID Battery System. The currently verified device is the LARK MIX Type-C receiver with product ID `0x0007`.

### DJI

DJI Mic Mini and Mic Mini 2 battery data is read from the receiver's v2 status stream using vendor ID `0x2CA3`, product ID `0x4011`, interface 6, and Bulk IN endpoint `0x86`. MicPilot can display separate TX1 and TX2 battery levels and charging states.

DJI Mic, Mic 2, Mic 3, and other DJI audio devices are recognized and checked for standard HID battery information. If a device does not expose a readable interface, MicPilot reports the battery as unavailable rather than inventing a percentage.

Battery support is best effort because these manufacturers do not provide a stable public macOS battery API for every model and firmware version.

## Safe read-only behavior

MicPilot only reads receiver status. For DJI devices, it listens to receiver status updates and does not send configuration commands. For Hollyland devices, it sends identity and status queries only. It does not modify gain, noise reduction, pairing, or firmware.

## Download

Download the latest ready-to-run build from [GitHub Releases](https://github.com/kevinxm615-netizen/MicPilot/releases/latest).

The downloadable app is ad-hoc signed but not Apple-notarized. On first launch, you may need to right-click `MicPilot.app` in Finder and choose **Open**.

## Requirements

- macOS 12.0 or later
- Xcode Command Line Tools with Swift 5.10 or later, when building from source

## Build from source

```sh
git clone https://github.com/kevinxm615-netizen/MicPilot.git
cd MicPilot
./scripts/build-app.sh
```

The build script creates `MicPilot.app` in the parent directory of the repository. Move the app into `/Applications` to install it.

## Usage

1. Click the microphone icon in the menu bar.
2. Select an input device to make it the system default.
3. Compatible wireless microphones show transmitter battery information next to the device name.

The menu also includes shortcuts for Sound Settings, refresh, launch at login, and quit.

## Project structure

| Component | Responsibility |
| --- | --- |
| `AppDelegate` | Status item, menu construction, device switching, and battery refresh scheduling |
| `CoreAudioDevices` | Input-device discovery and system default input switching |
| `WirelessMicBattery` | Wireless microphone detection and battery-state models |
| `LarkMixBatteryProvider` | Hollyland LARK status-query protocol and HID fallback |
| `DJIMicBatteryProvider` | DJI Mic Mini v2 status-stream parsing |
| `StandardHIDBatteryProvider` | Standard HID Battery System reader |
| `StatusBarIcon` | Template microphone icon for the macOS menu bar |

## License

MicPilot is available under the [MIT License](LICENSE).

## Acknowledgements

DJI Mic Mini protocol parsing is based on the [PROTOCOL.md](https://github.com/ShadowBitBasher/DJI-Mic-Control/blob/main/PROTOCOL.md) documentation from [DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control), which is released under the Unlicense.
