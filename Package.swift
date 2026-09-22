// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MDMCopilot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MDMCopilot", targets: ["MDMCopilot"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm.git",
            exact: "3.31.4"
        ),
        .package(
            url: "https://github.com/huggingface/swift-huggingface.git",
            exact: "0.9.0"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers.git",
            exact: "1.3.3"
        )
    ],
    targets: [
        .executableTarget(
            name: "MDMCopilot",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "Sources/MDMCopilot",
            exclude: ["App/Info.plist"],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MDMCopilotTests",
            dependencies: ["MDMCopilot"],
            path: "Tests/MDMCopilotTests"
        )
    ]
)
