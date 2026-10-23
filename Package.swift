// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sysbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sysbar", targets: ["Sysbar"]),
        .executable(name: "SysbarFanHelper", targets: ["SysbarFanHelper"]),
    ],
    targets: [
        // Thin C shim: private IOReport declarations + AppleSMC reader.
        .target(
            name: "CSystemBridge",
            linkerSettings: [
                .linkedLibrary("IOReport"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        // Samplers, history and formatting. No UI, fully testable.
        .target(name: "SysbarCore", dependencies: ["CSystemBridge"]),
        .executableTarget(name: "Sysbar", dependencies: ["SysbarCore"]),
        // Root launch daemon that writes fan speeds to the SMC on the app's behalf.
        .executableTarget(name: "SysbarFanHelper", dependencies: ["SysbarCore", "CSystemBridge"]),
        .testTarget(name: "SysbarCoreTests", dependencies: ["SysbarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
