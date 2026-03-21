import Foundation
import SwiftXMLCoder
import XCTest

// Run under ThreadSanitizer to detect data races:
//   swift test -Xswiftc -sanitize=thread --filter XMLConcurrencyStressTests
//
// The CI `concurrency` job does exactly this on every push/PR.
final class XMLConcurrencyStressTests: XCTestCase {

    // 100 concurrent tasks is enough to surface races under TSan while keeping
    // CI runtime reasonable.
    private let iterations = 100

    // MARK: - Shared encoder (DispatchQueue)

    func test_encode_sharedEncoder_noDataRace() {
        // The same XMLEncoder instance is used from all concurrent tasks.
        // Verifies that the Sendable conformance is race-free in practice.
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Payload"))
        stressRun {
            _ = try? encoder.encode(StressPayload.sample)
        }
    }

    // MARK: - Shared decoder (DispatchQueue)

    func test_decode_sharedDecoder_noDataRace() {
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let xml = StressPayload.sampleXML
        stressRun {
            _ = try? decoder.decode(StressPayload.self, from: xml)
        }
    }

    // MARK: - Concurrent round-trip (DispatchQueue)

    func test_encodeDecode_concurrent_roundTrip() {
        // Each task uses separate encoder/decoder instances so we exercise
        // concurrent libxml2 document creation and destruction paths.
        stressRun {
            let encoder = XMLEncoder(configuration: .init(rootElementName: "P"))
            let decoder = XMLDecoder(configuration: .init(rootElementName: "P"))
            let input = StressPayload(id: Int.random(in: 0..<10_000), label: "stress")
            guard
                let data = try? encoder.encode(input),
                let decoded = try? decoder.decode(StressPayload.self, from: data)
            else { return }
            XCTAssertEqual(decoded, input)
        }
    }

    // MARK: - Shared parser (DispatchQueue)

    func test_parse_sharedParser_noDataRace() {
        let parser = XMLTreeParser()
        let xml = Data("<Root><child>hello</child></Root>".utf8)
        stressRun {
            _ = try? parser.parse(data: xml)
        }
    }

    // MARK: - xmlInitParser concurrent first-use (DispatchQueue)

    func test_xmlInitParser_concurrentFirstUse_noRace() {
        // Swift's `lazy static let` is backed by dispatch_once and is thread-safe.
        // This test exercises the initialisation codepath concurrently under TSan
        // to confirm there is no race on the LibXML2.ensureInitialized() callsite.
        // (The first task to reach the initialiser wins; all others block safely.)
        stressRun {
            _ = try? XMLTreeParser().parse(data: Data("<X/>".utf8))
        }
    }

    // MARK: - Mixed encode + decode + parse (DispatchQueue)

    func test_mixed_concurrent_noDataRace() {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Item"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Item"))
        let parser  = XMLTreeParser()
        let rawXML  = Data("<Item><id>7</id><label>mix</label></Item>".utf8)

        stressRun {
            switch Int.random(in: 0..<3) {
            case 0: _ = try? encoder.encode(StressPayload.sample)
            case 1: _ = try? decoder.decode(StressPayload.self, from: rawXML)
            default: _ = try? parser.parse(data: rawXML)
            }
        }
    }

    // MARK: - Shared encoder (async/await TaskGroup)

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    func test_encode_sharedEncoder_noDataRace_async() async {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Payload"))
        await asyncStressRun {
            _ = try? encoder.encode(StressPayload.sample)
        }
    }

    // MARK: - Shared decoder (async/await TaskGroup)

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    func test_decode_sharedDecoder_noDataRace_async() async {
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let xml = StressPayload.sampleXML
        await asyncStressRun {
            _ = try? decoder.decode(StressPayload.self, from: xml)
        }
    }

    // MARK: - Concurrent round-trip (async/await TaskGroup)

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    func test_encodeDecode_concurrent_roundTrip_async() async {
        await asyncStressRun {
            let encoder = XMLEncoder(configuration: .init(rootElementName: "P"))
            let decoder = XMLDecoder(configuration: .init(rootElementName: "P"))
            let input = StressPayload(id: Int.random(in: 0..<10_000), label: "stress")
            guard
                let data = try? encoder.encode(input),
                let decoded = try? decoder.decode(StressPayload.self, from: data)
            else { return }
            XCTAssertEqual(decoded, input)
        }
    }

    // MARK: - Shared parser (async/await TaskGroup)

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    func test_parse_sharedParser_noDataRace_async() async {
        let parser = XMLTreeParser()
        let xml = Data("<Root><child>hello</child></Root>".utf8)
        await asyncStressRun {
            _ = try? parser.parse(data: xml)
        }
    }

    // MARK: - Mixed encode + decode + parse (async/await TaskGroup)

    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    func test_mixed_concurrent_noDataRace_async() async {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Item"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Item"))
        let parser  = XMLTreeParser()
        let rawXML  = Data("<Item><id>7</id><label>mix</label></Item>".utf8)

        await asyncStressRun {
            switch Int.random(in: 0..<3) {
            case 0: _ = try? encoder.encode(StressPayload.sample)
            case 1: _ = try? decoder.decode(StressPayload.self, from: rawXML)
            default: _ = try? parser.parse(data: rawXML)
            }
        }
    }

    // MARK: - Helpers

    private struct StressPayload: Codable, Equatable {
        let id: Int
        let label: String

        static let sample = StressPayload(id: 42, label: "widget")
        static let sampleXML = Data(
            "<Payload><id>42</id><label>widget</label></Payload>".utf8
        )
    }

    /// Submits `block` to a concurrent DispatchQueue `iterations` times and waits
    /// for all tasks to complete. Under TSan the runtime instruments every memory
    /// access, so genuine races will be reported as test failures.
    private func stressRun(_ block: @escaping @Sendable () -> Void) {
        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "SwiftXMLCoder.stressTests",
            attributes: .concurrent
        )
        for _ in 0..<iterations {
            group.enter()
            queue.async {
                block()
                group.leave()
            }
        }
        group.wait()
    }

    /// Spawns `iterations` child Tasks inside a TaskGroup and awaits all of them.
    /// Exercises Swift structured concurrency's cooperative thread pool instead of
    /// GCD, ensuring both scheduling models are race-free under TSan.
    @available(macOS 10.15, iOS 13, watchOS 6, tvOS 13, *)
    private func asyncStressRun(_ block: @escaping @Sendable () -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask { block() }
            }
        }
    }
}
