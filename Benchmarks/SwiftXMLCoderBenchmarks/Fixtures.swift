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
