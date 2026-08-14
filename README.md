# MicPilot

[简体中文](README.md) | [English](README_EN.md)

<img src="Resources/AppIconMaster.png" width="120" alt="MicPilot 图标" align="right" />

原生 macOS 菜单栏麦克风切换器，一键切换系统默认音频输入设备，并在菜单中实时显示兼容无线麦克风的发射器电量。

A native macOS menu bar app for switching the system default audio input device, with live transmitter battery readout for compatible wireless microphones.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2012%2B-lightgrey.svg)](#)
[![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange.svg)](#)

## 功能特性

- **菜单栏常驻**：菜单栏显示麦克风图标和当前输入设备简称，一眼看清正在使用哪个麦克风。
- **一键切换**：点击菜单栏即可查看全部输入设备并切换系统默认麦克风，无需打开系统设置。
- **发射器电量**：在兼容无线麦克风设备名后显示电池图标和电量，每 10 秒自动刷新。
- **多发射器**：双发射器设备分别显示 `TX1`、`TX2` 电量。
- **优雅降级**：接收器或发射器未连接、不可读时显示明确状态，绝不伪造百分比。
- **轻量原生**：`LSUIElement` 无 Dock 图标、无主窗口，纯 AppKit 实现，无第三方依赖。

## 支持的无线麦克风

### Hollyland 猛犸

识别厂商 VID `0x3547` 下的 LARK / MELO 系列 HID 接收器，包括 LARK MIX、LARK M2、LARK M2S、LARK A1、LARK A2、LARK MAX、LARK MAX 2、LARK C1、LARK M1、LARK 150、MELO P1 等。优先使用 LARK 状态查询协议读取精确百分比，并以标准 HID Battery System 作为兜底。当前硬件实测型号为 LARK MIX Type-C（PID `0x0007`）。

### DJI 大疆

DJI Mic Mini / Mic Mini 2 使用 VID `0x2CA3`、PID `0x4011`、接口 6、Bulk IN `0x86` 的 v2 状态推送读取 TX1/TX2 电量等级和充电状态。DJI Mic、Mic 2、Mic 3 及其他 DJI 音频设备会被识别，并尝试读取标准 HID Battery System；设备未公开可读接口时显示「暂不可读」，不会伪造百分比。

macOS 上支持 DJI Mic Mini 手机 USB-C 接收器。App 会从接收器设备内部查找未注册到全局 IORegistry 的状态接口，并在运行期间保持只读连接，以免系统配件服务抢占接口。

App 对 DJI 只读取接收器主动推送的状态，不发送设置命令；对 Hollyland 只发送身份/状态查询，不修改增益、降噪、配对或固件。

## 系统要求

- macOS 12.0 及以上
- Xcode Command Line Tools（Swift 5.10+）

## 构建

```sh
git clone https://github.com/kevinxm615-netizen/MicPilot.git
cd MicPilot
./scripts/build-app.sh
```

构建完成后，在仓库上一级目录生成 `MicPilot.app`，将其拖入「应用程序」即可使用。

## 使用

1. 点击菜单栏的麦克风图标，查看并切换当前输入设备。
2. 兼容的无线麦克风会自动在设备名后显示发射器电量。
3. 菜单底部提供「声音设置…」「刷新」「开机自启」「退出」。

## 实现结构

| 模块 | 职责 |
| --- | --- |
| `AppDelegate` | 菜单栏状态项、菜单构建、设备切换与电量刷新调度 |
| `CoreAudioDevices` | 枚举输入设备、读取/切换系统默认设备 |
| `WirelessMicBattery` | 无线麦克风品牌识别与电量状态建模 |
| `LarkMixBatteryProvider` | 猛犸 LARK 状态查询协议与 HID 兜底 |
| `DJIMicBatteryProvider` | 大疆 Mic Mini v2 状态推送解析 |
| `StandardHIDBatteryProvider` | 标准 HID Battery System 读取 |
| `StatusBarIcon` | 菜单栏单色麦克风矢量图标 |

## 许可证

本项目采用 [MIT 许可证](LICENSE)。

## 致谢

DJI Mic Mini 协议解析参考开源项目 [DJI-Mic-Control](https://github.com/ShadowBitBasher/DJI-Mic-Control) 的 [PROTOCOL.md](https://github.com/ShadowBitBasher/DJI-Mic-Control/blob/main/PROTOCOL.md)（Unlicense）。
