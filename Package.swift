// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sysbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Sysbar", targets: ["Sysbar"]),
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
        .testTarget(name: "SysbarCoreTests", dependencies: ["SysbarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
