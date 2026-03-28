import Benchmark
import Foundation
import SwiftXMLCoder

// MARK: - SAX decode decomposition
//
// These benchmarks decompose the total SAX decode cost into layers:
//
//   SAXParseOnly/*     — libxml2 parse + event callbacks only; no buffer construction,
//                        no Codable decode. Measures pure parser throughput.
//
//   Decode/SAX/*       — full decode: SAXParseOnly + _XMLEventBuffer init (side tables)
//                        + _XMLSAXDecoder + Codable decode. Defined in DecodeBenchmarks.swift.
//
//   KeyedDecode/*      — full decode on fixtures engineered to stress specific sub-costs:
//     /Flat            — BenchmarkItem (5 fields): baseline keyed lookup + scalar decode
//     /Wide            — WideItem (20 fields): high keyed-lookup density per element
//     /Nested          — NestedOuter (3 levels): nested decoder creation + childElementSpans
//
// The gap  Decode/SAX − SAXParseOnly  is the cost of buffer construction + Codable decode.
// The gap  KeyedDecode/Wide − KeyedDecode/Flat  (normalized per field) reveals per-key overhead.

func microbenchmarks() {
    let saxParser = XMLStreamParser()
    let decoder = XMLDecoder()

    // MARK: SAX parse-only

    for (label, data) in [
        ("10KB", xmlData10KB), ("100KB", xmlData100KB),
        ("1MB", xmlData1MB), ("10MB", xmlData10MB)
    ] {
        Benchmark("SAXParseOnly/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                try saxParser.parseSAX(data: data) { event in
                    blackHole(event)
                }
            }
        }
    }

    // MARK: Keyed decode — flat (5 fields/element)

    for (label, data) in [("10KB", xmlData10KB), ("100KB", xmlData100KB), ("1MB", xmlData1MB)] {
        Benchmark("KeyedDecode/Flat/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(BenchmarkCollection.self, from: data))
            }
        }
    }

    // MARK: Keyed decode — wide (20 fields/element)
    // High keyed-lookup density: exercises childSpansByName and attributesByName caches.

    for (label, data) in [("10KB", xmlDataWide10KB), ("100KB", xmlDataWide100KB)] {
        Benchmark("KeyedDecode/Wide/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(WideCollection.self, from: data))
            }
        }
    }

    // MARK: Keyed decode — nested (3 levels)
    // Exercises nested decoder creation and childElementSpans per level.

    for (label, data) in [("10KB", xmlDataNested10KB), ("100KB", xmlDataNested100KB)] {
        Benchmark("KeyedDecode/Nested/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(NestedCollection.self, from: data))
            }
        }
    }
}
