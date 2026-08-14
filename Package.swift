// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AudioInputSwitcher",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "AudioInputSwitcher", targets: ["AudioInputSwitcher"])
    ],
    targets: [
        .executableTarget(
            name: "AudioInputSwitcher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOUSBHost"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
