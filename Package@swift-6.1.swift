// swift-tools-version: 6.1

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftXMLCoder",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "SwiftXMLCoder", targets: ["SwiftXMLCoder"]),
        .library(name: "SwiftXMLCoderMacros", targets: ["SwiftXMLCoderMacros"]),
        .library(name: "SwiftXMLCoderTestSupport", targets: ["SwiftXMLCoderTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
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
            name: "SwiftXMLCoderOwnership6",
            dependencies: [
                "XMLCoderCompatibility",
                "SwiftXMLCoderCShim"
            ]
        ),
        .target(
            name: "SwiftXMLCoder",
            dependencies: [
                "XMLCoderCompatibility",
                "SwiftXMLCoderCShim",
                "SwiftXMLCoderOwnership6",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .macro(
            name: "SwiftXMLCoderMacroImplementation",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ]
        ),
        .target(
            name: "SwiftXMLCoderMacros",
            dependencies: [
                "SwiftXMLCoder",
                "SwiftXMLCoderMacroImplementation"
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
                "SwiftXMLCoderTestSupport",
                "SwiftXMLCoderMacros"
            ]
        ),
        .testTarget(
            name: "SwiftXMLCoderMacroTests",
            dependencies: [
                "SwiftXMLCoderMacroImplementation",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ],
    swiftLanguageModes: [
        .v6
    ]
)
