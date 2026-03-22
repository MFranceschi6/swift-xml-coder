import Benchmark
import Foundation
import SwiftXMLCoder

// MARK: - Minimal Foundation XMLParser delegate (counts events only)

private final class EventCountingDelegate: NSObject, XMLParserDelegate {
    var count = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        count += 1
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        count += 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        count += 1
    }
}

// MARK: - Foundation XMLParser SAX comparison

func foundationComparison() {

    // SAX: Foundation XMLParser vs SwiftXMLCoder XMLStreamParser

    for (label, data) in [
        ("10KB", xmlData10KB), ("100KB", xmlData100KB), ("1MB", xmlData1MB),
        ("10MB", xmlData10MB), ("100MB", xmlData100MB)
    ] {
        Benchmark("Compare/Foundation/SAXParse/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                let delegate = EventCountingDelegate()
                let parser = XMLParser(data: data)
                parser.delegate = delegate
                blackHole(parser.parse())
                blackHole(delegate.count)
            }
        }

        Benchmark("Compare/SwiftXMLCoder/SAXParse/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                var count = 0
                try? XMLStreamParser().parse(data: data) { _ in count += 1 }
                blackHole(count)
            }
        }
    }

    // Tree: Foundation XMLDocument vs SwiftXMLCoder XMLTreeParser
    // Foundation.XMLDocument is only available via FoundationXML on Linux.
    // Scale limited to 10MB (tree materializes full DOM).

    #if canImport(FoundationXML) || os(macOS)
    for (label, data) in [
        ("10KB", xmlData10KB), ("100KB", xmlData100KB),
        ("1MB", xmlData1MB), ("10MB", xmlData10MB)
    ] {
        Benchmark("Compare/Foundation/TreeParse/\(label)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(try? XMLDocument(data: data, options: []))
            }
        }

        Benchmark("Compare/SwiftXMLCoder/TreeParse/\(label)") { benchmark in
            let parser = XMLTreeParser()
            for _ in benchmark.scaledIterations {
                blackHole(try? parser.parse(data: data))
            }
        }
    }
    #endif
}
