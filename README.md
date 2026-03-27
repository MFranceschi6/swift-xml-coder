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

## Performance

SwiftXMLCoder ships with a comprehensive benchmark suite covering tree parsing, streaming (SAX push, pull cursor, item-by-item decode), Codable encode/decode, and comparisons against Foundation `XMLParser` and [CoreOffice/XMLCoder](https://github.com/CoreOffice/XMLCoder).

### When to Use What

| Document Size | Recommended Approach | Why |
|---------------|---------------------|-----|
| < 1 MB | `XMLDecoder` (tree) | Simplest API, minimal overhead |
| 1 - 10 MB | Tree or `XMLItemDecoder` | Tree works but uses more memory |
| > 10 MB | `XMLItemDecoder` / `XMLStreamParser` | Constant memory vs linear; tree does not scale |

### Measured Results

All figures are p50 wall-clock times. Measured on Apple M1 (arm64, 8 GB), macOS 15.3, release build with jemalloc.

| Operation | 10 KB | 100 KB | 1 MB | 10 MB |
|-----------|-------|--------|------|-------|
| Tree parse (`XMLTreeParser`) | 237 µs | 2.3 ms | 24 ms | 232 ms |
| SAX push (`XMLStreamParser`) | 225 µs | 2.2 ms | 20 ms | 208 ms |
| Pull cursor (`XMLEventCursor`) | 272 µs | 2.7 ms | 27 ms | 280 ms |
| Codable decode (`XMLDecoder`) | 554 µs | 5.6 ms | 55 ms | 545 ms |
| Codable encode (`XMLEncoder`) | 872 µs | 8.2 ms | 81 ms | 829 ms |
| Stream write (`XMLStreamWriter`) | 221 µs | 2.3 ms | 21 ms | 215 ms |
| Item decode (`XMLItemDecoder`, rich model) | — | — | 53 ms | — |

### GitHub Actions Results

All figures are p50 wall-clock times from the manual GitHub Actions benchmark run on March 22, 2026, using the `macos-15` hosted runner, Swift 6.1, and jemalloc. Run: [actions/runs/23411043764](https://github.com/MFranceschi6/swift-xml-coder/actions/runs/23411043764).

| Operation | 10 KB | 100 KB | 1 MB | 10 MB |
|-----------|-------|--------|------|-------|
| Tree parse (`XMLTreeParser`) | 268 µs | 2.7 ms | 29 ms | 241 ms |
| SAX push (`XMLStreamParser`) | 230 µs | 2.2 ms | 28 ms | 267 ms |
| Pull cursor (`XMLEventCursor`) | 281 µs | 2.8 ms | 43 ms | 439 ms |
| Codable decode (`XMLDecoder`) | 591 µs | 5.7 ms | 59 ms | 588 ms |
| Codable encode (`XMLEncoder`) | 837 µs | 8.1 ms | 108 ms | 962 ms |
| Stream write (`XMLStreamWriter`) | 243 µs | 2.5 ms | 24 ms | 230 ms |
| Item decode (`XMLItemDecoder`, rich model) | — | — | 74 ms | — |

### Cross-Machine Observations

The GitHub-hosted runner preserves the same overall ranking as the local M1 run, but most internal benchmarks are modestly slower in CI. Small-payload encode stays effectively flat, while larger streaming workloads drift more: `XMLEventCursor` moves from 27 ms to 43 ms at 1 MB, and rich `XMLItemDecoder` from 53 ms to 74 ms at 1 MB. No benchmark job failed, and there were no correctness warnings or crashes in the run.

One important documentation fix came out of the CI comparison: the previous `Foundation XMLParser` note was inverted. In both local and GitHub Actions measurements, Foundation SAX parsing is faster than SwiftXMLCoder's SAX parser at 1 MB, while SwiftXMLCoder's tree parser remains faster than Foundation `XMLDocument`.

**vs Foundation `XMLParser` (SAX):** SwiftXMLCoder is about 2.0-2.3x slower at 1 MB in both local and GitHub Actions runs (`~21-22 ms` vs `~9-11 ms`). This is consistent across 10 KB and 100 KB as well.

**vs Foundation `XMLDocument` (tree):** SwiftXMLCoder is about 18-25% faster at 1 MB (`23-24 ms` vs `28-32 ms`) across local and GitHub Actions runs.

**vs CoreOffice/XMLCoder decode:** SwiftXMLCoder remains faster on both machines, from about 1.3-1.5x at 100 KB to about 1.5-2.6x at 10 MB depending on the runner.

**vs CoreOffice/XMLCoder encode:** SwiftXMLCoder remains about 1.5-1.7x faster across all scales on both local and GitHub Actions runs.

### Benchmark Coverage

| Area | Scales | What It Measures |
|------|--------|-----------------|
| Tree parse / decode / encode | 10KB - 10MB | Full DOM materialization + Codable round-trip |
| SAX push (`XMLStreamParser`) | 10KB - 100MB | Event-driven parsing, no tree allocation |
| Pull cursor (`XMLEventCursor`) | 10KB - 100MB | Lazy pull-based iteration |
| Item-by-item (`XMLItemDecoder`) | 10KB - 100MB | Streaming Codable decode, constant memory |
| Stream writer (`XMLStreamWriter`) | 10KB - 10MB | Event sequence to XML serialization |
| Rich model (nested + attributes) | 10KB - 100MB | Real-world payload with 3-level nesting, namespaces |
| Foundation `XMLParser` comparison | 10KB - 100MB | SAX + tree parse vs Apple's built-in parser |
| CoreOffice/XMLCoder comparison | 10KB - 10MB | Codable decode/encode head-to-head |

### Running Benchmarks

```bash
cd Benchmarks

# Internal benchmarks (parse, stream, encode, decode, Foundation comparison)
swift package --disable-sandbox benchmark

# Comparative benchmarks (SwiftXMLCoder vs CoreOffice/XMLCoder)
swift package --disable-sandbox benchmark --target ComparisonBenchmarks
```

Benchmarks use [ordo-one/package-benchmark](https://github.com/ordo-one/package-benchmark) and require macOS 13+ with jemalloc (`brew install jemalloc`).

The repository also runs benchmark regression checks in GitHub Actions via [`.github/workflows/benchmarks.yml`](./.github/workflows/benchmarks.yml). Every PR to `main` is compared against a `main` baseline on a macOS runner, so we can track regressions with a shared CI reference instead of relying only on local machine measurements.

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
