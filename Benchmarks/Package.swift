// swift-tools-version: 5.9
// Benchmarks are in a separate package because package-benchmark requires macOS 13.0+
// while the main SwiftXMLCoder library supports macOS 10.15+.
//
// Usage:
//   cd Benchmarks
//   swift package --disable-sandbox benchmark

import PackageDescription

let package = Package(
    name: "SwiftXMLCoderBenchmarks",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../"),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.4.0")
    ],
    targets: [
        .executableTarget(
            name: "SwiftXMLCoderBenchmarks",
            dependencies: [
                .product(name: "SwiftXMLCoder", package: "swift-xml-coder"),
                .product(name: "Benchmark", package: "package-benchmark")
            ],
            path: "SwiftXMLCoderBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)
