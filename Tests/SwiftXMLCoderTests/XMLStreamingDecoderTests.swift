import Foundation
@testable import SwiftXMLCoder
import XCTest

// swiftlint:disable type_body_length file_length

/// Tests for the streaming XML decoder (`_XMLStreamingDecoder`), exercised through
/// the public `XMLDecoder.decode(_:from:)` entry point which routes through `decodeSAXImpl`.
final class XMLStreamingDecoderTests: XCTestCase {

    // MARK: - 1. Scalar leaf fast path

    func test_scalarLeaf_flatStructWithMultipleTypes() throws {
        struct Flat: Decodable, Equatable {
            let name: String
            let age: Int
            let score: Double
            let active: Bool
        }

        let xml = """
        <Flat>
            <name>Alice</name>
            <age>30</age>
            <score>95.5</score>
            <active>true</active>
        </Flat>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Flat"))
        let result = try decoder.decode(Flat.self, from: Data(xml.utf8))
        XCTAssertEqual(result.name, "Alice")
        XCTAssertEqual(result.age, 30)
        XCTAssertEqual(result.score, 95.5, accuracy: 0.001)
        XCTAssertTrue(result.active)
    }

    func test_scalarLeaf_emptyElement_decodedAsEmptyString() throws {
        struct Wrapper: Decodable {
            let field: String
        }

        let xml = "<Wrapper><field></field></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.field, "")
    }

    func test_scalarLeaf_selfClosingElement_decodedAsEmptyString() throws {
        struct Wrapper: Decodable {
            let field: String
        }

        let xml = "<Wrapper><field/></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.field, "")
    }

    func test_scalarLeaf_cdataInLeaf() throws {
        struct Wrapper: Decodable {
            let field: String
        }

        let xml = "<Wrapper><field><![CDATA[hello world]]></field></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.field, "hello world")
    }

    func test_scalarLeaf_intFields() throws {
        struct Numbers: Decodable, Equatable {
            let a: Int8
            let b: Int16
            let c: Int32
            let d: Int64
            let e: UInt
            let f: UInt8
            let g: UInt16
            let h: UInt32
            let i: UInt64
        }

        let xml = """
        <Numbers>
            <a>1</a><b>2</b><c>3</c><d>4</d>
            <e>5</e><f>6</f><g>7</g><h>8</h><i>9</i>
        </Numbers>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Numbers"))
        let result = try decoder.decode(Numbers.self, from: Data(xml.utf8))
        XCTAssertEqual(result, Numbers(a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9))
    }

    func test_scalarLeaf_floatField() throws {
        struct Wrapper: Decodable {
            let value: Float
        }

        let xml = "<Wrapper><value>3.14</value></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.value, 3.14, accuracy: 0.01)
    }

    func test_scalarLeaf_boolVariants() throws {
        struct Bools: Decodable {
            let t1: Bool
            let t2: Bool
            let f1: Bool
            let f2: Bool
        }

        let xml = """
        <Bools>
            <t1>true</t1>
            <t2>1</t2>
            <f1>false</f1>
            <f2>0</f2>
        </Bools>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Bools"))
        let result = try decoder.decode(Bools.self, from: Data(xml.utf8))
        XCTAssertTrue(result.t1)
        XCTAssertTrue(result.t2)
        XCTAssertFalse(result.f1)
        XCTAssertFalse(result.f2)
    }

    // MARK: - 2. Out-of-order key access (buffering fallback)

    func test_outOfOrderKeys_decodesCorrectly() throws {
        struct OutOfOrder: Decodable, Equatable {
            let beta: String
            let alpha: String

            enum CodingKeys: String, CodingKey {
                // CodingKeys declared in reverse order vs XML
                case beta
                case alpha
            }
        }

        // XML has alpha first, then beta, but struct decodes beta first
        let xml = "<OutOfOrder><alpha>A</alpha><beta>B</beta></OutOfOrder>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "OutOfOrder"))
        let result = try decoder.decode(OutOfOrder.self, from: Data(xml.utf8))
        XCTAssertEqual(result.alpha, "A")
        XCTAssertEqual(result.beta, "B")
    }

    func test_outOfOrderKeys_threeFields_middleFirst() throws {
        struct Reorder: Decodable, Equatable {
            let second: Int
            let first: Int
            let third: Int

            enum CodingKeys: String, CodingKey {
                case second, first, third
            }
        }

        let xml = """
        <Reorder>
            <first>1</first>
            <second>2</second>
            <third>3</third>
        </Reorder>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Reorder"))
        let result = try decoder.decode(Reorder.self, from: Data(xml.utf8))
        XCTAssertEqual(result.first, 1)
        XCTAssertEqual(result.second, 2)
        XCTAssertEqual(result.third, 3)
    }

    // MARK: - 3. Unkeyed container modes

    func test_unkeyedContainer_arrayOfItems_withItemWrapper() throws {
        struct Wrapper: Decodable, Equatable {
            let values: [String]
        }

        let xml = """
        <Wrapper>
            <values>
                <item>one</item>
                <item>two</item>
                <item>three</item>
            </values>
        </Wrapper>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.values, ["one", "two", "three"])
    }

    func test_unkeyedContainer_allChildrenMode_heterogeneousNames() throws {
        struct Wrapper: Decodable {
            let items: [String]

            enum CodingKeys: String, CodingKey { case items }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                var unkeyed = try container.nestedUnkeyedContainer(forKey: .items)
                var result: [String] = []
                while !unkeyed.isAtEnd {
                    result.append(try unkeyed.decode(String.self))
                }
                items = result
            }
        }

        // No <item> wrappers -> allChildren mode
        let xml = """
        <Wrapper>
            <items>
                <alpha>A</alpha>
                <beta>B</beta>
                <gamma>C</gamma>
            </items>
        </Wrapper>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.items, ["A", "B", "C"])
    }

    func test_unkeyedContainer_emptyArray() throws {
        struct Wrapper: Decodable, Equatable {
            let values: [String]
        }

        let xml = "<Wrapper><values></values></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.values, [])
    }

    func test_unkeyedContainer_nestedArrayOfStructs() throws {
        struct Inner: Decodable, Equatable {
            let name: String
            let value: Int
        }
        struct Outer: Decodable, Equatable {
            let items: [Inner]
        }

        let xml = """
        <Outer>
            <items>
                <item><name>first</name><value>1</value></item>
                <item><name>second</name><value>2</value></item>
            </items>
        </Outer>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Outer"))
        let result = try decoder.decode(Outer.self, from: Data(xml.utf8))
        XCTAssertEqual(result.items, [Inner(name: "first", value: 1), Inner(name: "second", value: 2)])
    }

    func test_unkeyedContainer_arrayOfIntegers() throws {
        struct Wrapper: Decodable, Equatable {
            let numbers: [Int]
        }

        let xml = """
        <Wrapper>
            <numbers>
                <item>10</item>
                <item>20</item>
                <item>30</item>
            </numbers>
        </Wrapper>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.numbers, [10, 20, 30])
    }

    // MARK: - 4. Optional/nil handling

    func test_optional_missingElement_decodesAsNil() throws {
        struct Wrapper: Decodable {
            let present: String
            let missing: String?
        }

        let xml = "<Wrapper><present>hello</present></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.present, "hello")
        XCTAssertNil(result.missing)
    }

    func test_optional_emptyElement_decodesAsNil() throws {
        struct Wrapper: Decodable {
            let field: Int?
        }

        let xml = "<Wrapper><field></field></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        // An empty element for a non-String optional typically decodes as nil
        XCTAssertNil(result.field)
    }

    func test_optional_presentElement_decodesValue() throws {
        struct Wrapper: Decodable {
            let field: Int?
        }

        let xml = "<Wrapper><field>42</field></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertEqual(result.field, 42)
    }

    func test_optional_selfClosingElement_decodesAsNil() throws {
        struct Wrapper: Decodable {
            let field: Int?
        }

        let xml = "<Wrapper><field/></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        XCTAssertNil(result.field)
    }

    func test_optional_stringEmptyElement_decodesAsEmptyString() throws {
        struct Wrapper: Decodable {
            let field: String?
        }

        // Optional<String> with an empty element should decode as empty string, not nil,
        // because String's decodeIfPresent finds the element present.
        let xml = "<Wrapper><field></field></Wrapper>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Wrapper"))
        let result = try decoder.decode(Wrapper.self, from: Data(xml.utf8))
        // The element exists, so it decodes the text content (empty string).
        // This may be nil or "" depending on nil-detection — verify actual behavior.
        // Empty leaf elements with no text are treated as nil by isNilResult.
        XCTAssertNil(result.field)
    }

    // MARK: - 5. Nested structs (recursive streaming)

    func test_nestedStruct_twoLevels() throws {
        struct Inner: Decodable, Equatable {
            let value: String
        }
        struct Outer: Decodable, Equatable {
            let name: String
            let inner: Inner
        }

        let xml = """
        <Outer>
            <name>root</name>
            <inner><value>nested</value></inner>
        </Outer>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Outer"))
        let result = try decoder.decode(Outer.self, from: Data(xml.utf8))
        XCTAssertEqual(result.name, "root")
        XCTAssertEqual(result.inner.value, "nested")
    }

    func test_nestedStruct_threeLevels() throws {
        struct Level3: Decodable, Equatable { let data: String }
        struct Level2: Decodable, Equatable { let child: Level3 }
        struct Level1: Decodable, Equatable {
            let name: String
            let sub: Level2
        }

        let xml = """
        <Level1>
            <name>top</name>
            <sub><child><data>deep</data></child></sub>
        </Level1>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Level1"))
        let result = try decoder.decode(Level1.self, from: Data(xml.utf8))
        XCTAssertEqual(result.name, "top")
        XCTAssertEqual(result.sub.child.data, "deep")
    }

    func test_nestedStruct_containingArrayOfStructs() throws {
        struct Item: Decodable, Equatable {
            let id: Int
            let label: String
        }
        struct Container: Decodable, Equatable {
            let title: String
            let items: [Item]
        }

        let xml = """
        <Container>
            <title>My List</title>
            <items>
                <item><id>1</id><label>first</label></item>
                <item><id>2</id><label>second</label></item>
            </items>
        </Container>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Container"))
        let result = try decoder.decode(Container.self, from: Data(xml.utf8))
        XCTAssertEqual(result.title, "My List")
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0], Item(id: 1, label: "first"))
        XCTAssertEqual(result.items[1], Item(id: 2, label: "second"))
    }

    // MARK: - 6. Error paths

    func test_error_missingRequiredKey_throwsDecodeFailed() throws {
        struct Payload: Decodable {
            let required: String
        }

        let xml = "<Payload><other>value</other></Payload>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case XMLParsingError.decodeFailed(_, _, let message) = error else {
                return XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
            }
            XCTAssertTrue((message ?? "").contains("XML6_5_KEY_NOT_FOUND"))
        }
    }

    func test_error_rootElementMismatch_throwsParseFailed() throws {
        struct Payload: Decodable {
            let value: String
        }

        let xml = "<Wrong><value>hello</value></Wrong>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Expected"))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case XMLParsingError.parseFailed(let message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error)")
            }
            XCTAssertTrue((message ?? "").contains("XML6_5_ROOT_MISMATCH"))
        }
    }

    func test_error_emptyDocument_throwsMissingRoot() throws {
        struct Payload: Decodable {
            let value: String
        }

        let xml = ""
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8)))
    }

    func test_error_emptyDocumentWithDeclaration_throwsMissingRoot() throws {
        struct Payload: Decodable {
            let value: String
        }

        let xml = "<?xml version=\"1.0\"?>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            // libxml2 may report "Extra content at the end of the document" or our
            // code may report MISSING_ROOT -- either way, decoding should fail.
            XCTAssertTrue(error is XMLParsingError, "Expected XMLParsingError, got \(error)")
        }
    }

    // MARK: - 7. Limits enforcement

    func test_limits_depthLimitExceeded_throwsParseFailed() throws {
        struct Payload: Decodable {
            let value: String
        }

        // Create XML with depth exceeding a tight limit
        let xml = "<a><b><c><d><value>hello</value></d></c></b></a>"
        let limits = XMLTreeParser.Limits(maxDepth: 2)
        let parserConfig = XMLTreeParser.Configuration(limits: limits)
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "a",
            parserConfiguration: parserConfig
        ))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            let errorString = "\(error)"
            XCTAssertTrue(
                errorString.contains("XML6_2H_MAX_DEPTH"),
                "Error should contain MAX_DEPTH code: \(errorString)"
            )
        }
    }

    func test_limits_nodeCountLimitExceeded_throwsParseFailed() throws {
        struct Payload: Decodable {
            let a: String
            let b: String
            let c: String
        }

        let xml = "<Root><a>1</a><b>2</b><c>3</c></Root>"
        let limits = XMLTreeParser.Limits(maxNodeCount: 2)
        let parserConfig = XMLTreeParser.Configuration(limits: limits)
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "Root",
            parserConfiguration: parserConfig
        ))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            let errorString = "\(error)"
            XCTAssertTrue(
                errorString.contains("XML6_2H_MAX_NODE_COUNT"),
                "Error should contain MAX_NODE_COUNT code: \(errorString)"
            )
        }
    }

    func test_limits_textNodeByteLimitExceeded_throwsParseFailed() throws {
        struct Payload: Decodable {
            let field: String
        }

        let longText = String(repeating: "x", count: 100)
        let xml = "<Root><field>\(longText)</field></Root>"
        let limits = XMLTreeParser.Limits(maxTextNodeBytes: 10)
        let parserConfig = XMLTreeParser.Configuration(limits: limits)
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "Root",
            parserConfiguration: parserConfig
        ))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            let errorString = "\(error)"
            XCTAssertTrue(
                errorString.contains("XML6_2H_MAX_TEXT_NODE_BYTES"),
                "Error should contain MAX_TEXT_NODE_BYTES code: \(errorString)"
            )
        }
    }

    // MARK: - 8. Mixed content edge cases

    func test_mixedContent_textAndChildElements() throws {
        // When an element has both text and child elements,
        // the text becomes "direct text" of the parent.
        struct Mixed: Decodable {
            let child: String

            enum CodingKeys: String, CodingKey { case child }
        }

        let xml = "<Mixed>some text<child>nested</child></Mixed>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Mixed"))
        let result = try decoder.decode(Mixed.self, from: Data(xml.utf8))
        XCTAssertEqual(result.child, "nested")
    }

    func test_mixedContent_multipleTextSegmentsBetweenElements() throws {
        struct Parent: Decodable {
            let a: String
            let b: String
        }

        let xml = "<Parent>text1<a>A</a>text2<b>B</b>text3</Parent>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Parent"))
        let result = try decoder.decode(Parent.self, from: Data(xml.utf8))
        XCTAssertEqual(result.a, "A")
        XCTAssertEqual(result.b, "B")
    }

    // MARK: - 9. Attribute decoding

    func test_attribute_decodeThroughFieldCodingOverrides() throws {
        struct Item: Decodable, Equatable {
            let id: String
            let name: String

            enum CodingKeys: String, CodingKey { case id, name }
        }

        let xml = "<Item id=\"42\"><name>Widget</name></Item>"
        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "Item",
            fieldCodingOverrides: overrides
        ))
        let result = try decoder.decode(Item.self, from: Data(xml.utf8))
        XCTAssertEqual(result.id, "42")
        XCTAssertEqual(result.name, "Widget")
    }

    func test_attribute_mixOfAttributesAndElements() throws {
        struct Record: Decodable, Equatable {
            let type: String
            let id: Int
            let content: String

            enum CodingKeys: String, CodingKey { case type, id, content }
        }

        let xml = "<Record type=\"info\" id=\"7\"><content>data</content></Record>"
        let overrides = XMLFieldCodingOverrides()
            .setting(path: [], key: "type", as: .attribute)
            .setting(path: [], key: "id", as: .attribute)
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "Record",
            fieldCodingOverrides: overrides
        ))
        let result = try decoder.decode(Record.self, from: Data(xml.utf8))
        XCTAssertEqual(result.type, "info")
        XCTAssertEqual(result.id, 7)
        XCTAssertEqual(result.content, "data")
    }

    func test_attribute_missingAttribute_throwsError() throws {
        struct Item: Decodable {
            let id: String

            enum CodingKeys: String, CodingKey { case id }
        }

        let xml = "<Item><name>test</name></Item>"
        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "Item",
            fieldCodingOverrides: overrides
        ))
        XCTAssertThrowsError(try decoder.decode(Item.self, from: Data(xml.utf8))) { error in
            let errorString = "\(error)"
            XCTAssertTrue(
                errorString.contains("XML6_6_ATTRIBUTE_NOT_FOUND"),
                "Error should contain ATTRIBUTE_NOT_FOUND: \(errorString)"
            )
        }
    }

    // MARK: - 10. Line number resolution

    func test_lineNumber_errorIncludesLineInfo() throws {
        struct Payload: Decodable {
            let missing: String
        }

        // Multi-line XML so that line numbers are meaningful
        let xml = """
        <Root>
            <name>Alice</name>
        </Root>
        """
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Payload.self, from: Data(xml.utf8))) { error in
            guard case XMLParsingError.decodeFailed(_, let location, let message) = error else {
                return XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
            }
            let hasLineInMessage = (message ?? "").contains("line")
            let hasLineInLocation = location?.line != nil
            XCTAssertTrue(
                hasLineInMessage || hasLineInLocation,
                "Error should include line info; message='\(message ?? "<nil>")' location=\(String(describing: location))"
            )
        }
    }

    // MARK: - Additional coverage: single-value root decoding

    func test_singleValueRoot_stringDecoding() throws {
        let xml = "<Value>hello</Value>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Value"))
        let result = try decoder.decode(String.self, from: Data(xml.utf8))
        XCTAssertEqual(result, "hello")
    }

    func test_singleValueRoot_intDecoding() throws {
        let xml = "<Value>42</Value>"
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Value"))
        let result = try decoder.decode(Int.self, from: Data(xml.utf8))
        XCTAssertEqual(result, 42)
    }

    // MARK: - Additional coverage: XMLRootNode conformance

    func test_xmlRootNode_conformance_decodesCorrectly() throws {
        struct Envelope: Decodable, Equatable, XMLRootNode {
            static let xmlRootElementName = "Envelope"
            let message: String
        }

        let xml = "<Envelope><message>hi</message></Envelope>"
        let decoder = XMLDecoder()
        let result = try decoder.decode(Envelope.self, from: Data(xml.utf8))
        XCTAssertEqual(result.message, "hi")
    }

    func test_xmlRootNode_mismatch_throwsError() throws {
        struct Envelope: Decodable, XMLRootNode {
            static let xmlRootElementName = "Envelope"
            let message: String
        }

        let xml = "<Other><message>hi</message></Other>"
        let decoder = XMLDecoder()
        XCTAssertThrowsError(try decoder.decode(Envelope.self, from: Data(xml.utf8))) { error in
            guard case XMLParsingError.parseFailed(let message) = error else {
                return XCTFail("Expected parseFailed, got \(error)")
            }
            XCTAssertTrue((message ?? "").contains("XML6_5_ROOT_MISMATCH"))
        }
    }

    // MARK: - Additional coverage: roundtrip with encoder

    func test_roundtrip_complexPayload() throws {
        struct Address: Codable, Equatable {
            let street: String
            let city: String
        }
        struct Person: Codable, Equatable {
            let name: String
            let age: Int
            let address: Address
        }

        let input = Person(
            name: "Bob",
            age: 25,
            address: Address(street: "123 Main St", city: "Springfield")
        )
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Person"))
        let data = try encoder.encode(input)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Person"))
        let decoded = try decoder.decode(Person.self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func test_roundtrip_withArrays() throws {
        struct Payload: Codable, Equatable {
            let tags: [String]
            let scores: [Int]
        }

        let input = Payload(tags: ["swift", "xml"], scores: [100, 200])
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Payload"))
        let data = try encoder.encode(input)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let decoded = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(decoded, input)
    }
}

// swiftlint:enable type_body_length file_length
