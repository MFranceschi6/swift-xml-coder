import Foundation
import SwiftXMLCoder

// Duplicated fixture model for the comparison target to avoid cross-target dependencies.
// Keep in sync with SwiftXMLCoderBenchmarks/Fixtures.swift.

struct CompBenchmarkItem: Codable, Sendable {
    var id: Int
    var name: String
    var description: String
    var price: Double
    var active: Bool
}

struct CompBenchmarkCollection: Codable, Sendable {
    var items: [CompBenchmarkItem]
}

extension CompBenchmarkCollection: XMLRootNode {
    static var xmlRootElementName: String { "collection" }
}

private func makeItems(_ count: Int) -> [CompBenchmarkItem] {
    (1...max(1, count)).map { i in
        CompBenchmarkItem(
            id: i,
            name: "Item \(i)",
            description: "Description for benchmark item number \(i) in the test fixture",
            price: Double(i) * 1.23,
            active: i % 2 == 0
        )
    }
}

private func encodeFixture(itemCount: Int) -> Data {
    let collection = CompBenchmarkCollection(items: makeItems(itemCount))
    guard let data = try? SwiftXMLCoder.XMLEncoder().encode(collection) else {
        fatalError("Comparison fixture encoding failed")
    }
    return data
}

// Pre-encoded XML data
let compXmlData10KB: Data = encodeFixture(itemCount: 60)
let compXmlData100KB: Data = encodeFixture(itemCount: 600)
let compXmlData1MB: Data = encodeFixture(itemCount: 6000)
let compXmlData10MB: Data = encodeFixture(itemCount: 60_000)

// Pre-built Swift structs
let compCollection10KB = CompBenchmarkCollection(items: makeItems(60))
let compCollection100KB = CompBenchmarkCollection(items: makeItems(600))
let compCollection1MB = CompBenchmarkCollection(items: makeItems(6000))
let compCollection10MB = CompBenchmarkCollection(items: makeItems(60_000))
