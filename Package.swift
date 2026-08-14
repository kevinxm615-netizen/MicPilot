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
        .target(
            name: "DJIUSBTransport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "AudioInputSwitcher",
            dependencies: ["DJIUSBTransport"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
