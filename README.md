# SwiftXMLCoder

[![CI](https://github.com/MFranceschi6/swift-xml-coder/actions/workflows/ci.yml/badge.svg)](https://github.com/MFranceschi6/swift-xml-coder/actions/workflows/ci.yml)
[![Lint](https://github.com/MFranceschi6/swift-xml-coder/actions/workflows/lint.yml/badge.svg)](https://github.com/MFranceschi6/swift-xml-coder/actions/workflows/lint.yml)
[![Swift 5.6+](https://img.shields.io/badge/Swift-5.6%2B-orange)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-lightgrey)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

A Codable-compatible XML encoder and decoder for Swift, backed by libxml2.

Encode and decode any `Codable` type to XML with control over element vs. attribute mapping, namespace declarations, date strategies, XPath queries, and deterministic canonicalization.

---

## Features

- **`XMLEncoder` / `XMLDecoder`** — Codable-compatible, zero-reflection encoding and decoding
- **Three-tier field mapping** — `@XMLAttribute` / `@XMLChild` property wrappers, `@XMLCodable` macros (Swift 5.9+), or runtime `XMLFieldCodingOverrides`
- **Streaming** — `XMLStreamParser` (push/SAX), `XMLStreamWriter`, `XMLEventCursor` (pull/cursor), `XMLItemDecoder` (item-by-item Codable decode)
- **XPath 1.0** — query parsed documents with namespace-aware expressions
- **Namespace support** — declare, resolve, and validate XML namespace prefixes; per-field namespace override via `XMLFieldNamespaceProvider` / `@XMLFieldNamespace`
- **Canonicalization** — deterministic XML output via `XMLCanonicalizer` (XML-DSig ready)
- **Parser security** — configurable depth, node-count, and text-size limits; network and DTD access disabled by default
- **Structured diagnostics** — `XMLParsingError.decodeFailed` with coding path and `XMLSourceLocation` for precise error reporting
- **Immutable tree model** — value-semantic `XMLTreeDocument` for transform pipelines; full fidelity for processing instructions, doctypes, and comments
- **Swift 5.6 – 6.1** — multi-manifest compatibility; macros on 5.9+; `~Copyable` ownership on 6.0+
- **macOS, iOS, tvOS, watchOS, Linux** — SPM-only, no Objective-C, no Foundation XML APIs

---

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/MFranceschi6/swift-xml-coder.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "SwiftXMLCoder", package: "swift-xml-coder"),
            // Optional: macro support (Swift 5.9+)
            .product(name: "SwiftXMLCoderMacros", package: "swift-xml-coder"),
        ]
    )
]
```

---

## Quick Start

### Encode

```swift
import SwiftXMLCoder

struct Book: Codable {
    var title: String
    var author: String
    var year: Int
}

let book = Book(title: "Swift in Practice", author: "Apple", year: 2024)
let data = try XMLEncoder().encode(book)
// <Book><title>Swift in Practice</title><author>Apple</author><year>2024</year></Book>
```

### Decode

```swift
let xml = Data("<Book><title>Swift in Practice</title><author>Apple</author><year>2024</year></Book>".utf8)
let book = try XMLDecoder().decode(Book.self, from: xml)
```

### Field Mapping with Macros (Swift 5.9+)

```swift
import SwiftXMLCoderMacros

@XMLCodable
struct Product: Codable {
    @XMLAttribute var id: String   // → attribute
    var name: String               // → element (default)
    var price: Double              // → element
}
// <Product id="SKU-1"><name>Widget</name><price>9.99</price></Product>
```

### XPath Query

```swift
let doc = try XMLDocument(data: xmlData)
let node = try doc.xpathFirstNode("/catalog/book[@lang='en']/title")
print(node?.content ?? "not found")
```

### Parser Security

```swift
let parser = XMLTreeParser(configuration: .init(
    limits: .untrustedInputDefault()   // caps depth, nodes, text size
))
let tree = try parser.parse(data: untrustedInput)
```

### Streaming — Pull Cursor

```swift
// Parse once, consume on demand
let cursor = try XMLEventCursor(data: xmlData)
while let event = cursor.next() {
    if case .startElement(let name, _, _) = event {
        print(name.localName)
    }
}
```

### Streaming — Item-by-Item Codable Decode

```swift
struct Product: Decodable { let sku: String; let price: Double }

let cursor   = try XMLEventCursor(data: catalogData)
let products = try XMLItemDecoder().decode(Product.self, itemElement: "Product", from: cursor)

// Or async, one item at a time (macOS 12+):
for try await product in XMLItemDecoder().items(Product.self, itemElement: "Product", from: cursor) {
    await persist(product)
}
```

---

## Documentation

Full API documentation and guides:

- [Getting Started](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/GettingStarted.md)
- [Field Mapping](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/FieldMapping.md)
- [Namespaces](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/Namespaces.md)
- [Streaming](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/Streaming.md)
- [Canonicalization](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/Canonicalization.md)
- [XPath](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/XPath.md)
- [Security](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/Security.md)
- [Swift Version Compatibility](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/Compatibility.md)
- [Test Support](Sources/SwiftXMLCoder/SwiftXMLCoder.docc/Articles/TestSupport.md)

---

## Requirements

| Component | Requirement |
|-----------|-------------|
| Swift | 5.6+ (macros require 5.9+) |
| macOS | 10.15+ |
| iOS | 15.0+ |
| tvOS | 15.0+ |
| watchOS | 8.0+ |
| Linux | Ubuntu 20.04+ with `libxml2-dev` |
| Package manager | Swift Package Manager only |

---

## License

MIT — see [LICENSE](LICENSE).
