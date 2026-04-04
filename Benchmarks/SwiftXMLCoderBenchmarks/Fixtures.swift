import Foundation
import SwiftXMLCoder

// MARK: - Benchmark model types

struct BenchmarkItem: Codable, Sendable {
    var id: Int
    var name: String
    var description: String
    var price: Double
    var active: Bool
}

struct BenchmarkCollection: Codable, Sendable {
    var items: [BenchmarkItem]
}

extension BenchmarkCollection: XMLRootNode {
    static var xmlRootElementName: String { "collection" }
}

// MARK: - Fixture data generators

private func makeBenchmarkItems(_ count: Int) -> [BenchmarkItem] {
    (1...max(1, count)).map { i in
        BenchmarkItem(
            id: i,
            name: "Item \(i)",
            description: "Description for benchmark item number \(i) in the test fixture",
            price: Double(i) * 1.23,
            active: i % 2 == 0
        )
    }
}

private func encodeFixture(itemCount: Int) -> Data {
    let collection = BenchmarkCollection(items: makeBenchmarkItems(itemCount))
    guard let data = try? XMLEncoder().encode(collection) else {
        fatalError("Benchmark fixture encoding failed — this is a programming error")
    }
    return data
}

// MARK: - Pre-encoded XML data (for parse and decode benchmarks)

/// ~1 KB of XML (≈6 items)
let xmlData1KB: Data = encodeFixture(itemCount: 6)
/// ~10 KB of XML (≈60 items)
let xmlData10KB: Data = encodeFixture(itemCount: 60)
/// ~100 KB of XML (≈600 items)
let xmlData100KB: Data = encodeFixture(itemCount: 600)
/// ~1 MB of XML (≈6000 items)
let xmlData1MB: Data = encodeFixture(itemCount: 6000)
/// ~10 MB of XML (≈60 000 items) — enterprise scale, streaming-only
let xmlData10MB: Data = encodeFixture(itemCount: 60_000)
/// ~100 MB of XML (≈600 000 items) — stress scale, streaming-only
let xmlData100MB: Data = encodeFixture(itemCount: 600_000)

// MARK: - Pre-built Swift structs (for encode benchmarks)

/// Small collection for encode benchmarks (~1 KB output)
let collection1KB: BenchmarkCollection = BenchmarkCollection(items: makeBenchmarkItems(6))
/// Medium collection for encode benchmarks (~10 KB output)
let collection10KB: BenchmarkCollection = BenchmarkCollection(items: makeBenchmarkItems(60))
/// Large collection for encode benchmarks (~100 KB output)
let collection100KB: BenchmarkCollection = BenchmarkCollection(items: makeBenchmarkItems(600))
/// Extra-large collection for encode benchmarks (~1 MB output)
let collection1MB: BenchmarkCollection = BenchmarkCollection(items: makeBenchmarkItems(6000))

// MARK: - Pre-parsed trees (for canonicalization benchmarks)

private func parseFixture(_ data: Data) -> XMLTreeDocument {
    guard let doc = try? XMLTreeParser().parse(data: data) else {
        fatalError("Benchmark fixture parsing failed — this is a programming error")
    }
    return doc
}

let parsedDoc1KB: XMLTreeDocument = parseFixture(xmlData1KB)
let parsedDoc10KB: XMLTreeDocument = parseFixture(xmlData10KB)
let parsedDoc100KB: XMLTreeDocument = parseFixture(xmlData100KB)

// MARK: - Microbenchmark fixtures

// WideItem: 20 scalar fields — exercises keyed lookup and scalar decode densely per element.
struct WideItem: Codable, Sendable {
    var f01: Int; var f02: Int; var f03: Int; var f04: Int; var f05: Int
    var f06: Double; var f07: Double; var f08: Double; var f09: Double; var f10: Double
    var f11: String; var f12: String; var f13: String; var f14: String; var f15: String
    var f16: Bool; var f17: Bool; var f18: Bool; var f19: Bool; var f20: Bool
}

struct WideCollection: Codable, Sendable {
    var items: [WideItem]
}

extension WideCollection: XMLRootNode {
    static var xmlRootElementName: String { "collection" }
}

private func makeWideItem(_ i: Int) -> WideItem {
    let d = Double(i)
    return WideItem(
        f01: i, f02: i + 1, f03: i + 2, f04: i + 3, f05: i + 4,
        f06: d * 1.1, f07: d * 2.2, f08: d * 3.3, f09: d * 4.4, f10: d * 5.5,
        f11: "s\(i)", f12: "s\(i + 1)", f13: "s\(i + 2)", f14: "s\(i + 3)", f15: "s\(i + 4)",
        f16: i % 2 == 0, f17: i % 3 == 0, f18: i % 4 == 0, f19: i % 5 == 0, f20: i % 6 == 0
    )
}

private func makeWideItems(_ count: Int) -> [WideItem] {
    (1...max(1, count)).map { makeWideItem($0) }
}

private func encodeWideFixture(itemCount: Int) -> Data {
    let collection = WideCollection(items: makeWideItems(itemCount))
    guard let data = try? XMLEncoder().encode(collection) else {
        fatalError("Wide fixture encoding failed — this is a programming error")
    }
    return data
}

// ~10 KB of wide-item XML (≈15 items × 20 fields each)
let xmlDataWide10KB: Data = encodeWideFixture(itemCount: 15)
// ~100 KB of wide-item XML (≈150 items × 20 fields each)
let xmlDataWide100KB: Data = encodeWideFixture(itemCount: 150)

// NestedItem: 3 levels of nesting — exercises childElementSpans and nested decoder creation.
struct NestedLeaf: Codable, Sendable {
    var value: String
    var count: Int
}

struct NestedMid: Codable, Sendable {
    var label: String
    var leaf: NestedLeaf
}

struct NestedOuter: Codable, Sendable {
    var id: Int
    var mid: NestedMid
}

struct NestedCollection: Codable, Sendable {
    var items: [NestedOuter]
}

extension NestedCollection: XMLRootNode {
    static var xmlRootElementName: String { "collection" }
}

private func makeNestedItems(_ count: Int) -> [NestedOuter] {
    (1...max(1, count)).map { i in
        NestedOuter(id: i, mid: NestedMid(label: "label\(i)", leaf: NestedLeaf(value: "v\(i)", count: i)))
    }
}

private func encodeNestedFixture(itemCount: Int) -> Data {
    let collection = NestedCollection(items: makeNestedItems(itemCount))
    guard let data = try? XMLEncoder().encode(collection) else {
        fatalError("Nested fixture encoding failed — this is a programming error")
    }
    return data
}

// ~10 KB of nested XML (≈200 3-level items)
let xmlDataNested10KB: Data = encodeNestedFixture(itemCount: 200)
// ~100 KB of nested XML (≈2000 3-level items)
let xmlDataNested100KB: Data = encodeNestedFixture(itemCount: 2000)
