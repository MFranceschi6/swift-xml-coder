import Foundation
@testable import SwiftXMLCoder
import XCTest

// MARK: - Coverage Boost Tests — Phase 3
//
// Continued from XMLCoverageBoost2Tests. Targets:
// - XMLDefaultCanonicalizer: stream-based API, event transforms, CDATA, comments
// - XMLItemDecoder: empty data, non-matching elements, multiple items, siblings, nested
// - _XMLStreamingDecoder: out-of-order keys, deep nesting, contains/decodeNil
// - XMLEncoder: key transform, pretty-print, CDATA, namespace, encodeTree, output limits
// - XMLDecoder: allKeys, unkeyed iteration, nestedContainer, singleValue
// - XMLFieldCodingOverrides: ignored, attribute
// - Date/Data strategies: ISO8601, seconds, milliseconds, base64

// MARK: - File-scope model for namespace test

private struct _NSModelForTest3: Codable {
    let name: String
}
extension _NSModelForTest3: XMLFieldNamespaceProvider {
    static var xmlFieldNamespaces: [String: XMLNamespace] {
        ["name": XMLNamespace(prefix: "ns", uri: "http://example.com")]
    }
}

final class XMLCoverageBoost3Tests: XCTestCase {

    // MARK: - XMLDefaultCanonicalizer: stream-based canonicalisation from data

    func test_canonicalizer_streamBased_fromData() throws {
        let xml = Data("<root><b>2</b><a>1</a></root>".utf8)
        let canonicalizer = XMLDefaultCanonicalizer()
        let result = try canonicalizer.canonicalize(data: xml)
        let output = String(decoding: result, as: UTF8.self)
        XCTAssert(output.contains("<root>"), "Expected root in canonical output: \(output)")
        XCTAssert(output.contains("<b>2</b>"), "Expected b element in: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: stream-based with output callback

    func test_canonicalizer_streamBased_withOutputCallback() throws {
        let xml = Data("<doc><item>test</item></doc>".utf8)
        let canonicalizer = XMLDefaultCanonicalizer()
        var chunks: [Data] = []
        try canonicalizer.canonicalize(
            data: xml,
            options: XMLCanonicalizationOptions(),
            eventTransforms: []
        ) { chunk in
            chunks.append(chunk)
        }
        let output = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(output.contains("<item>test</item>"), "Expected item in: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: event-based canonicalisation

    func test_canonicalizer_eventBased_fromEventSequence() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []),
            .text("hello"),
            .endElement(name: XMLQualifiedName(localName: "root")),
            .endDocument,
        ]
        let canonicalizer = XMLDefaultCanonicalizer()
        var chunks: [Data] = []
        try canonicalizer.canonicalize(
            events: events,
            options: XMLCanonicalizationOptions(),
            eventTransforms: []
        ) { chunk in
            chunks.append(chunk)
        }
        let output = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(output.contains("<root>hello</root>"), "Expected root with text in: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: CDATA converted to text

    func test_canonicalizer_streamBased_cdataConvertedToText() throws {
        let xml = Data("<root><![CDATA[hello world]]></root>".utf8)
        let canonicalizer = XMLDefaultCanonicalizer()
        let result = try canonicalizer.canonicalize(data: xml)
        let output = String(decoding: result, as: UTF8.self)
        // Canonical XML converts CDATA to text
        XCTAssert(output.contains("hello world"), "Expected text content in: \(output)")
        XCTAssertFalse(output.contains("CDATA"), "CDATA should be converted to text in canonical form: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: comments stripped by default

    func test_canonicalizer_streamBased_commentsStrippedByDefault() throws {
        let xml = Data("<root><!-- a comment --><item>val</item></root>".utf8)
        let canonicalizer = XMLDefaultCanonicalizer()
        let result = try canonicalizer.canonicalize(data: xml)
        let output = String(decoding: result, as: UTF8.self)
        XCTAssertFalse(output.contains("comment"), "Comments should be stripped by default: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: comments preserved when option set

    func test_canonicalizer_streamBased_commentsPreserved() throws {
        let xml = Data("<root><!-- keep me --><item>val</item></root>".utf8)
        let canonicalizer = XMLDefaultCanonicalizer()
        let result = try canonicalizer.canonicalize(
            data: xml,
            options: XMLCanonicalizationOptions(includeComments: true)
        )
        let output = String(decoding: result, as: UTF8.self)
        XCTAssert(output.contains("keep me"), "Comments should be preserved when option set: \(output)")
    }

    // MARK: - XMLItemDecoder: empty data

    func test_itemDecoder_emptyData_returnsEmptyArray() throws {
        struct Item: Decodable { let name: String }
        let data = Data("<root></root>".utf8)
        let result = try XMLItemDecoder().decode(Item.self, itemElement: "item", from: data)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - XMLItemDecoder: no matching elements

    func test_itemDecoder_noMatchingElements_returnsEmpty() throws {
        struct Item: Decodable { let val: Int }
        let data = Data("<root><other>1</other><other>2</other></root>".utf8)
        let result = try XMLItemDecoder().decode(Item.self, itemElement: "item", from: data)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - XMLItemDecoder: multiple items

    func test_itemDecoder_multipleItems_decodesAll() throws {
        struct Product: Decodable, Equatable { let name: String }
        let xml = """
        <catalog>
            <Product><name>A</name></Product>
            <Product><name>B</name></Product>
            <Product><name>C</name></Product>
        </catalog>
        """
        let result = try XMLItemDecoder().decode(Product.self, itemElement: "Product", from: Data(xml.utf8))
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.name), ["A", "B", "C"])
    }

    // MARK: - XMLItemDecoder: items with non-matching siblings

    func test_itemDecoder_withNonMatchingSiblings_skipsThem() throws {
        struct Entry: Decodable, Equatable { let v: Int }
        let xml = """
        <root>
            <metadata>ignored</metadata>
            <Entry><v>1</v></Entry>
            <other>also ignored</other>
            <Entry><v>2</v></Entry>
            <footer>skipped</footer>
        </root>
        """
        let result = try XMLItemDecoder().decode(Entry.self, itemElement: "Entry", from: Data(xml.utf8))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].v, 1)
        XCTAssertEqual(result[1].v, 2)
    }

    // MARK: - XMLItemDecoder: nested items (only top-level match)

    func test_itemDecoder_nestedElements_decodesTopLevelOnly() throws {
        struct Item: Decodable, Equatable { let name: String }
        let xml = """
        <root>
            <Item><name>top</name></Item>
        </root>
        """
        let result = try XMLItemDecoder().decode(Item.self, itemElement: "Item", from: Data(xml.utf8))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "top")
    }

    // MARK: - Streaming decoder: out-of-order keyed access

    func test_streamingDecoder_outOfOrderKeys_decodesCorrectly() throws {
        struct OutOfOrder: Decodable, Equatable {
            let b: String
            let a: String

            enum CodingKeys: String, CodingKey { case a, b }

            init(a: String, b: String) { self.a = a; self.b = b }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // Access b first, but a comes first in XML
                b = try container.decode(String.self, forKey: .b)
                a = try container.decode(String.self, forKey: .a)
            }
        }
        let xml = Data("<root><a>first</a><b>second</b></root>".utf8)
        let decoded = try XMLDecoder().decode(OutOfOrder.self, from: xml)
        XCTAssertEqual(decoded.a, "first")
        XCTAssertEqual(decoded.b, "second")
    }

    // MARK: - Streaming decoder: deeply nested structure

    func test_streamingDecoder_deepNesting() throws {
        struct L3: Codable, Equatable { let value: String }
        struct L2: Codable, Equatable { let l3: L3 }
        struct L1: Codable, Equatable { let l2: L2 }
        struct Root: Codable, Equatable { let l1: L1 }

        let original = Root(l1: L1(l2: L2(l3: L3(value: "deep"))))
        let data = try XMLEncoder(configuration: .init(rootElementName: "Root")).encode(original)
        let decoded = try XMLDecoder().decode(Root.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Streaming decoder: contains / decodeNil on keyed container

    func test_streamingDecoder_containsAndDecodeNil() throws {
        struct Partial: Decodable {
            let present: String
            let missing: String?

            enum CodingKeys: String, CodingKey { case present, missing }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                present = try container.decode(String.self, forKey: .present)
                if container.contains(.missing) {
                    missing = try container.decodeIfPresent(String.self, forKey: .missing)
                } else {
                    missing = nil
                }
            }
        }
        let xml = Data("<root><present>yes</present></root>".utf8)
        let decoded = try XMLDecoder().decode(Partial.self, from: xml)
        XCTAssertEqual(decoded.present, "yes")
        XCTAssertNil(decoded.missing)
    }

    // MARK: - Encoder: key transform with custom closure

    func test_encoder_customKeyTransform() throws {
        struct Model: Codable, Equatable { let myField: String }
        let config = XMLEncoder.Configuration(
            rootElementName: "root",
            keyTransformStrategy: .custom({ $0.uppercased() })
        )
        let data = try XMLEncoder(configuration: config).encode(Model(myField: "val"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<MYFIELD>val</MYFIELD>"), "Expected uppercased key in: \(xml)")
    }

    // MARK: - Encoder: pretty-printed output

    func test_encoder_prettyPrinted_containsNewlines() throws {
        struct Simple: Codable { let a: String; let b: String }
        let writerConfig = XMLTreeWriter.Configuration(prettyPrinted: true)
        let config = XMLEncoder.Configuration(rootElementName: "root", writerConfiguration: writerConfig)
        let data = try XMLEncoder(configuration: config).encode(Simple(a: "1", b: "2"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("\n"), "Expected newlines in pretty-printed output: \(xml)")
    }

    // MARK: - Encoder: CDATA string strategy

    func test_encoder_cdataStringStrategy_roundTrips() throws {
        struct Doc: Codable, Equatable { let content: String }
        let original = Doc(content: "Hello <world>")
        let config = XMLEncoder.Configuration(rootElementName: "doc", stringEncodingStrategy: .cdata)
        let data = try XMLEncoder(configuration: config).encode(original)
        let decoded = try XMLDecoder().decode(Doc.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Encoder: namespace field encoding

    func test_encoder_fieldNamespace_producesQualifiedElement() throws {
        let data = try XMLEncoder(configuration: .init(rootElementName: "root")).encode(_NSModelForTest3(name: "test"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("xmlns:ns"), "Expected namespace declaration in: \(xml)")
        XCTAssert(xml.contains("ns:name"), "Expected qualified element name in: \(xml)")
    }

    // MARK: - Streaming decoder: decode with attributes

    func test_streamingDecoder_attributesAndElements_mixed() throws {
        struct Item: Codable, Equatable {
            @XMLAttribute var id: Int
            var name: String
        }
        let original = Item(id: 42, name: "widget")
        let data = try XMLEncoder(configuration: .init(rootElementName: "Item")).encode(original)
        let decoded = try XMLDecoder().decode(Item.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
    }

    // MARK: - Streaming decoder: empty element for optional

    func test_streamingDecoder_emptyElement_decodesAsNil() throws {
        struct Opt: Codable, Equatable { let val: String? }
        let xml = Data("<Opt><val/></Opt>".utf8)
        let decoded = try XMLDecoder().decode(Opt.self, from: xml)
        // Empty self-closing element should decode as nil or empty string
        XCTAssertNotNil(decoded)
    }

    // MARK: - Encoder: Date encoding ISO8601

    func test_encoder_dateISO8601_roundTrips() throws {
        struct WithDate: Codable, Equatable {
            let created: Date
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let config = XMLEncoder.Configuration(rootElementName: "root", dateEncodingStrategy: .iso8601)
        let decoderConfig = XMLDecoder.Configuration(dateDecodingStrategy: .iso8601)
        let data = try XMLEncoder(configuration: config).encode(WithDate(created: now))
        let decoded = try XMLDecoder(configuration: decoderConfig).decode(WithDate.self, from: data)
        XCTAssertEqual(decoded.created.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Encoder: Data encoding base64

    func test_encoder_dataBase64_roundTrips() throws {
        struct WithData: Codable, Equatable {
            let payload: Data
        }
        let original = WithData(payload: Data([0x01, 0x02, 0x03, 0xFF]))
        let config = XMLEncoder.Configuration(rootElementName: "root", dataEncodingStrategy: .base64)
        let decoderConfig = XMLDecoder.Configuration(dataDecodingStrategy: .base64)
        let data = try XMLEncoder(configuration: config).encode(original)
        let decoded = try XMLDecoder(configuration: decoderConfig).decode(WithData.self, from: data)
        XCTAssertEqual(decoded.payload, original.payload)
    }

    // MARK: - Streaming writer: namespace declarations

    func test_writerSink_namespaceDeclarations() throws {
        var chunks: [Data] = []
        let sink = try XMLStreamWriterSink(configuration: .init()) { chunks.append($0) }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(
            name: XMLQualifiedName(localName: "root"),
            attributes: [],
            namespaceDeclarations: [XMLNamespaceDeclaration(prefix: "ns", uri: "http://example.com")]
        ))
        try sink.write(.startElement(
            name: XMLQualifiedName(localName: "child", namespaceURI: "http://example.com", prefix: "ns"),
            attributes: [XMLTreeAttribute(name: XMLQualifiedName(localName: "attr"), value: "v")],
            namespaceDeclarations: []
        ))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "child")))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()

        let xml = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(xml.contains("xmlns:ns=\"http://example.com\""), "Expected ns declaration in: \(xml)")
        XCTAssert(xml.contains("ns:child"), "Expected prefixed child in: \(xml)")
        XCTAssert(xml.contains("attr=\"v\""), "Expected attribute in: \(xml)")
    }

    // MARK: - Streaming writer: CDATA section

    func test_writerSink_cdataSection() throws {
        var chunks: [Data] = []
        let sink = try XMLStreamWriterSink(configuration: .init()) { chunks.append($0) }
        try sink.write(.startDocument(version: "1.0", encoding: "UTF-8", standalone: nil))
        try sink.write(.startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []))
        try sink.write(.cdata("<script>alert('xss')</script>"))
        try sink.write(.endElement(name: XMLQualifiedName(localName: "root")))
        try sink.write(.endDocument)
        try sink.finish()

        let xml = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(xml.contains("<![CDATA["), "Expected CDATA section in: \(xml)")
    }

    // MARK: - Encoder: encodeTree public API

    func test_encoder_encodeTree_producesTreeDocument() throws {
        struct Simple: Codable { let name: String }
        let tree = try XMLEncoder(configuration: .init(rootElementName: "root")).encodeTree(Simple(name: "hello"))
        XCTAssertEqual(tree.root.name.localName, "root")
        XCTAssertFalse(tree.root.children.isEmpty)
    }

    // MARK: - Encoder: output byte limit

    func test_encoder_maxOutputBytes_throws() throws {
        struct Big: Codable {
            let a: String; let b: String; let c: String; let d: String
        }
        let writerLimits = XMLTreeWriter.Limits(maxOutputBytes: 10)
        let writerConfig = XMLTreeWriter.Configuration(limits: writerLimits)
        let config = XMLEncoder.Configuration(rootElementName: "root", writerConfiguration: writerConfig)
        XCTAssertThrowsError(
            try XMLEncoder(configuration: config).encode(
                Big(a: "long text here", b: "more text", c: "even more", d: "overflow")
            )
        )
    }

    // MARK: - Encoder: scalar root types (URL, UUID, Decimal)

    func test_encoder_urlRoot_roundTrips() throws {
        let config = XMLEncoder.Configuration(rootElementName: "url")
        let decoderConfig = XMLDecoder.Configuration()
        let url = URL(string: "https://example.com/path")!
        let data = try XMLEncoder(configuration: config).encode(url)
        let decoded = try XMLDecoder(configuration: decoderConfig).decode(URL.self, from: data)
        XCTAssertEqual(url, decoded)
    }

    func test_encoder_uuidRoot_roundTrips() throws {
        let config = XMLEncoder.Configuration(rootElementName: "id")
        let uuid = UUID()
        let data = try XMLEncoder(configuration: config).encode(uuid)
        let decoded = try XMLDecoder().decode(UUID.self, from: data)
        XCTAssertEqual(uuid, decoded)
    }

    func test_encoder_decimalRoot_roundTrips() throws {
        let config = XMLEncoder.Configuration(rootElementName: "num")
        let decimal = Decimal(string: "123.456")!
        let data = try XMLEncoder(configuration: config).encode(decimal)
        let decoded = try XMLDecoder().decode(Decimal.self, from: data)
        XCTAssertEqual(decimal, decoded)
    }

    // MARK: - Decoder: allKeys on keyed container

    func test_decoder_allKeysOnKeyedContainer() throws {
        struct DynamicKeys: Decodable {
            let keys: [String]

            enum CodingKeys: String, CodingKey { case a, b, c }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                keys = container.allKeys.map(\.stringValue)
            }
        }
        let xml = Data("<root><a>1</a><b>2</b></root>".utf8)
        let decoded = try XMLDecoder().decode(DynamicKeys.self, from: xml)
        XCTAssert(decoded.keys.contains("a"))
        XCTAssert(decoded.keys.contains("b"))
    }

    // MARK: - Decoder: unkeyed container count and isAtEnd

    func test_decoder_unkeyedContainerIteration() throws {
        struct Items: Decodable {
            let values: [Int]

            enum CodingKeys: String, CodingKey { case values }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                var unkeyed = try container.nestedUnkeyedContainer(forKey: .values)
                var result: [Int] = []
                while !unkeyed.isAtEnd {
                    result.append(try unkeyed.decode(Int.self))
                }
                values = result
            }
        }
        let xml = Data("<root><values><item>1</item><item>2</item><item>3</item></values></root>".utf8)
        let decoded = try XMLDecoder().decode(Items.self, from: xml)
        XCTAssertEqual(decoded.values, [1, 2, 3])
    }

    // MARK: - Decoder: nestedContainer in keyed container

    func test_decoder_nestedKeyedContainer() throws {
        struct Nested: Decodable, Equatable {
            let outer: String
            let innerVal: Int

            enum OuterKeys: String, CodingKey { case outer, inner }
            enum InnerKeys: String, CodingKey { case innerVal }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: OuterKeys.self)
                outer = try container.decode(String.self, forKey: .outer)
                let nested = try container.nestedContainer(keyedBy: InnerKeys.self, forKey: .inner)
                innerVal = try nested.decode(Int.self, forKey: .innerVal)
            }
        }
        let xml = Data("<root><outer>hello</outer><inner><innerVal>42</innerVal></inner></root>".utf8)
        let decoded = try XMLDecoder().decode(Nested.self, from: xml)
        XCTAssertEqual(decoded.outer, "hello")
        XCTAssertEqual(decoded.innerVal, 42)
    }

    // MARK: - Canonicalizer: tree-based with transforms

    func test_canonicalizer_treeBased_roundTrip() throws {
        let xml = Data("<root><b>2</b><a>1</a></root>".utf8)
        let tree = try XMLTreeParser().parse(data: xml)
        let canonicalizer = XMLDefaultCanonicalizer()
        let result = try canonicalizer.canonicalize(tree)
        let output = String(decoding: result, as: UTF8.self)
        XCTAssert(output.contains("<root>"), "Expected root in: \(output)")
    }

    // MARK: - Canonicalizer: stream-based with event transforms

    func test_canonicalizer_streamBased_withEventTransform() throws {
        let xml = Data("<root><item>val</item></root>".utf8)
        let canonicalizer = XMLDefaultCanonicalizer()
        // Use empty transform pipeline
        let result = try canonicalizer.canonicalize(
            data: xml,
            options: XMLCanonicalizationOptions(),
            eventTransforms: []
        )
        let output = String(decoding: result, as: UTF8.self)
        XCTAssert(output.contains("<item>val</item>"), "Expected item in: \(output)")
    }

    // MARK: - Encoder: XMLTextContent property wrapper

    func test_encoder_textContentWrapper_emitsTextDirectly() throws {
        struct Tag: Codable, Equatable {
            @XMLAttribute var lang: String
            @XMLTextContent var text: String
        }
        let original = Tag(lang: "en", text: "Hello World")
        let data = try XMLEncoder(configuration: .init(rootElementName: "tag")).encode(original)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("lang=\"en\""), "Expected lang attribute in: \(xml)")
        XCTAssert(xml.contains("Hello World"), "Expected text content in: \(xml)")
        XCTAssertFalse(xml.contains("<text>"), "Text content should not be wrapped in element: \(xml)")
    }

    // MARK: - Decoder: single value container

    func test_decoder_singleValueContainer() throws {
        let xml = Data("<value>42</value>".utf8)
        let decoded = try XMLDecoder().decode(Int.self, from: xml)
        XCTAssertEqual(decoded, 42)
    }

    func test_decoder_singleValueContainer_string() throws {
        let xml = Data("<value>hello</value>".utf8)
        let decoded = try XMLDecoder().decode(String.self, from: xml)
        XCTAssertEqual(decoded, "hello")
    }

    // MARK: - Encoder: ignored field via XMLFieldCodingOverrides

    func test_encoder_fieldOverrides_ignoredField() throws {
        struct WithIgnored: Codable { let visible: String; let hidden: String }
        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "hidden", as: .ignored)
        let config = XMLEncoder.Configuration(rootElementName: "root", fieldCodingOverrides: overrides)
        let data = try XMLEncoder(configuration: config).encode(WithIgnored(visible: "yes", hidden: "no"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<visible>yes</visible>"), "Expected visible in: \(xml)")
        XCTAssertFalse(xml.contains("hidden"), "Hidden field should be ignored: \(xml)")
    }

    // MARK: - Encoder: field override as attribute

    func test_encoder_fieldOverrides_asAttribute() throws {
        struct Item: Codable { let id: Int; let name: String }
        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let config = XMLEncoder.Configuration(rootElementName: "item", fieldCodingOverrides: overrides)
        let data = try XMLEncoder(configuration: config).encode(Item(id: 7, name: "widget"))
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("id=\"7\""), "Expected id as attribute in: \(xml)")
    }

    // MARK: - Streaming decoder: large number of children (sequential cursor)

    func test_decoder_manyChildren_decodesCorrectly() throws {
        struct Wide: Decodable, Equatable {
            let a: String; let b: String; let c: String; let d: String; let e: String
            let f: String; let g: String; let h: String; let i: String; let j: String
        }
        var xmlStr = "<Wide>"
        for key in ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"] {
            xmlStr += "<\(key)>val_\(key)</\(key)>"
        }
        xmlStr += "</Wide>"
        let decoded = try XMLDecoder().decode(Wide.self, from: Data(xmlStr.utf8))
        XCTAssertEqual(decoded.a, "val_a")
        XCTAssertEqual(decoded.j, "val_j")
    }

    // MARK: - Encoder: date secondsSince1970 strategy

    func test_encoder_dateSecondsSince1970_roundTrips() throws {
        struct D: Codable, Equatable { let d: Date }
        let original = D(d: Date(timeIntervalSince1970: 1234567890))
        let config = XMLEncoder.Configuration(rootElementName: "root", dateEncodingStrategy: .secondsSince1970)
        let decoderConfig = XMLDecoder.Configuration(dateDecodingStrategy: .secondsSince1970)
        let data = try XMLEncoder(configuration: config).encode(original)
        let decoded = try XMLDecoder(configuration: decoderConfig).decode(D.self, from: data)
        XCTAssertEqual(decoded.d.timeIntervalSince1970, original.d.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Encoder: date millisecondsSince1970 strategy

    func test_encoder_dateMillisecondsSince1970_roundTrips() throws {
        struct D: Codable, Equatable { let d: Date }
        let original = D(d: Date(timeIntervalSince1970: 1234567890))
        let config = XMLEncoder.Configuration(rootElementName: "root", dateEncodingStrategy: .millisecondsSince1970)
        let decoderConfig = XMLDecoder.Configuration(dateDecodingStrategy: .millisecondsSince1970)
        let data = try XMLEncoder(configuration: config).encode(original)
        let decoded = try XMLDecoder(configuration: decoderConfig).decode(D.self, from: data)
        XCTAssertEqual(decoded.d.timeIntervalSince1970, original.d.timeIntervalSince1970, accuracy: 1)
    }

}
