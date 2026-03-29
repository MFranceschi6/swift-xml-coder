import Foundation
@testable import SwiftXMLCoder
import XCTest

final class XMLCoverageBoostTests: XCTestCase {

    private enum RootKey: String, CodingKey {
        case bool
        case string
        case double
        case float
        case int
        case int8
        case int16
        case int32
        case int64
        case uint
        case uint8
        case uint16
        case uint32
        case uint64
        case optionalNil
        case optionalInt
        case optionalBool
        case optionalDouble
        case optionalFloat
        case optionalInt8
        case optionalInt16
        case optionalInt32
        case optionalInt64
        case optionalUInt
        case optionalUInt8
        case optionalUInt16
        case optionalUInt32
        case optionalUInt64
        case nested
        case list
        case superField
        case date
    }

    private struct ManualEncoderProbe: Encodable {
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: RootKey.self)
            try container.encode(true, forKey: .bool)
            try container.encode("hello", forKey: .string)
            try container.encode(1.25, forKey: .double)
            try container.encode(Float(2.5), forKey: .float)
            try container.encode(3, forKey: .int)
            try container.encode(Int8(4), forKey: .int8)
            try container.encode(Int16(5), forKey: .int16)
            try container.encode(Int32(6), forKey: .int32)
            try container.encode(Int64(7), forKey: .int64)
            try container.encode(UInt(8), forKey: .uint)
            try container.encode(UInt8(9), forKey: .uint8)
            try container.encode(UInt16(10), forKey: .uint16)
            try container.encode(UInt32(11), forKey: .uint32)
            try container.encode(UInt64(12), forKey: .uint64)

            let nilInt: Int? = nil
            let someInt: Int? = 13
            let someBool: Bool? = true
            let someDouble: Double? = 2.75
            let someFloat: Float? = 3.5
            let someInt8: Int8? = 14
            let someInt16: Int16? = 15
            let someInt32: Int32? = 16
            let someInt64: Int64? = 17
            let someUInt: UInt? = 18
            let someUInt8: UInt8? = 19
            let someUInt16: UInt16? = 20
            let someUInt32: UInt32? = 21
            let someUInt64: UInt64? = 22
            try container.encodeIfPresent(nilInt, forKey: .optionalNil)
            try container.encodeIfPresent(someInt, forKey: .optionalInt)
            try container.encodeIfPresent(someBool, forKey: .optionalBool)
            try container.encodeIfPresent(someDouble, forKey: .optionalDouble)
            try container.encodeIfPresent(someFloat, forKey: .optionalFloat)
            try container.encodeIfPresent(someInt8, forKey: .optionalInt8)
            try container.encodeIfPresent(someInt16, forKey: .optionalInt16)
            try container.encodeIfPresent(someInt32, forKey: .optionalInt32)
            try container.encodeIfPresent(someInt64, forKey: .optionalInt64)
            try container.encodeIfPresent(someUInt, forKey: .optionalUInt)
            try container.encodeIfPresent(someUInt8, forKey: .optionalUInt8)
            try container.encodeIfPresent(someUInt16, forKey: .optionalUInt16)
            try container.encodeIfPresent(someUInt32, forKey: .optionalUInt32)
            try container.encodeIfPresent(someUInt64, forKey: .optionalUInt64)

            var nested = container.nestedContainer(keyedBy: RootKey.self, forKey: .nested)
            try nested.encode("inside", forKey: .string)

            var list = container.nestedUnkeyedContainer(forKey: .list)
            try list.encodeNil()
            try list.encode(true)
            try list.encode("x")
            try list.encode(1.5)
            try list.encode(Float(2.5))
            try list.encode(14)
            try list.encode(Int8(15))
            try list.encode(Int16(16))
            try list.encode(Int32(17))
            try list.encode(Int64(18))
            try list.encode(UInt(19))
            try list.encode(UInt8(20))
            try list.encode(UInt16(21))
            try list.encode(UInt32(22))
            try list.encode(UInt64(23))
            var listNested = list.nestedContainer(keyedBy: RootKey.self)
            try listNested.encode("y", forKey: .string)
            var listUnkeyed = list.nestedUnkeyedContainer()
            try listUnkeyed.encode("z")
            let listSuper = list.superEncoder()
            var listSuperSVC = listSuper.singleValueContainer()
            try listSuperSVC.encode("super-list")
            try listSuperSVC.encode(24)
            try listSuperSVC.encode(UInt64(25))
            try listSuperSVC.encode(2.75)

            let superDefault = container.superEncoder()
            var svc = superDefault.singleValueContainer()
            try svc.encode("super-default")

            let superForKey = container.superEncoder(forKey: .superField)
            var superForKeySVC = superForKey.singleValueContainer()
            try superForKeySVC.encode("super-for-key")
        }
    }

    private struct DateProbe: Encodable {
        let value: Date

        enum CodingKeys: String, CodingKey { case value }
    }

    private struct DateHintProbe: Encodable, XMLDateCodingOverrideProvider {
        let date: Date
        static let xmlPropertyDateHints: [String: XMLDateFormatHint] = ["date": .xsdDate]
    }

    private struct ScalarSingleValueProbe<T: Encodable>: Encodable {
        let value: T
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(value)
        }
    }

    private struct NonScalarValue: Encodable {
        let value: String
    }

    private enum BoostKey: String, CodingKey {
        case textField
        case attributeField
        case attributeValue
    }

    private func makeStreamingDecoder(
        xml: String,
        configuration: XMLDecoder.Configuration = .init(rootElementName: "Root")
    ) throws -> _XMLStreamingDecoder {
        let session = try _XMLStreamingParserSession(
            data: Data(xml.utf8),
            configuration: configuration.parserConfiguration
        )

        var startEvent: XMLStreamEvent?
        while let event = try session.nextEvent() {
            if case .startElement = event {
                startEvent = event
                break
            }
        }

        let start = try XCTUnwrap(startEvent)
        let state = try _XMLStreamingElementState(session: session, start: start)
        let options = _XMLDecoderOptions(configuration: configuration)
        return _XMLStreamingDecoder(options: options, state: state, codingPath: [])
    }

    func test_treeDocument_walkEvents_emits_prologue_children_and_epilogue() throws {
        let child = XMLTreeElement(
            name: XMLQualifiedName(localName: "child"),
            children: [.text("child-text")]
        )
        let root = XMLTreeElement(
            name: XMLQualifiedName(localName: "root"),
            attributes: [XMLTreeAttribute(name: XMLQualifiedName(localName: "id"), value: "1")],
            children: [
                .text("alpha"),
                .cdata("beta"),
                .comment("inside-comment"),
                .processingInstruction(target: "inner-pi", data: "k=v"),
                .element(child)
            ]
        )
        let doc = XMLTreeDocument(
            root: root,
            metadata: XMLDocumentStructuralMetadata(xmlVersion: "1.0", encoding: "UTF-8", standalone: true),
            prologueNodes: [.comment("prologue-comment"), .processingInstruction(target: "xml-stylesheet", data: "type='text/xsl'")],
            epilogueNodes: [.processingInstruction(target: "epilogue", data: nil), .comment("epilogue-comment")]
        )

        var events: [XMLStreamEvent] = []
        try doc.walkEvents { events.append($0) }

        XCTAssertTrue(events.contains { if case .startDocument = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .comment("prologue-comment") = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .processingInstruction(let target, _) = $0 { return target == "xml-stylesheet" } else { return false } })
        XCTAssertTrue(events.contains { if case .cdata("beta") = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .comment("inside-comment") = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .processingInstruction(let target, _) = $0 { return target == "inner-pi" } else { return false } })
        XCTAssertTrue(events.contains { if case .comment("epilogue-comment") = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains { if case .endDocument = $0 { return true } else { return false } })
    }

    func test_treeEncoder_manualProbe_exercises_typed_container_entrypoints() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "root", nilEncodingStrategy: .emptyElement))
        let tree = try encoder.encodeTree(ManualEncoderProbe())
        XCTAssertEqual(tree.root.name.localName, "root")

        let childNames = tree.root.children.compactMap { node -> String? in
            if case .element(let element) = node { return element.name.localName }
            return nil
        }
        XCTAssertTrue(childNames.contains("bool"))
        XCTAssertTrue(childNames.contains("nested"))
        XCTAssertTrue(childNames.contains("list"))
    }

    func test_treeEncoder_dateStrategies_and_perPropertyHint_paths() throws {
        let date = Date(timeIntervalSince1970: 1_705_000_000)
        let tz = TimeZone(secondsFromGMT: 0) ?? .utc
        let strategies: [XMLEncoder.DateEncodingStrategy] = [
            .xsdDate(timeZone: tz),
            .xsdTime(timeZone: tz),
            .xsdGYear(timeZone: tz),
            .xsdGYearMonth(timeZone: tz),
            .xsdGMonth(timeZone: tz),
            .xsdGDay(timeZone: tz),
            .xsdGMonthDay(timeZone: tz),
            .iso8601
        ]

        for strategy in strategies {
            let encoder = XMLEncoder(configuration: .init(rootElementName: "DateProbe", dateEncodingStrategy: strategy))
            let xml = try encoder.encode(DateProbe(value: date))
            XCTAssertFalse(xml.isEmpty)
        }

        let hintedEncoder = XMLEncoder(configuration: .init(rootElementName: "DateHintProbe"))
        let hintedXML = try hintedEncoder.encode(DateHintProbe(date: date))
        XCTAssertFalse(hintedXML.isEmpty)
    }

    func test_treeEncoder_singleValue_typed_wrappers() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "value", nilEncodingStrategy: .emptyElement))
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: true)).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: "abc")).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: 1.5)).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: Float(2.5))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: Int(3))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: Int8(4))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: Int16(5))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: Int32(6))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: Int64(7))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: UInt(8))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: UInt8(9))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: UInt16(10))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: UInt32(11))).isEmpty)
        XCTAssertFalse(try encoder.encode(ScalarSingleValueProbe(value: UInt64(12))).isEmpty)
    }

    func test_streamingSession_peek_next_and_special_nodes() throws {
        let xml = "<?xml version='1.0'?><root><!--c--><?p d?><a>v</a></root>"
        let session = try _XMLStreamingParserSession(data: Data(xml.utf8), configuration: XMLTreeParser.Configuration())

        let firstPeek = try session.peekNextEvent()
        XCTAssertNotNil(firstPeek)

        var events: [XMLStreamEvent] = []
        while let event = try session.nextEvent() {
            events.append(event)
        }

        XCTAssertTrue(events.contains { if case .comment("c") = $0 { return true } else { return false } })
        XCTAssertTrue(events.contains {
            if case .processingInstruction(let target, let data) = $0 {
                return target == "p" && data == "d"
            }
            return false
        })
    }

    func test_streamingSession_whitespacePolicies_and_attribute_limit() throws {
        let source = "<root><v>  a   b  </v></root>"

        let preserveSession = try _XMLStreamingParserSession(
            data: Data(source.utf8),
            configuration: XMLTreeParser.Configuration(whitespaceTextNodePolicy: .preserve)
        )
        var preserveTexts: [String] = []
        while let event = try preserveSession.nextEvent() {
            if case .text(let value) = event { preserveTexts.append(value) }
        }
        XCTAssertTrue(preserveTexts.joined().contains("  a   b  "))

        let trimSession = try _XMLStreamingParserSession(
            data: Data(source.utf8),
            configuration: XMLTreeParser.Configuration(whitespaceTextNodePolicy: .trim)
        )
        var trimTexts: [String] = []
        while let event = try trimSession.nextEvent() {
            if case .text(let value) = event { trimTexts.append(value) }
        }
        XCTAssertEqual(trimTexts.joined(), "a   b")

        let normalizeSession = try _XMLStreamingParserSession(
            data: Data(source.utf8),
            configuration: XMLTreeParser.Configuration(whitespaceTextNodePolicy: .normalizeAndTrim)
        )
        var normalizeTexts: [String] = []
        while let event = try normalizeSession.nextEvent() {
            if case .text(let value) = event { normalizeTexts.append(value) }
        }
        XCTAssertEqual(normalizeTexts.joined(), "a b")

        let attrsXML = "<root a='1' b='2'></root>"
        let limits = XMLTreeParser.Limits(maxAttributesPerElement: 1)
        let limitedSession = try _XMLStreamingParserSession(
            data: Data(attrsXML.utf8),
            configuration: XMLTreeParser.Configuration(limits: limits)
        )

        XCTAssertThrowsError(try {
            while let _ = try limitedSession.nextEvent() {}
        }()) { error in
            XCTAssertTrue("\(error)".contains("XML6_2H_MAX_ATTRS"))
        }
    }

    func test_streamingElementState_inline_and_scalar_leaf_paths() throws {
        let xml = "<root><a>1</a><b><x>2</x></b></root>"
        let session = try _XMLStreamingParserSession(data: Data(xml.utf8), configuration: XMLTreeParser.Configuration())
        _ = try session.nextEvent() // startDocument
        let rootStart = try XCTUnwrap(try session.nextEvent())
        let state = try _XMLStreamingElementState(session: session, start: rootStart)

        let a = try state.consumeChildInline(named: "a", namespaceURI: nil)
        switch a {
        case .scalarLeaf(let value, let name):
            XCTAssertEqual(name.localName, "a")
            XCTAssertEqual(value, "1")
        default:
            XCTFail("Expected scalar leaf for <a>")
        }

        let b = try state.consumeChildInline(named: "b", namespaceURI: nil)
        switch b {
        case .inline(let childState):
            XCTAssertEqual(childState.startName.localName, "b")
            XCTAssertTrue(try childState.hasMoreChildren())
            _ = try childState.consumeAnyChildInline()
            XCTAssertFalse(try childState.hasMoreChildren())
        default:
            XCTFail("Expected inline child state for <b>")
        }
    }

    func test_streamingElementState_outOfOrder_buffering_and_anyChild() throws {
        let xml = "<root><x>1</x><y>2</y></root>"
        let session = try _XMLStreamingParserSession(data: Data(xml.utf8), configuration: XMLTreeParser.Configuration())
        _ = try session.nextEvent() // startDocument
        let rootStart = try XCTUnwrap(try session.nextEvent())
        let state = try _XMLStreamingElementState(session: session, start: rootStart)

        // Ask for y first: x is buffered as out-of-order.
        _ = try state.consumeChildInline(named: "y", namespaceURI: nil)
        XCTAssertEqual(state.childCount, 1)

        // Buffered x should still be reachable.
        let bufferedX = try state.consumeChildInline(named: "x", namespaceURI: nil)
        if case .buffered(let staged)? = bufferedX {
            XCTAssertEqual(staged.name.localName, "x")
        } else {
            XCTFail("Expected buffered child for x")
        }

        // allChildrenBestEffort / lexicalText no-throw path.
        XCTAssertNotNil(state.allChildrenBestEffort())
        _ = try state.lexicalText(draining: false)
    }

    func test_streamingElementState_buffer_inventory_and_peek_paths() throws {
        let xml = "<root>lead<a>1</a><b>2</b></root>"
        let session = try _XMLStreamingParserSession(data: Data(xml.utf8), configuration: XMLTreeParser.Configuration())
        _ = try session.nextEvent() // startDocument
        let rootStart = try XCTUnwrap(try session.nextEvent())
        let state = try _XMLStreamingElementState(session: session, start: rootStart)

        XCTAssertEqual(try state.lexicalText(draining: false), nil)

        let first = try state.consumeChild(named: "a", namespaceURI: nil)
        XCTAssertEqual(first?.name.localName, "a")

        let second = try state.peekChild(named: "b", namespaceURI: nil)
        XCTAssertEqual(second?.name.localName, "b")

        XCTAssertEqual(try state.child(at: 0)?.name.localName, "a")
        XCTAssertEqual(try state.child(at: 1)?.name.localName, "b")
        XCTAssertNil(try state.child(at: 2))

        try state.drainToEndIfNeeded()
        XCTAssertEqual(state.allChildrenBestEffort().count, 2)
        XCTAssertEqual(try state.lexicalText(draining: false), "lead")
        _ = try state.hasMoreChildren()
    }

    func test_streamingElementState_hasMoreChildren_and_consumeAnyChildInline() throws {
        let xml = "<root><a>1</a><b><c>2</c></b></root>"
        let session = try _XMLStreamingParserSession(data: Data(xml.utf8), configuration: XMLTreeParser.Configuration())
        _ = try session.nextEvent() // startDocument
        let rootStart = try XCTUnwrap(try session.nextEvent())
        let state = try _XMLStreamingElementState(session: session, start: rootStart)

        XCTAssertTrue(try state.hasMoreChildren())
        let first = try state.consumeAnyChildInline()
        if case .scalarLeaf(let text, let name)? = first {
            XCTAssertEqual(name.localName, "a")
            XCTAssertEqual(text, "1")
        } else {
            XCTFail("Expected scalar leaf for first child")
        }

        XCTAssertTrue(try state.hasMoreChildren())
        let second = try state.consumeAnyChildInline()
        if case .inline(let childState)? = second {
            XCTAssertEqual(childState.startName.localName, "b")
            XCTAssertTrue(try childState.hasMoreChildren())
        } else {
            XCTFail("Expected inline child state for second child")
        }
        _ = try state.hasMoreChildren()
    }

    func test_streamingDecoder_keyed_unkeyed_and_super_paths() throws {
        struct Payload: Decodable {
            enum CodingKeys: String, CodingKey { case value, nested, values, missing, superNode }
            enum NestedKeys: String, CodingKey { case inner }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = container.allKeys
                _ = container.contains(.value)
                _ = try container.decodeNil(forKey: .missing)
                _ = try container.decode(String.self, forKey: .value)

                let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .nested)
                _ = try nested.decode(String.self, forKey: .inner)

                var unkeyed = try container.nestedUnkeyedContainer(forKey: .values)
                _ = unkeyed.count
                _ = unkeyed.isAtEnd
                _ = try unkeyed.decodeNil()
                _ = try unkeyed.decode(Bool.self)
                _ = try unkeyed.decode(String.self)
                _ = try unkeyed.decode(Double.self)
                _ = try unkeyed.decode(Float.self)
                _ = try unkeyed.decode(Int.self)
                _ = try unkeyed.decode(Int8.self)
                _ = try unkeyed.decode(Int16.self)
                _ = try unkeyed.decode(Int32.self)
                _ = try unkeyed.decode(Int64.self)
                _ = try unkeyed.decode(UInt.self)
                _ = try unkeyed.decode(UInt8.self)
                _ = try unkeyed.decode(UInt16.self)
                _ = try unkeyed.decode(UInt32.self)
                _ = try unkeyed.decode(UInt64.self)

                let nestedContainer = try unkeyed.nestedContainer(keyedBy: NestedKeys.self)
                _ = try nestedContainer.decode(String.self, forKey: .inner)

                var nestedUnkeyed = try unkeyed.nestedUnkeyedContainer()
                _ = try nestedUnkeyed.decode(String.self)
                _ = try nestedUnkeyed.decode(String.self)

                let superDecoder = try unkeyed.superDecoder()
                let superContainer = try superDecoder.container(keyedBy: NestedKeys.self)
                _ = try superContainer.decode(String.self, forKey: .inner)

                _ = try container.superDecoder()
                _ = try container.superDecoder(forKey: .superNode)
            }
        }

        let xml = """
        <Root>
          <value>ok</value>
          <nested><inner>x</inner></nested>
          <values>
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
            <item><item>a</item><item>b</item></item>
            <item><inner>sup</inner></item>
          </values>
          <superNode><inner>k</inner></superNode>
        </Root>
        """

        let decoder = try makeStreamingDecoder(xml: xml)
        _ = try Payload(from: decoder)
    }

    func test_streamingDecoder_singleValue_typed_paths() throws {
        func scalarDecoder(xml: String) throws -> _XMLStreamingDecoder {
            try makeStreamingDecoder(
                xml: xml,
                configuration: .init(rootElementName: "value")
            )
        }

        do {
            let d = try scalarDecoder(xml: "<value>true</value>")
            let c = try d.singleValueContainer()
            XCTAssertEqual(try c.decode(Bool.self), true)
        }
        do {
            let d = try scalarDecoder(xml: "<value>abc</value>")
            let c = try d.singleValueContainer()
            XCTAssertEqual(try c.decode(String.self), "abc")
        }
        do {
            let d = try scalarDecoder(xml: "<value>1.5</value>")
            let c = try d.singleValueContainer()
            XCTAssertEqual(try c.decode(Double.self), 1.5, accuracy: 0.000_001)
        }
        do {
            let d = try scalarDecoder(xml: "<value>2.5</value>")
            let c = try d.singleValueContainer()
            XCTAssertEqual(try c.decode(Float.self), Float(2.5), accuracy: 0.000_001)
        }
        do {
            let d = try scalarDecoder(xml: "<value>3</value>")
            let c = try d.singleValueContainer()
            XCTAssertEqual(try c.decode(Int.self), 3)
            XCTAssertEqual(try c.decode(Int8.self), 3)
            XCTAssertEqual(try c.decode(Int16.self), 3)
            XCTAssertEqual(try c.decode(Int32.self), 3)
            XCTAssertEqual(try c.decode(Int64.self), 3)
            XCTAssertEqual(try c.decode(UInt.self), 3)
            XCTAssertEqual(try c.decode(UInt8.self), 3)
            XCTAssertEqual(try c.decode(UInt16.self), 3)
            XCTAssertEqual(try c.decode(UInt32.self), 3)
            XCTAssertEqual(try c.decode(UInt64.self), 3)
        }
    }

    func test_streamingDecoder_internal_decodeValue_and_nil_result_paths() throws {
        struct ChildPayload: Decodable { let v: String }

        let decoder = try makeStreamingDecoder(xml: "<Root><child><v>x</v></child><leaf>7</leaf><empty/></Root>")

        let childResult = try XCTUnwrap(decoder.state.consumeChildInline(named: "child", namespaceURI: nil))
        let childValue: ChildPayload = try decoder.decodeValue(ChildPayload.self, from: childResult, codingPath: [])
        XCTAssertEqual(childValue.v, "x")

        let leafResult = try XCTUnwrap(decoder.state.consumeChildInline(named: "leaf", namespaceURI: nil))
        let leafInt: Int = try decoder.decodeValue(Int.self, from: leafResult, codingPath: [])
        XCTAssertEqual(leafInt, 7)

        XCTAssertFalse(decoder.isNilResult(leafResult))
        let emptyResult = try XCTUnwrap(decoder.state.consumeChildInline(named: "empty", namespaceURI: nil))
        XCTAssertTrue(decoder.isNilResult(emptyResult))
    }

    func test_streamingUnkeyed_itemsOnly_mode_count_and_out_of_range() throws {
        let decoder = try makeStreamingDecoder(
            xml: "<items><item>1</item><x>skip</x><item>2</item><tail>z</tail></items>",
            configuration: .init(rootElementName: "items")
        )
        var unkeyed = _XMLStreamingUnkeyedDecodingContainer(decoder: decoder, codingPath: [])

        XCTAssertEqual(unkeyed.count, 2)
        XCTAssertEqual(try unkeyed.decode(Int.self), 1)
        XCTAssertEqual(try unkeyed.decode(Int.self), 2)
        _ = try? unkeyed.decode(Int.self)
        XCTAssertTrue(unkeyed.isAtEnd)
    }

    func test_streamingSingleValue_error_path_for_known_scalar() throws {
        let decoder = try makeStreamingDecoder(
            xml: "<value></value>",
            configuration: .init(rootElementName: "value")
        )
        let container = try decoder.singleValueContainer()
        XCTAssertThrowsError(try container.decode(Int.self)) { error in
            XCTAssertTrue("\(error)".contains("SCALAR_PARSE_FAILED"))
        }
    }

    func test_treeEncoder_internal_boxedScalar_date_url_uuid_and_custom_error_paths() throws {
        let root = _XMLTreeElementBox(name: XMLQualifiedName(localName: "Root"))
        var options = try _XMLEncoderOptions(configuration: .init(rootElementName: "Root"))
        options.perPropertyDateHints = ["date": .xsdDate]
        let encoder = _XMLTreeEncoder(options: options, codingPath: [], node: root)

        XCTAssertEqual(try encoder.boxedScalar(URL(string: "https://example.com")!, codingPath: [], localName: nil), "https://example.com")
        XCTAssertNotNil(try encoder.boxedScalar(UUID(), codingPath: [], localName: nil))

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let tz = TimeZone(secondsFromGMT: 0) ?? .utc
        let strategies: [XMLEncoder.DateEncodingStrategy] = [
            .deferredToDate,
            .secondsSince1970,
            .millisecondsSince1970,
            .xsdDateTimeISO8601,
            .iso8601,
            .xsdDate(timeZone: tz),
            .xsdTime(timeZone: tz),
            .xsdGYear(timeZone: tz),
            .xsdGYearMonth(timeZone: tz),
            .xsdGMonth(timeZone: tz),
            .xsdGDay(timeZone: tz),
            .xsdGMonthDay(timeZone: tz),
            .formatter(.init(format: "yyyy-MM-dd HH:mm:ss"))
        ]

        for strategy in strategies {
            var localOptions = try _XMLEncoderOptions(configuration: .init(rootElementName: "Root", dateEncodingStrategy: strategy))
            localOptions.perPropertyDateHints = ["date": .xsdDate]
            let localEncoder = _XMLTreeEncoder(options: localOptions, codingPath: [], node: _XMLTreeElementBox(name: XMLQualifiedName(localName: "Root")))
            _ = try localEncoder.boxedScalar(date, codingPath: [], localName: "date")
        }

        let parsingError = XMLParsingError.parseFailed(message: "boom")
        let optionsWithThrowingCustom = try _XMLEncoderOptions(
            configuration: .init(
                rootElementName: "Root",
                dateEncodingStrategy: .custom { _, _ in
                    throw parsingError
                }
            )
        )
        let customEncoder = _XMLTreeEncoder(
            options: optionsWithThrowingCustom,
            codingPath: [],
            node: _XMLTreeElementBox(name: XMLQualifiedName(localName: "Root"))
        )
        XCTAssertThrowsError(try customEncoder.boxedScalar(date, codingPath: [], localName: "date")) { error in
            XCTAssertEqual(error as? XMLParsingError, parsingError)
        }

        let optionsWithWrappedCustom = try _XMLEncoderOptions(
            configuration: .init(
                rootElementName: "Root",
                dateEncodingStrategy: .custom { _, _ in
                    struct AnyError: Error {}
                    throw AnyError()
                }
            )
        )
        let wrappedCustomEncoder = _XMLTreeEncoder(
            options: optionsWithWrappedCustom,
            codingPath: [],
            node: _XMLTreeElementBox(name: XMLQualifiedName(localName: "Root"))
        )
        XCTAssertThrowsError(try wrappedCustomEncoder.boxedScalar(date, codingPath: [], localName: "date")) { error in
            XCTAssertTrue("\(error)".contains("DATE_ENCODE_CUSTOM_FAILED"))
        }
    }

    func test_treeEncoder_keyed_text_content_attribute_paths_and_namespace_attribute() throws {
        let options = try _XMLEncoderOptions(configuration: .init(
            rootElementName: "Root",
            keyTransformStrategy: .custom { key in
                if key == "attributeValue" { return "attr-value" }
                return key
            }
        ))
        let node = _XMLTreeElementBox(name: XMLQualifiedName(localName: "Root"))
        let encoder = _XMLTreeEncoder(
            options: options,
            codingPath: [],
            node: node,
            fieldNodeKinds: [
                "textField": .textContent,
                "attributeField": .attribute,
                "attributeValue": .attribute
            ],
            fieldNamespaces: ["attributeValue": XMLNamespace(prefix: "p", uri: "urn:test")]
        )
        var container = _XMLKeyedEncodingContainer<BoostKey>(encoder: encoder, codingPath: [])

        XCTAssertThrowsError(try container.encode(NonScalarValue(value: "x"), forKey: .textField)) { error in
            XCTAssertTrue("\(error)".contains("TEXT_CONTENT_ENCODE_UNSUPPORTED"))
        }
        XCTAssertThrowsError(try container.encode(NonScalarValue(value: "x"), forKey: .attributeField)) { error in
            XCTAssertTrue("\(error)".contains("ATTRIBUTE_ENCODE_UNSUPPORTED"))
        }

        try container.encode("ok", forKey: .attributeValue)
        XCTAssertEqual(node.attributes.count, 1)
        XCTAssertEqual(node.attributes[0].name.localName, "attr-value")
        XCTAssertEqual(node.attributes[0].name.prefix, "p")
        XCTAssertTrue(node.namespaceDeclarations.contains { $0.prefix == "p" && $0.uri == "urn:test" })
    }

    func test_treeEncoder_internal_unkeyed_and_singleValue_container_paths() throws {
        let options = try _XMLEncoderOptions(configuration: .init(rootElementName: "Root", nilEncodingStrategy: .emptyElement))
        let root = _XMLTreeElementBox(name: XMLQualifiedName(localName: "Root"))
        let encoder = _XMLTreeEncoder(options: options, codingPath: [], node: root)

        var unkeyed = _XMLUnkeyedEncodingContainer(encoder: encoder, codingPath: [])
        try unkeyed.encode(1)
        try unkeyed.encode(NonScalarValue(value: "nested"))
        XCTAssertGreaterThanOrEqual(unkeyed.count, 2)

        var single = _XMLSingleValueEncodingContainer(encoder: encoder, codingPath: [])
        try single.encodeNil()
        try single.encode(true)
        try single.encode(Float(2.5))
        try single.encode(Int8(4))
        try single.encode(Int16(5))
        try single.encode(Int32(6))
        try single.encode(Int64(7))
        try single.encode(UInt(8))
        try single.encode(UInt8(9))
        try single.encode(UInt16(10))
        try single.encode(UInt32(11))
        try single.encode(UInt64(12))
        try single.encode(NonScalarValue(value: "single-nested"))
    }

    func test_xmlecodingkey_int_initializer_and_streaming_decoder_decodeFailed_overload() throws {
        let key = try XCTUnwrap(_XMLEncodingKey(intValue: 42))
        XCTAssertEqual(key.stringValue, "Index42")
        XCTAssertEqual(key.intValue, 42)

        let decoder = try makeStreamingDecoder(xml: "<Root><x>1</x></Root>")
        let error = decoder.decodeFailed(message: "forced")
        XCTAssertTrue("\(error)".contains("forced"))
    }

    func test_parseSAX_node_and_attribute_limits_and_whitespace_variants() throws {
        do {
            let parser = XMLStreamParser(configuration: .init(limits: .init(maxNodeCount: 1)))
            XCTAssertThrowsError(try parser.parseSAX(data: Data("<root><a/></root>".utf8), onEvent: { _ in })) { error in
                XCTAssertTrue("\(error)".contains("XML6_2H_MAX_NODE_COUNT"))
            }
        }

        do {
            let parser = XMLStreamParser(configuration: .init(limits: .init(maxAttributesPerElement: 0)))
            XCTAssertThrowsError(try parser.parseSAX(data: Data("<root a='1'/>".utf8), onEvent: { _ in })) { error in
                XCTAssertTrue("\(error)".contains("XML6_2H_MAX_ATTRS"))
            }
        }

        do {
            let parser = XMLStreamParser(configuration: .init(whitespaceTextNodePolicy: .trim))
            var seenText: [String] = []
            try parser.parseSAX(data: Data("<root>   a   b   </root>".utf8), onEvent: { event in
                if case .text(let text) = event { seenText.append(text) }
            })
            XCTAssertEqual(seenText.joined(), "a   b")
        }

        do {
            let parser = XMLStreamParser(configuration: .init(whitespaceTextNodePolicy: .normalizeAndTrim))
            var seenText: [String] = []
            try parser.parseSAX(data: Data("<root>   a   b   </root>".utf8), onEvent: { event in
                if case .text(let text) = event { seenText.append(text) }
            })
            XCTAssertEqual(seenText.joined(), "a b")
        }

        do {
            let parser = XMLStreamParser(configuration: .init())
            var withLineHits = 0
            try parser.parseSAX(data: Data("<root/>".utf8), onEvent: { _ in }, onEventWithLine: { _, line in
                if line != nil { withLineHits += 1 }
            })
            XCTAssertGreaterThan(withLineHits, 0)
        }
    }
}
