// swift-tools-version: 5.9
// Fuzz targets for SwiftXMLCoder — for type-checking only.
//
// The run_fuzzer.sh script builds the actual fuzz binaries using
// `swiftc -parse-as-library -sanitize=fuzzer,address`.
//
// Usage:
//   swift build                — type-check harnesses (CI lint/compile gate)
//   ./run_fuzzer.sh            — build + run all targets with libFuzzer
//   ./run_fuzzer.sh FuzzXMLParser  — run a single target
import PackageDescription

let package = Package(
    name: "SwiftXMLCoderFuzz",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(path: "../")
    ],
    targets: [
        // Each harness is a separate library target so both can define
        // @_cdecl("LLVMFuzzerTestOneInput") without symbol conflict.
        // run_fuzzer.sh compiles each independently as its own binary.
        .target(
            name: "FuzzXMLParser",
            dependencies: [
                .product(name: "SwiftXMLCoder", package: "swift-xml-coder")
            ],
            path: "Sources/FuzzXMLParser"
        ),
        .target(
            name: "FuzzXMLDecoder",
            dependencies: [
                .product(name: "SwiftXMLCoder", package: "swift-xml-coder")
            ],
            path: "Sources/FuzzXMLDecoder"
        )
    ]
)
