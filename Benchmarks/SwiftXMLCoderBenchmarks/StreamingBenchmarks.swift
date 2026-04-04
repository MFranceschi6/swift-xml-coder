import Benchmark
import Foundation
import SwiftXMLCoder

func streamingBenchmarks() {

    // MARK: - SAX Push Parse (XMLStreamParser)

    for (label, data) in [
        ("10KB", xmlData10KB), ("100KB", xmlData100KB), ("1MB", xmlData1MB),
        ("10MB", xmlData10MB), ("100MB", xmlData100MB)
    ] {
        Benchmark("StreamParse/SAX/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                var count = 0
                try? XMLStreamParser().parse(data: data) { _ in count += 1 }
                blackHole(count)
            }
        }
    }

    // MARK: - Item-by-Item Decode (XMLItemDecoder)

    for (label, data) in [
        ("10KB", xmlData10KB), ("100KB", xmlData100KB), ("1MB", xmlData1MB),
        ("10MB", xmlData10MB), ("100MB", xmlData100MB)
    ] {
        Benchmark("StreamDecode/ItemDecoder/\(label)") { benchmark in
            let decoder = XMLItemDecoder()
            for _ in benchmark.scaledIterations {
                blackHole(
                    try? decoder.decode(
                        BenchmarkItem.self,
                        itemElement: "items",
                        from: data
                    )
                )
            }
        }
    }

    // MARK: - Stream Writer

    // Pre-parse events for writer benchmarks
    let writerFixtures: [(String, [XMLStreamEvent])] = [
        ("10KB", xmlData10KB), ("100KB", xmlData100KB),
        ("1MB", xmlData1MB), ("10MB", xmlData10MB)
    ].compactMap { label, data in
        var events: [XMLStreamEvent] = []
        try? XMLStreamParser().parse(data: data) { events.append($0) }
        return (label, events)
    }

    for (label, events) in writerFixtures {
        Benchmark("StreamWrite/\(label)") { benchmark in
            let writer = XMLStreamWriter()
            for _ in benchmark.scaledIterations {
                blackHole(try? writer.write(events))
            }
        }
    }
}
