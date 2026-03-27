import Foundation
import SwiftXMLCoder
import XCTest

final class XMLStreamingLargeInputStressTests: XCTestCase {

    private struct Product: Decodable {
        let id: Int
        let name: String
        let description: String
        let price: Double
        let active: Bool
    }

    private var shouldRunStressTests: Bool {
        ProcessInfo.processInfo.environment["RUN_LARGE_XML_STRESS"] == "1"
    }

    private func makeBenchmarkStyleXML(itemCount: Int) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><collection>"
        xml.reserveCapacity(itemCount * 180)

        for i in 1...itemCount {
            xml += "<items>"
            xml += "<id>\(i)</id>"
            xml += "<name>Item \(i)</name>"
            xml += "<description>Description for benchmark item number \(i) in the test fixture</description>"
            xml += "<price>\(Double(i) * 1.23)</price>"
            xml += "<active>\(i.isMultiple(of: 2) ? "true" : "false")</active>"
            xml += "</items>"
        }

        xml += "</collection>"
        return Data(xml.utf8)
    }

    func test_streamParser_largeFlatFixture_10MB_stress() throws {
        try XCTSkipUnless(shouldRunStressTests, "Set RUN_LARGE_XML_STRESS=1 to run large streaming stress tests.")

        let data = makeBenchmarkStyleXML(itemCount: 60_000)
        XCTAssertGreaterThan(data.count, 8_000_000)

        var eventCount = 0
        try XMLStreamParser().parse(data: data) { _ in
            eventCount += 1
        }

        XCTAssertGreaterThan(eventCount, 0)
    }

    func test_eventCursor_largeFlatFixture_10MB_stress() throws {
        try XCTSkipUnless(shouldRunStressTests, "Set RUN_LARGE_XML_STRESS=1 to run large streaming stress tests.")

        let data = makeBenchmarkStyleXML(itemCount: 60_000)
        XCTAssertGreaterThan(data.count, 8_000_000)

        let cursor = try XMLEventCursor(data: data)
        XCTAssertGreaterThan(cursor.count, 0)
    }

    func test_itemDecoder_largeFlatFixture_10MB_stress() throws {
        try XCTSkipUnless(shouldRunStressTests, "Set RUN_LARGE_XML_STRESS=1 to run large streaming stress tests.")

        let data = makeBenchmarkStyleXML(itemCount: 60_000)
        XCTAssertGreaterThan(data.count, 8_000_000)

        let cursor = try XMLEventCursor(data: data)
        let products = try XMLItemDecoder().decode(Product.self, itemElement: "items", from: cursor)
        XCTAssertEqual(products.count, 60_000)
    }
}
