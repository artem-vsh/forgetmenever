// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ForgetMeNever",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ForgetMeNever", targets: ["ForgetMeNeverApp"])
    ],
    targets: [
        .executableTarget(
            name: "ForgetMeNeverApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
