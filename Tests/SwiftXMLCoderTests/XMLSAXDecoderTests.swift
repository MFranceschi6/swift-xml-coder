import Foundation
@testable import SwiftXMLCoder
import XCTest

final class XMLSAXDecoderTests: XCTestCase {

    private func makeBuffer(_ events: [XMLStreamEvent], _ lines: [Int?]? = nil) -> _XMLEventBuffer {
        let lineTable = lines.map { _LazyLineTable(prebuilt: ContiguousArray($0)) }
        return _XMLEventBuffer(events: ContiguousArray(events), lineTable: lineTable)
    }

    func test_eventBuffer_findRootElement_returnsRootSpan() throws {
        let rootName = XMLQualifiedName(localName: "Root")
        let childName = XMLQualifiedName(localName: "Child")
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .comment("before"),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .startElement(name: childName, attributes: [], namespaceDeclarations: []),
            .endElement(name: childName),
            .endElement(name: rootName),
            .endDocument
        ]
        let buffer = makeBuffer(events)
        let root = try buffer.findRootElement()
        XCTAssertEqual(root.start, 2)
        XCTAssertEqual(root.end, 5)
    }

    func test_eventBuffer_childElementSpans_returnsDirectChildrenOnly() {
        let rootName = XMLQualifiedName(localName: "Root")
        let aName = XMLQualifiedName(localName: "A")
        let bName = XMLQualifiedName(localName: "B")
        let nestedName = XMLQualifiedName(localName: "Nested")
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []), // 1
            .startElement(name: aName, attributes: [], namespaceDeclarations: []),    // 2
            .startElement(name: nestedName, attributes: [], namespaceDeclarations: []), // 3
            .endElement(name: nestedName),                                             // 4
            .endElement(name: aName),                                                  // 5
            .startElement(name: bName, attributes: [], namespaceDeclarations: []),     // 6
            .endElement(name: bName),                                                  // 7
            .endElement(name: rootName),                                               // 8
            .endDocument
        ]
        let buffer = makeBuffer(events)
        let spans = buffer.childElementSpans(from: 1, to: 8)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].name.localName, "A")
        XCTAssertEqual(spans[0].start, 2)
        XCTAssertEqual(spans[0].end, 5)
        XCTAssertEqual(spans[1].name.localName, "B")
        XCTAssertEqual(spans[1].start, 6)
        XCTAssertEqual(spans[1].end, 7)
    }

    func test_eventBuffer_lexicalText_concatenatesDirectTextAndCDATA() {
        let rootName = XMLQualifiedName(localName: "Root")
        let childName = XMLQualifiedName(localName: "Child")
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []), // 1
            .text(" hello "),
            .cdata("world"),
            .startElement(name: childName, attributes: [], namespaceDeclarations: []),
            .text("ignored"),
            .endElement(name: childName),
            .text(" !"),
            .endElement(name: rootName), // 8
            .endDocument
        ]
        let buffer = makeBuffer(events)
        XCTAssertEqual(buffer.lexicalText(from: 1, to: 8), " hello world !")
    }

    func test_eventBuffer_isNilSpan_trueOnlyWhenNoChildrenAndNoLexicalContent() {
        let rootName = XMLQualifiedName(localName: "Root")
        let childName = XMLQualifiedName(localName: "Child")

        let emptyEvents: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .text("   \n"),
            .endElement(name: rootName),
            .endDocument
        ]
        XCTAssertTrue(makeBuffer(emptyEvents).isNilSpan(from: 1, to: 3))

        let withChildEvents: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .startElement(name: childName, attributes: [], namespaceDeclarations: []),
            .endElement(name: childName),
            .endElement(name: rootName),
            .endDocument
        ]
        XCTAssertFalse(makeBuffer(withChildEvents).isNilSpan(from: 1, to: 4))
    }

    func test_eventBuffer_lineNumberAt_returnsStoredLine() {
        let rootName = XMLQualifiedName(localName: "Root")
        let events: [XMLStreamEvent] = [
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: rootName, attributes: [], namespaceDeclarations: []),
            .endElement(name: rootName),
            .endDocument
        ]
        let lines: [Int?] = [nil, 12, 12, nil]
        let buffer = makeBuffer(events, lines)
        XCTAssertEqual(buffer.lineNumberAt(1), 12)
        XCTAssertEqual(buffer.lineNumberAt(2), 12)
        XCTAssertNil(buffer.lineNumberAt(0))
        XCTAssertNil(buffer.lineNumberAt(99))
    }

    func test_eventBuffer_findRootElement_missingRoot_throws() {
        let buffer = makeBuffer([.startDocument(version: nil, encoding: nil, standalone: nil), .endDocument])
        XCTAssertThrowsError(try buffer.findRootElement()) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_MISSING_ROOT"))
        }
    }

    func test_eventBuffer_findRootElement_unbalancedStart_throws() {
        let root = XMLQualifiedName(localName: "Root")
        let buffer = makeBuffer([
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: root, attributes: [], namespaceDeclarations: []),
            .endDocument
        ])
        XCTAssertThrowsError(try buffer.findRootElement()) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_UNBALANCED_START"))
        }
    }

    func test_eventBuffer_elementEndIndex_and_attributesAt_coverHelpers() {
        let root = XMLQualifiedName(localName: "Root")
        let child = XMLQualifiedName(localName: "Child")
        let attrs = [XMLTreeAttribute(name: XMLQualifiedName(localName: "id"), value: "42")]
        let buffer = makeBuffer([
            .startDocument(version: nil, encoding: nil, standalone: nil),
            .startElement(name: root, attributes: attrs, namespaceDeclarations: []), // 1
            .startElement(name: child, attributes: [], namespaceDeclarations: []),   // 2
            .endElement(name: child), // 3
            .endElement(name: root),  // 4
            .endDocument
        ])

        XCTAssertEqual(buffer.elementEndIndex(from: 1), 4)
        XCTAssertEqual(buffer.elementEndIndex(from: 2), 3)
        XCTAssertNil(buffer.elementEndIndex(from: 0))
        XCTAssertNil(buffer.elementEndIndex(from: 99))
        XCTAssertEqual(buffer.attributesAt(1).count, 1)
        XCTAssertEqual(buffer.attributesAt(1).first?.value, "42")
        XCTAssertTrue(buffer.attributesAt(2).isEmpty)
    }

    private func makeSAXDecoder(
        xml: String,
        configuration: XMLDecoder.Configuration = .init(rootElementName: "Root")
    ) throws -> _XMLSAXDecoder {
        var events: [XMLStreamEvent] = []
        var lines: [Int?] = []
        let parser = XMLStreamParser(configuration: configuration.parserConfiguration)
        try parser.parseSAX(
            data: Data(xml.utf8),
            onEvent: { events.append($0) },
            onEventWithLine: { _, line in lines.append(line) }
        )

        let lineTable = _LazyLineTable(prebuilt: ContiguousArray(lines))
        let buffer = _XMLEventBuffer(events: ContiguousArray(events), lineTable: lineTable)
        let root = try buffer.findRootElement()
        let options = _XMLDecoderOptions(configuration: configuration)
        return _XMLSAXDecoder(
            options: options,
            buffer: buffer,
            start: root.start,
            end: root.end,
            codingPath: []
        )
    }

    func test_saxDecoder_userInfo_contains_nested_unkeyed_and_superDecoder_paths() throws {
        struct Payload: Decodable {
            let value: String

            enum CodingKeys: String, CodingKey {
                case value
                case nested
                case values
                case missing
            }

            enum NestedKeys: String, CodingKey { case inner }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = container.allKeys
                _ = container.contains(.value)
                _ = try container.decodeNil(forKey: .missing)
                value = try container.decode(String.self, forKey: .value)

                let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nested)
                _ = try nested.decode(String.self, forKey: .inner)

                var unkeyed = try container.nestedUnkeyedContainer(forKey: .values)
                _ = unkeyed.count
                _ = unkeyed.isAtEnd
                _ = try unkeyed.decode(String.self)
                _ = try unkeyed.decode(String.self)
                _ = unkeyed.isAtEnd

                _ = try container.superDecoder()
                _ = try container.superDecoder(forKey: .nested)
            }
        }

        let key = try XCTUnwrap(CodingUserInfoKey(rawValue: "probe-key"))
        let config = XMLDecoder.Configuration(rootElementName: "Root", userInfo: [key: "probe-value"])
        let decoder = try makeSAXDecoder(
            xml: "<Root><value>ok</value><nested><inner>x</inner></nested><values><item>a</item><item>b</item></values></Root>",
            configuration: config
        )

        XCTAssertEqual(decoder.userInfo[key] as? String, "probe-value")
        let payload = try Payload(from: decoder)
        XCTAssertEqual(payload.value, "ok")
    }

    func test_saxDecoder_typed_numeric_decode_paths() throws {
        struct NumericPayload: Decodable {
            enum CodingKeys: String, CodingKey {
                case bool, double, float, int, int8, int16, int32, int64, uint, uint8, uint16, uint32, uint64
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                _ = try c.decode(Bool.self, forKey: .bool)
                _ = try c.decode(Double.self, forKey: .double)
                _ = try c.decode(Float.self, forKey: .float)
                _ = try c.decode(Int.self, forKey: .int)
                _ = try c.decode(Int8.self, forKey: .int8)
                _ = try c.decode(Int16.self, forKey: .int16)
                _ = try c.decode(Int32.self, forKey: .int32)
                _ = try c.decode(Int64.self, forKey: .int64)
                _ = try c.decode(UInt.self, forKey: .uint)
                _ = try c.decode(UInt8.self, forKey: .uint8)
                _ = try c.decode(UInt16.self, forKey: .uint16)
                _ = try c.decode(UInt32.self, forKey: .uint32)
                _ = try c.decode(UInt64.self, forKey: .uint64)
            }
        }

        let xml = """
        <Root>
            <bool>true</bool>
            <double>1.5</double>
            <float>2.5</float>
            <int>3</int>
            <int8>4</int8>
            <int16>5</int16>
            <int32>6</int32>
            <int64>7</int64>
            <uint>8</uint>
            <uint8>9</uint8>
            <uint16>10</uint16>
            <uint32>11</uint32>
            <uint64>12</uint64>
        </Root>
        """
        let decoder = try makeSAXDecoder(xml: xml)
        _ = try NumericPayload(from: decoder)
    }

    func test_saxDecoder_attribute_nestedContainer_unsupported_throws() throws {
        struct BadNested: Decodable {
            enum CodingKeys: String, CodingKey { case id }
            enum InnerKeys: String, CodingKey { case x }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.nestedContainer(keyedBy: InnerKeys.self, forKey: .id)
            }
        }

        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let config = XMLDecoder.Configuration(rootElementName: "Root", fieldCodingOverrides: overrides)
        let decoder = try makeSAXDecoder(xml: "<Root id='1'></Root>", configuration: config)

        XCTAssertThrowsError(try BadNested(from: decoder)) { error in
            XCTAssertTrue("\(error)".contains("XML6_6_ATTRIBUTE_NESTED_UNSUPPORTED"))
        }
    }

    func test_saxDecoder_attribute_nestedUnkeyedContainer_unsupported_throws() throws {
        struct BadNested: Decodable {
            enum CodingKeys: String, CodingKey { case id }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.nestedUnkeyedContainer(forKey: .id)
            }
        }

        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let config = XMLDecoder.Configuration(rootElementName: "Root", fieldCodingOverrides: overrides)
        let decoder = try makeSAXDecoder(xml: "<Root id='1'></Root>", configuration: config)

        XCTAssertThrowsError(try BadNested(from: decoder)) { error in
            XCTAssertTrue("\(error)".contains("XML6_6_ATTRIBUTE_NESTED_UNSUPPORTED"))
        }
    }

    func test_saxDecoder_unkeyed_typed_and_nested_paths_cover_remaining_entrypoints() throws {
        struct Payload: Decodable {
            enum CodingKeys: String, CodingKey { case items }
            enum NestedKeys: String, CodingKey { case inner }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                var list = try container.nestedUnkeyedContainer(forKey: .items)

                XCTAssertEqual(list.count, 18)
                XCTAssertTrue(try list.decodeNil())
                XCTAssertEqual(try list.decode(Bool.self), true)
                XCTAssertEqual(try list.decode(String.self), "s")
                XCTAssertEqual(try list.decode(Double.self), 1.5, accuracy: 0.000_001)
                XCTAssertEqual(try list.decode(Float.self), Float(2.5), accuracy: 0.000_001)
                XCTAssertEqual(try list.decode(Int.self), 3)
                XCTAssertEqual(try list.decode(Int8.self), 4)
                XCTAssertEqual(try list.decode(Int16.self), 5)
                XCTAssertEqual(try list.decode(Int32.self), 6)
                XCTAssertEqual(try list.decode(Int64.self), 7)
                XCTAssertEqual(try list.decode(UInt.self), 8)
                XCTAssertEqual(try list.decode(UInt8.self), 9)
                XCTAssertEqual(try list.decode(UInt16.self), 10)
                XCTAssertEqual(try list.decode(UInt32.self), 11)
                XCTAssertEqual(try list.decode(UInt64.self), 12)

                let nested = try list.nestedContainer(keyedBy: NestedKeys.self)
                XCTAssertEqual(try nested.decode(String.self, forKey: .inner), "v")

                var nestedList = try list.nestedUnkeyedContainer()
                XCTAssertEqual(try nestedList.decode(String.self), "x")
                XCTAssertEqual(try nestedList.decode(String.self), "y")
                XCTAssertTrue(nestedList.isAtEnd)

                let superDecoder = try list.superDecoder()
                let superContainer = try superDecoder.container(keyedBy: NestedKeys.self)
                XCTAssertEqual(try superContainer.decode(String.self, forKey: .inner), "sup")
                XCTAssertTrue(list.isAtEnd)

                XCTAssertThrowsError(try list.decode(Int.self)) { error in
                    XCTAssertTrue("\(error)".contains("XML6_5_UNKEYED_OUT_OF_RANGE"))
                }
            }
        }

        let xml = """
        <Root>
          <items>
            <item></item>
            <item>true</item>
            <item>s</item>
            <item>1.5</item>
            <item>2.5</item>
            <item>3</item>
            <item>4</item>
            <item>5</item>
            <item>6</item>
            <item>7</item>
            <item>8</item>
            <item>9</item>
            <item>10</item>
            <item>11</item>
            <item>12</item>
            <item><inner>v</inner></item>
            <item><item>x</item><item>y</item></item>
            <item><inner>sup</inner></item>
          </items>
        </Root>
        """

        let decoder = try makeSAXDecoder(xml: xml)
        _ = try Payload(from: decoder)
    }

    func test_saxDecoder_singleValue_typed_paths() throws {
        func scalarDecoder(xml: String) throws -> _XMLSAXDecoder {
            try makeSAXDecoder(xml: xml, configuration: .init(rootElementName: "value"))
        }

        do {
            let decoder = try scalarDecoder(xml: "<value>true</value>")
            let container = try decoder.singleValueContainer()
            XCTAssertEqual(try container.decode(Bool.self), true)
        }
        do {
            let decoder = try scalarDecoder(xml: "<value>hello</value>")
            let container = try decoder.singleValueContainer()
            XCTAssertEqual(try container.decode(String.self), "hello")
        }
        do {
            let decoder = try scalarDecoder(xml: "<value>1.5</value>")
            let container = try decoder.singleValueContainer()
            XCTAssertEqual(try container.decode(Double.self), 1.5, accuracy: 0.000_001)
        }
        do {
            let decoder = try scalarDecoder(xml: "<value>2.5</value>")
            let container = try decoder.singleValueContainer()
            XCTAssertEqual(try container.decode(Float.self), Float(2.5), accuracy: 0.000_001)
        }
        do {
            let decoder = try scalarDecoder(xml: "<value>3</value>")
            let container = try decoder.singleValueContainer()
            XCTAssertEqual(try container.decode(Int.self), 3)
            XCTAssertEqual(try container.decode(Int8.self), 3)
            XCTAssertEqual(try container.decode(Int16.self), 3)
            XCTAssertEqual(try container.decode(Int32.self), 3)
            XCTAssertEqual(try container.decode(Int64.self), 3)
            XCTAssertEqual(try container.decode(UInt.self), 3)
            XCTAssertEqual(try container.decode(UInt8.self), 3)
            XCTAssertEqual(try container.decode(UInt16.self), 3)
            XCTAssertEqual(try container.decode(UInt32.self), 3)
            XCTAssertEqual(try container.decode(UInt64.self), 3)
        }
    }

    func test_saxDecoder_error_paths_for_missing_keys_and_parse_failures() throws {
        struct MissingDecode: Decodable {
            enum CodingKeys: String, CodingKey { case present, missing }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.decode(String.self, forKey: .present)
                _ = try container.decode(String.self, forKey: .missing)
            }
        }

        struct MissingNestedDecode: Decodable {
            enum CodingKeys: String, CodingKey { case nested, list, superNode }
            enum NestedKeys: String, CodingKey { case x }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nested)
                _ = try container.nestedUnkeyedContainer(forKey: .list)
                _ = try container.superDecoder(forKey: .superNode)
            }
        }

        struct BadScalar: Decodable {
            enum CodingKeys: String, CodingKey { case number }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.decode(Int.self, forKey: .number)
            }
        }

        let baseDecoder = try makeSAXDecoder(xml: "<Root><present>ok</present></Root>")
        XCTAssertThrowsError(try MissingDecode(from: baseDecoder)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_KEY_NOT_FOUND"))
        }

        let nestedDecoder = try makeSAXDecoder(xml: "<Root></Root>")
        XCTAssertThrowsError(try MissingNestedDecode(from: nestedDecoder)) { error in
            XCTAssertTrue("\(error)".contains("XML6_5_KEY_NOT_FOUND"))
        }

        let badScalar = try makeSAXDecoder(xml: "<Root><number>not-an-int</number></Root>")
        XCTAssertThrowsError(try BadScalar(from: badScalar)) { error in
            XCTAssertTrue("\(error)".contains("number") || "\(error)".contains("SCALAR"))
        }
    }

    func test_saxDecoder_nodeKind_and_transform_paths() throws {
        struct IgnoredValue: Decodable {
            enum CodingKeys: String, CodingKey { case hidden }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.decode(String.self, forKey: .hidden)
            }
        }

        struct TextAsInt: Decodable {
            enum CodingKeys: String, CodingKey { case body }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.decode(Int.self, forKey: .body)
            }
        }

        struct AttrStruct: Decodable {
            enum CodingKeys: String, CodingKey { case id }
            struct Nested: Decodable {}
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.decode(Nested.self, forKey: .id)
            }
        }

        let ignored = XMLFieldCodingOverrides().setting(path: [], key: "hidden", as: .ignored)
        let ignoredConfig = XMLDecoder.Configuration(rootElementName: "Root", fieldCodingOverrides: ignored)
        let ignoredDecoder = try makeSAXDecoder(xml: "<Root><hidden>x</hidden></Root>", configuration: ignoredConfig)
        XCTAssertThrowsError(try IgnoredValue(from: ignoredDecoder)) { error in
            XCTAssertTrue("\(error)".contains("XML6_6_IGNORED_FIELD_DECODE"))
        }

        let textKind = XMLFieldCodingOverrides().setting(path: [], key: "body", as: .textContent)
        let textConfig = XMLDecoder.Configuration(rootElementName: "Root", fieldCodingOverrides: textKind)
        let textDecoder = try makeSAXDecoder(xml: "<Root>abc</Root>", configuration: textConfig)
        XCTAssertThrowsError(try TextAsInt(from: textDecoder)) { error in
            XCTAssertTrue("\(error)".contains("TEXT_CONTENT") || "\(error)".contains("body"))
        }

        let attrKind = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let attrConfig = XMLDecoder.Configuration(rootElementName: "Root", fieldCodingOverrides: attrKind)
        let attrDecoder = try makeSAXDecoder(xml: "<Root id='7'></Root>", configuration: attrConfig)
        XCTAssertThrowsError(try AttrStruct(from: attrDecoder)) { error in
            XCTAssertTrue("\(error)".contains("XML6_6_ATTRIBUTE_DECODE_UNSUPPORTED"))
        }

        struct SnakeCasePayload: Decodable {
            let someValue: Int
        }
        let snakeConfig = XMLDecoder.Configuration(
            rootElementName: "Root",
            keyTransformStrategy: .convertToSnakeCase
        )
        let snakeDecoder = try makeSAXDecoder(xml: "<Root><some_value>9</some_value></Root>", configuration: snakeConfig)
        let snake = try SnakeCasePayload(from: snakeDecoder)
        XCTAssertEqual(snake.someValue, 9)
    }

}
