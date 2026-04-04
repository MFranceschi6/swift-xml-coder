import Benchmark
import Foundation
import SwiftXMLCoder

private struct NoOpEventTransform: XMLEventTransform {
    mutating func process(_ event: XMLStreamEvent) throws -> [XMLStreamEvent] { [event] }
    mutating func finalize() throws -> [XMLStreamEvent] { [] }
}

private struct NormalizeTextEventTransform: XMLEventTransform {
    mutating func process(_ event: XMLStreamEvent) throws -> [XMLStreamEvent] {
        if case .text(let value) = event {
            let normalized = value
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return normalized.isEmpty ? [] : [.text(normalized)]
        }
        return [event]
    }

    mutating func finalize() throws -> [XMLStreamEvent] { [] }
}

func canonicalizationBenchmarks() {
    let canonicalizer = XMLDefaultCanonicalizer()
    let options = XMLCanonicalizationOptions()
    let transforms: XMLTransformPipeline = []
    let treeFixtures: [(String, XMLTreeDocument)] = [
        ("1KB", parsedDoc1KB),
        ("10KB", parsedDoc10KB),
        ("100KB", parsedDoc100KB)
    ]
    let dataFixtures: [(String, Data)] = [
        ("1KB", xmlData1KB),
        ("10KB", xmlData10KB),
        ("100KB", xmlData100KB)
    ]
    let eventFixtures: [(String, [XMLStreamEvent])] = dataFixtures.map { label, data in
        var events: [XMLStreamEvent] = []
        try? XMLStreamParser().parse(data: data) { events.append($0) }
        return (label, events)
    }

    for (label, doc) in treeFixtures {
        Benchmark("Canonicalize/Tree/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? canonicalizer.canonicalize(doc, options: options, transforms: transforms))
            }
        }
    }

    for (label, data) in dataFixtures {
        Benchmark("Canonicalize/StreamData/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? canonicalizer.canonicalize(data: data, options: options, eventTransforms: []))
            }
        }
    }

    for (label, events) in eventFixtures {
        Benchmark("Canonicalize/StreamEvents/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? canonicalizer.canonicalize(events: events, options: options, eventTransforms: []))
            }
        }
    }

    for (label, data) in dataFixtures {
        Benchmark("Canonicalize/StreamData/NoOpTransform/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(
                    try? canonicalizer.canonicalize(
                        data: data,
                        options: options,
                        eventTransforms: [NoOpEventTransform()]
                    )
                )
            }
        }
    }

    for (label, data) in dataFixtures {
        Benchmark("Canonicalize/StreamData/NormalizeTextTransform/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(
                    try? canonicalizer.canonicalize(
                        data: data,
                        options: options,
                        eventTransforms: [NormalizeTextEventTransform()]
                    )
                )
            }
        }
    }
}
