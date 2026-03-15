// swift-tools-version: 5.6

import PackageDescription

let package = Package(
    name: "SwiftXMLCoder",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "SwiftXMLCoder", targets: ["SwiftXMLCoder"]),
        .library(name: "SwiftXMLCoderTestSupport", targets: ["SwiftXMLCoderTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        .systemLibrary(
            name: "CLibXML2",
            pkgConfig: "libxml-2.0",
            providers: [
                .brew(["libxml2"]),
                .apt(["libxml2-dev"])
            ]
        ),
        .target(
            name: "SwiftXMLCoderCShim",
            dependencies: ["CLibXML2"],
            publicHeadersPath: "include"
        ),
        .target(
            name: "XMLCoderCompatibility",
            dependencies: ["CLibXML2"]
        ),
        .target(
            name: "SwiftXMLCoder",
            dependencies: [
                "XMLCoderCompatibility",
                "SwiftXMLCoderCShim",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "SwiftXMLCoderTestSupport",
            dependencies: ["SwiftXMLCoder"]
        ),
        .testTarget(
            name: "SwiftXMLCoderTests",
            dependencies: [
                "SwiftXMLCoder",
                "SwiftXMLCoderTestSupport"
            ]
        )
    ]
)