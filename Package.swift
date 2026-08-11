// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CopytoolCore",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CopytoolCore",
            path: "copytool",
            exclude: [
                "AppDelegate.swift",
                "Assets.xcassets",
                "ClipboardManager.swift",
                "ContentView.swift",
                "PreviewWindowManager.swift",
                "SettingsView.swift",
                "copytoolApp.swift"
            ],
            sources: [
                "HistoryCrypto.swift",
                "HistoryItem.swift",
                "HistoryStore.swift",
                "SettingsManager.swift"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CopytoolCoreTests",
            dependencies: ["CopytoolCore"],
            path: "copytoolTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
