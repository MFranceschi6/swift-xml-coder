import Benchmark
import Foundation
import SwiftXMLCoder
import XMLCoder

// Entry point discovered by the BenchmarkPlugin.
let benchmarks: @Sendable () -> Void = {
    comparisonBenchmarks()
}

// MARK: - SwiftXMLCoder vs CoreOffice/XMLCoder: Codable Decode & Encode

func comparisonBenchmarks() {

    // Decode comparison

    for (label, data) in [
        ("10KB", compXmlData10KB), ("100KB", compXmlData100KB),
        ("1MB", compXmlData1MB), ("10MB", compXmlData10MB)
    ] {
        Benchmark("Compare/Decode/SwiftXMLCoder/SAX/\(label)") { benchmark in
            let decoder = SwiftXMLCoder.XMLDecoder()
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(CompBenchmarkCollection.self, from: data))
            }
        }

        Benchmark("Compare/Decode/XMLCoder/\(label)") { benchmark in
            let decoder = XMLCoder.XMLDecoder()
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(CompBenchmarkCollection.self, from: data))
            }
        }
    }

    // Encode comparison

    for (label, collection) in [
        ("10KB", compCollection10KB), ("100KB", compCollection100KB),
        ("1MB", compCollection1MB), ("10MB", compCollection10MB)
    ] as [(String, CompBenchmarkCollection)] {
        Benchmark("Compare/Encode/SwiftXMLCoder/\(label)") { benchmark in
            let encoder = SwiftXMLCoder.XMLEncoder()
            for _ in benchmark.scaledIterations {
                blackHole(try? encoder.encode(collection))
            }
        }

        Benchmark("Compare/Encode/XMLCoder/\(label)") { benchmark in
            let encoder = XMLCoder.XMLEncoder()
            for _ in benchmark.scaledIterations {
                blackHole(try? encoder.encode(collection))
            }
        }
    }
}
