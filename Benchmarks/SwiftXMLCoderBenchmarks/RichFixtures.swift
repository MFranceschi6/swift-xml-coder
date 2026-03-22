import Foundation
import SwiftXMLCoder

// MARK: - Rich benchmark model types (nested, attributes, namespaces)

struct RichCountry: Codable, Sendable {
    var code: String
    var name: String
}

struct RichAddress: Codable, Sendable {
    var street: String
    var city: String
    var zip: String
    var country: RichCountry
}

struct RichItem: Codable, Sendable {
    var id: Int
    var currency: String
    var address: RichAddress
    var tags: [String]
    var amount: Double
    var notes: String
}

struct RichCollection: Codable, Sendable {
    var items: [RichItem]
}

extension RichCollection: XMLRootNode {
    static var xmlRootElementName: String { "richCollection" }
}

// MARK: - Rich fixture generators

private func makeRichItems(_ count: Int) -> [RichItem] {
    (1...max(1, count)).map { i -> RichItem in
        let country = RichCountry(
            code: i % 3 == 0 ? "DE" : (i % 3 == 1 ? "IT" : "US"),
            name: i % 3 == 0 ? "Germany" : (i % 3 == 1 ? "Italy" : "United States")
        )
        let address = RichAddress(
            street: "Street \(i)",
            city: "City \(i % 50)",
            zip: String(format: "%05d", i % 100_000),
            country: country
        )
        return RichItem(
            id: i,
            currency: i % 2 == 0 ? "EUR" : "USD",
            address: address,
            tags: ["tag-\(i % 10)", "category-\(i % 5)"],
            amount: Double(i) * 9.99,
            notes: "Benchmark note for rich item \(i). This is a longer text field designed to exercise text node parsing with realistic payload sizes in the benchmark suite."
        )
    }
}

private func encodeRichFixture(itemCount: Int) -> Data {
    let collection = RichCollection(items: makeRichItems(itemCount))
    guard let data = try? XMLEncoder().encode(collection) else {
        fatalError("Rich benchmark fixture encoding failed — this is a programming error")
    }
    return data
}

// MARK: - Pre-encoded rich XML data

/// ~10 KB of rich XML (≈20 items — ~3x bytes per item vs flat)
let richXmlData10KB: Data = encodeRichFixture(itemCount: 20)
/// ~100 KB of rich XML (≈200 items)
let richXmlData100KB: Data = encodeRichFixture(itemCount: 200)
/// ~1 MB of rich XML (≈2000 items)
let richXmlData1MB: Data = encodeRichFixture(itemCount: 2000)
/// ~10 MB of rich XML (≈20 000 items)
let richXmlData10MB: Data = encodeRichFixture(itemCount: 20_000)
/// ~100 MB of rich XML (≈200 000 items) — streaming-only
let richXmlData100MB: Data = encodeRichFixture(itemCount: 200_000)

// MARK: - Pre-built Swift structs (for encode benchmarks)

let richCollection10KB = RichCollection(items: makeRichItems(20))
let richCollection100KB = RichCollection(items: makeRichItems(200))
let richCollection1MB = RichCollection(items: makeRichItems(2000))
let richCollection10MB = RichCollection(items: makeRichItems(20_000))
