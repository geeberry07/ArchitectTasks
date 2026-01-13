// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ArchitectTasks",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Libraries
        .library(name: "ArchitectCore", targets: ["ArchitectCore"]),
        .library(name: "ArchitectAnalysis", targets: ["ArchitectAnalysis"]),
        .library(name: "ArchitectPlanner", targets: ["ArchitectPlanner"]),
        .library(name: "ArchitectExecutor", targets: ["ArchitectExecutor"]),
        .library(name: "ArchitectHost", targets: ["ArchitectHost"]),
        
        // Full package
        .library(name: "ArchitectTasks", targets: [
            "ArchitectCore",
            "ArchitectAnalysis",
            "ArchitectPlanner",
            "ArchitectExecutor",
            "ArchitectHost"
        ]),
        
        // CLI executable
        .executable(name: "architect-cli", targets: ["architect-cli"]),
        
        // Menu Bar App (macOS only)
        .executable(name: "ArchitectMenuBar", targets: ["ArchitectMenuBar"]),
        
        // Language Server
        .executable(name: "architect-lsp", targets: ["ArchitectLSP"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "509.0.0"),
    ],
    targets: [
        // Core models and protocols (no dependencies)
        .target(name: "ArchitectCore"),
        
        // Analysis (SwiftSyntax-based)
        .target(
            name: "ArchitectAnalysis",
            dependencies: [
                "ArchitectCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        
        // Planner (Agent A)
        .target(
            name: "ArchitectPlanner",
            dependencies: ["ArchitectCore", "ArchitectAnalysis"]
        ),
        
        // Executor (Agent B) - now with SwiftSyntax transforms
        .target(
            name: "ArchitectExecutor",
            dependencies: [
                "ArchitectCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        
        // Host contract and reference implementation
        .target(
            name: "ArchitectHost",
            dependencies: [
                "ArchitectCore",
                "ArchitectAnalysis",
                "ArchitectPlanner",
                "ArchitectExecutor"
            ]
        ),
        
        // CLI executable
        .executableTarget(
            name: "architect-cli",
            dependencies: ["ArchitectHost"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        
        // Menu Bar App (macOS only)
        .executableTarget(
            name: "ArchitectMenuBar",
            dependencies: ["ArchitectHost"],
            path: "Sources/ArchitectMenuBar"
        ),
        
        // Language Server Protocol
        .executableTarget(
            name: "ArchitectLSP",
            dependencies: ["ArchitectHost"],
            path: "Sources/ArchitectLSP"
        ),
        
        // Tests
        .testTarget(
            name: "ArchitectCoreTests",
            dependencies: ["ArchitectCore"]
        ),
        .testTarget(
            name: "ArchitectAnalysisTests",
            dependencies: ["ArchitectAnalysis"]
        ),
        .testTarget(
            name: "ArchitectPlannerTests",
            dependencies: ["ArchitectPlanner", "ArchitectAnalysis"]
        ),
        .testTarget(
            name: "ArchitectExecutorTests",
            dependencies: ["ArchitectExecutor", "ArchitectCore"]
        ),
        .testTarget(
            name: "ArchitectHostTests",
            dependencies: ["ArchitectHost"]
        ),
    ]
)
