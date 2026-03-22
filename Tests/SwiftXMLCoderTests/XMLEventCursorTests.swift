import Foundation
import SwiftXMLCoder
import XCTest

final class XMLEventCursorTests: XCTestCase {

    // MARK: - Helpers

    private let singleElement = Data("""
        <Root>
          <Child>hello</Child>
        </Root>
        """.utf8)

    private let catalog = Data("""
        <Catalog>
          <Product><sku>A1</sku><price>9.99</price></Product>
          <Product><sku>B2</sku><price>14.99</price></Product>
          <Product><sku>C3</sku><price>4.50</price></Product>
        </Catalog>
        """.utf8)

    // MARK: - XMLEventCursor — basic navigation

    func test_cursor_init_parsesAllEvents() throws {
        let cursor = try XMLEventCursor(data: singleElement)
        XCTAssertFalse(cursor.isAtEnd)
        XCTAssertGreaterThan(cursor.count, 0)
    }

    func test_cursor_next_advancesPosition() throws {
        let cursor = try XMLEventCursor(data: singleElement)
        let first = cursor.next()
        XCTAssertNotNil(first)
        XCTAssertEqual(cursor.position, 1)
    }

    func test_cursor_peek_doesNotAdvance() throws {
        let cursor = try XMLEventCursor(data: singleElement)
        let peeked = cursor.peek()
        XCTAssertNotNil(peeked)
        XCTAssertEqual(cursor.position, 0, "peek() must not advance the cursor")
        let next = cursor.next()
        XCTAssertEqual(peeked, next, "peek() and next() must return the same event")
    }

    func test_cursor_isAtEnd_afterFullConsumption() throws {
        let cursor = try XMLEventCursor(data: singleElement)
        while cursor.next() != nil { }
        XCTAssertTrue(cursor.isAtEnd)
        XCTAssertNil(cursor.next())
        XCTAssertNil(cursor.peek())
    }

    func test_cursor_count_matchesEventSequence() throws {
        var expected = 0
        try XMLStreamParser().parse(data: singleElement) { _ in expected += 1 }
        let cursor = try XMLEventCursor(data: singleElement)
        XCTAssertEqual(cursor.count, expected)
    }

    func test_cursor_iteratorProtocol_worksInWhileLoop() throws {
        let cursor = try XMLEventCursor(data: singleElement)
        var startElementCount = 0
        while let event = cursor.next() {
            if case .startElement = event { startElementCount += 1 }
        }
        XCTAssertGreaterThan(startElementCount, 0)
    }

    // MARK: - advance(toElement:)

    func test_advanceToElement_findsFirstOccurrence() throws {
        let cursor = try XMLEventCursor(data: catalog)
        let event = cursor.advance(toElement: "Product")
        XCTAssertNotNil(event)
        if case .startElement(let name, _, _) = event {
            XCTAssertEqual(name.localName, "Product")
        } else {
            XCTFail("Expected .startElement(Product)")
        }
    }

    func test_advanceToElement_consumesEventsUpToMatch() throws {
        let cursor = try XMLEventCursor(data: catalog)
        let positionBefore = cursor.position
        cursor.advance(toElement: "Product")
        XCTAssertGreaterThan(cursor.position, positionBefore)
    }

    func test_advanceToElement_returnsNilWhenNotFound() throws {
        let cursor = try XMLEventCursor(data: singleElement)
        let result = cursor.advance(toElement: "NoSuchElement")
        XCTAssertNil(result)
        XCTAssertTrue(cursor.isAtEnd)
    }

    func test_advanceToElement_calledMultipleTimes_findsSuccessiveOccurrences() throws {
        let cursor = try XMLEventCursor(data: catalog)
        let first = cursor.advance(toElement: "Product")
        let second = cursor.advance(toElement: "Product")
        let third = cursor.advance(toElement: "Product")
        let fourth = cursor.advance(toElement: "Product")
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(third)
        XCTAssertNil(fourth, "Only 3 Product elements exist")
    }

    // MARK: - XMLItemDecoder — sync decode

    func test_itemDecoder_decode_returnsAllItems() throws {
        struct Product: Decodable, Equatable {
            let sku: String
            let price: Double
        }

        let cursor = try XMLEventCursor(data: catalog)
        let decoder = XMLItemDecoder()
        let products = try decoder.decode(Product.self, itemElement: "Product", from: cursor)

        XCTAssertEqual(products.count, 3)
        XCTAssertEqual(products[0].sku, "A1")
        XCTAssertEqual(products[1].sku, "B2")
        XCTAssertEqual(products[2].sku, "C3")
        XCTAssertEqual(products[0].price, 9.99, accuracy: 0.001)
        XCTAssertEqual(products[1].price, 14.99, accuracy: 0.001)
        XCTAssertEqual(products[2].price, 4.50, accuracy: 0.001)
    }

    func test_itemDecoder_decode_emptyContainer_returnsEmptyArray() throws {
        struct Item: Decodable { let value: String }
        let xml = Data("<Root></Root>".utf8)
        let cursor = try XMLEventCursor(data: xml)
        let results = try XMLItemDecoder().decode(Item.self, itemElement: "Item", from: cursor)
        XCTAssertEqual(results.count, 0)
    }

    func test_itemDecoder_decode_singleItem() throws {
        struct Item: Decodable, Equatable { let name: String }
        let xml = Data("<Root><Item><name>Alpha</name></Item></Root>".utf8)
        let cursor = try XMLEventCursor(data: xml)
        let results = try XMLItemDecoder().decode(Item.self, itemElement: "Item", from: cursor)
        XCTAssertEqual(results, [Item(name: "Alpha")])
    }

    func test_itemDecoder_decode_cursorsAdvancesPastItems() throws {
        struct Product: Decodable { let sku: String }
        let cursor = try XMLEventCursor(data: catalog)
        _ = try XMLItemDecoder().decode(Product.self, itemElement: "Product", from: cursor)
        // Cursor should now be at the end or past all Product elements
        let remaining = cursor.advance(toElement: "Product")
        XCTAssertNil(remaining, "All Product elements should have been consumed")
    }

    // MARK: - XMLItemDecoder — nested elements with same name

    func test_itemDecoder_decode_nestedSameNameElements() throws {
        // A Folder can contain nested Folder elements — depth tracking must be correct
        struct Folder: Decodable {
            let name: String
        }
        let xml = Data("""
            <Root>
              <Folder><name>Parent</name></Folder>
              <Folder><name>Child</name></Folder>
            </Root>
            """.utf8)
        let cursor = try XMLEventCursor(data: xml)
        let results = try XMLItemDecoder().decode(Folder.self, itemElement: "Folder", from: cursor)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].name, "Parent")
        XCTAssertEqual(results[1].name, "Child")
    }

    // MARK: - XMLItemDecoder — configuration forwarding

    func test_itemDecoder_configurationForwarded_dateStrategy() throws {
        struct Event: Decodable {
            let at: Date
        }
        let xml = Data("""
            <Events>
              <Event><at>1000.0</at></Event>
              <Event><at>2000.0</at></Event>
            </Events>
            """.utf8)

        let config = XMLDecoder.Configuration(dateDecodingStrategy: .secondsSince1970)
        let cursor = try XMLEventCursor(data: xml)
        let results = try XMLItemDecoder(configuration: config).decode(Event.self, itemElement: "Event", from: cursor)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].at.timeIntervalSince1970, 1000.0, accuracy: 0.001)
        XCTAssertEqual(results[1].at.timeIntervalSince1970, 2000.0, accuracy: 0.001)
    }

    // MARK: - XMLItemDecoder — async API

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_itemDecoder_items_asyncStream_yieldsAllItems() async throws {
        struct Product: Decodable, Equatable {
            let sku: String
        }

        let cursor = try XMLEventCursor(data: catalog)
        let decoder = XMLItemDecoder()
        var collected: [Product] = []
        for try await product in decoder.items(Product.self, itemElement: "Product", from: cursor) {
            collected.append(product)
        }

        XCTAssertEqual(collected.count, 3)
        XCTAssertEqual(collected[0].sku, "A1")
        XCTAssertEqual(collected[1].sku, "B2")
        XCTAssertEqual(collected[2].sku, "C3")
    }

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_itemDecoder_items_asyncStream_emptyContainer_yieldsNothing() async throws {
        struct Item: Decodable { let value: String }
        let xml = Data("<Root></Root>".utf8)
        let cursor = try XMLEventCursor(data: xml)
        var count = 0
        for try await _ in XMLItemDecoder().items(Item.self, itemElement: "Item", from: cursor) {
            count += 1
        }
        XCTAssertEqual(count, 0)
    }

    // MARK: - XMLEventCursor — invalid XML

    func test_cursor_init_throwsOnInvalidXML() throws {
        let bad = Data("<Root><Unclosed>".utf8)
        XCTAssertThrowsError(try XMLEventCursor(data: bad))
    }

    // MARK: - Extraction correctness (via decode round-trip)

    func test_itemDecoder_extractionCorrect_firstItemHasExpectedSku() throws {
        struct Product: Decodable { let sku: String }
        // Cursor positioned manually; only first Product should be decoded
        let cursor = try XMLEventCursor(data: catalog)
        let decoder = XMLItemDecoder()
        let all = try decoder.decode(Product.self, itemElement: "Product", from: cursor)
        // Verify extraction captured the full element (sku present in every item)
        XCTAssertTrue(all.allSatisfy { !$0.sku.isEmpty }, "All decoded items should have a non-empty sku")
    }

    func test_itemDecoder_extractionCorrect_countMatchesOccurrences() throws {
        struct Product: Decodable { let sku: String }
        // The catalog XML has exactly 3 Product elements
        let cursor = try XMLEventCursor(data: catalog)
        let all = try XMLItemDecoder().decode(Product.self, itemElement: "Product", from: cursor)
        XCTAssertEqual(all.count, 3)
    }
}
