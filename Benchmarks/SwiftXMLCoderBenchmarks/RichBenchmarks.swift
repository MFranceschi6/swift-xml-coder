import Benchmark
import Foundation
import SwiftXMLCoder

func richBenchmarks() {
    let parser = XMLTreeParser()
    let decoder = XMLDecoder()
    let encoder = XMLEncoder()

    // MARK: - Rich Tree Parse

    for (label, data) in [
        ("10KB", richXmlData10KB), ("100KB", richXmlData100KB),
        ("1MB", richXmlData1MB), ("10MB", richXmlData10MB)
    ] {
        Benchmark("Parse/Rich/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? parser.parse(data: data))
            }
        }
    }

    // MARK: - Rich Codable Decode

    for (label, data) in [
        ("10KB", richXmlData10KB), ("100KB", richXmlData100KB),
        ("1MB", richXmlData1MB), ("10MB", richXmlData10MB)
    ] {
        Benchmark("Decode/Rich/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(RichCollection.self, from: data))
            }
        }
    }

    // MARK: - Rich Codable Decode split (SAX vs Tree)

    for (label, data) in [
        ("10KB", richXmlData10KB), ("100KB", richXmlData100KB),
        ("1MB", richXmlData1MB), ("10MB", richXmlData10MB)
    ] {
        Benchmark("Decode/Rich/SAX/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? decoder.decode(RichCollection.self, from: data))
            }
        }

        Benchmark("Decode/Rich/Tree/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                guard let tree = try? parser.parse(data: data) else {
                    blackHole(nil as RichCollection?)
                    continue
                }
                blackHole(try? decoder.decodeTree(RichCollection.self, from: tree))
            }
        }
    }

    // MARK: - Rich Codable Encode

    for (label, collection) in [
        ("10KB", richCollection10KB), ("100KB", richCollection100KB),
        ("1MB", richCollection1MB), ("10MB", richCollection10MB)
    ] as [(String, RichCollection)] {
        Benchmark("Encode/Rich/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? encoder.encode(collection))
            }
        }
    }

    // MARK: - Rich Streaming (SAX + ItemDecoder)

    for (label, data) in [
        ("10KB", richXmlData10KB), ("100KB", richXmlData100KB),
        ("1MB", richXmlData1MB), ("10MB", richXmlData10MB),
        ("100MB", richXmlData100MB)
    ] {
        Benchmark("StreamParse/SAX/Rich/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                var count = 0
                try? XMLStreamParser().parse(data: data) { _ in count += 1 }
                blackHole(count)
            }
        }
    }

    for (label, data) in [
        ("10KB", richXmlData10KB), ("100KB", richXmlData100KB),
        ("1MB", richXmlData1MB), ("10MB", richXmlData10MB),
        ("100MB", richXmlData100MB)
    ] {
        Benchmark("StreamDecode/ItemDecoder/Rich/\(label)") { benchmark in
            let itemDecoder = XMLItemDecoder()
            for _ in benchmark.scaledIterations {
                let cursor = try XMLEventCursor(data: data)
                blackHole(
                    try? itemDecoder.decode(
                        RichItem.self,
                        itemElement: "items",
                        from: cursor
                    )
                )
            }
        }
    }
}
