import Foundation
import SwiftXMLCoder
import XCTest

final class XMLEncoderTests: XCTestCase {
    func test_encodeTree_keyedAndNestedEncodable_buildsElementHierarchy() throws {
        struct Payload: Encodable {
            let id: Int
            let title: String
            let values: [Int]
        }

        let encoder = XMLEncoder(
            configuration: .init(rootElementName: "PayloadRoot")
        )
        let tree = try encoder.encodeTree(
            Payload(id: 42, title: "hello", values: [1, 2, 3])
        )

        XCTAssertEqual(tree.root.name.localName, "PayloadRoot")
        XCTAssertEqual(textForFirstChild(named: "id", in: tree.root), "42")
        XCTAssertEqual(textForFirstChild(named: "title", in: tree.root), "hello")

        guard let values = firstChild(named: "values", in: tree.root) else {
            return XCTFail("Expected 'values' element.")
        }
        let items = children(named: "item", in: values)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(textContent(of: items[0]), "1")
        XCTAssertEqual(textContent(of: items[1]), "2")
        XCTAssertEqual(textContent(of: items[2]), "3")
    }

    func test_encodeTree_singleValueEncodable_writesRootText() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Value"))
        let tree = try encoder.encodeTree("abc")

        XCTAssertEqual(tree.root.name.localName, "Value")
        XCTAssertEqual(tree.root.children, [.text("abc")])
    }

    func test_encodeTree_nilEncodingStrategy_emptyElement_preservesOptionalField() throws {
        struct ManualNilPayload: Encodable {
            let present: String

            enum CodingKeys: String, CodingKey {
                case present
                case missing
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(present, forKey: .present)
                try container.encodeNil(forKey: .missing)
            }
        }

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                nilEncodingStrategy: .emptyElement
            )
        )
        let tree = try encoder.encodeTree(
            ManualNilPayload(present: "ok")
        )

        XCTAssertEqual(textForFirstChild(named: "present", in: tree.root), "ok")
        guard let missing = firstChild(named: "missing", in: tree.root) else {
            return XCTFail("Expected empty 'missing' element.")
        }
        XCTAssertTrue(missing.children.isEmpty)
    }

    func test_encodeTree_nilEncodingStrategy_omitElement_dropsOptionalField() throws {
        struct ManualNilPayload: Encodable {
            let present: String

            enum CodingKeys: String, CodingKey {
                case present
                case missing
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(present, forKey: .present)
                try container.encodeNil(forKey: .missing)
            }
        }

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                nilEncodingStrategy: .omitElement
            )
        )
        let tree = try encoder.encodeTree(
            ManualNilPayload(present: "ok")
        )

        XCTAssertEqual(textForFirstChild(named: "present", in: tree.root), "ok")
        XCTAssertNil(firstChild(named: "missing", in: tree.root))
    }

    func test_encodeTree_rootElementName_isSanitizedForXMLSafety() throws {
        struct Sample: Encodable { let value: String }
        let encoder = XMLEncoder(
            configuration: .init(rootElementName: "  9 root name  ")
        )
        let tree = try encoder.encodeTree(Sample(value: "x"))

        XCTAssertEqual(tree.root.name.localName, "_9_root_name")
    }

    func test_encodeTree_rootElementName_usesXMLRootNodeWhenConfigurationIsUnset() throws {
        struct Payload: Encodable, XMLRootNode {
            static let xmlRootElementName = "ServiceEnvelope"
            let value: String
        }

        let encoder = XMLEncoder()
        let tree = try encoder.encodeTree(Payload(value: "ok"))

        XCTAssertEqual(tree.root.name.localName, "ServiceEnvelope")
    }

    func test_encodeTree_rootElementName_configurationOverridesXMLRootNode() throws {
        struct Payload: Encodable, XMLRootNode {
            static let xmlRootElementName = "ImplicitEnvelope"
            let value: String
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "ExplicitEnvelope"))
        let tree = try encoder.encodeTree(Payload(value: "ok"))

        XCTAssertEqual(tree.root.name.localName, "ExplicitEnvelope")
    }

    func test_encodeTree_rootElementName_fromXMLRootNode_isSanitizedForXMLSafety() throws {
        struct Payload: Encodable, XMLRootNode {
            static let xmlRootElementName = "9 Root Name"
            let value: String
        }

        let encoder = XMLEncoder()
        let tree = try encoder.encodeTree(Payload(value: "ok"))

        XCTAssertEqual(tree.root.name.localName, "_9_Root_Name")
    }

    func test_encodeTree_rootElementName_withEmptyXMLRootNode_throwsDeterministicError() throws {
        struct Payload: Encodable, XMLRootNode {
            static let xmlRootElementName = "   "
            let value: String
        }

        let encoder = XMLEncoder()
        XCTAssertThrowsError(try encoder.encodeTree(Payload(value: "ok"))) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed.")
            }
            XCTAssertTrue((message ?? "").contains("XML6_7_ROOT_NAME_EMPTY"))
        }
    }

    func test_encodeTree_dateAndDataStrategies_applyConfiguredScalarFormatting() throws {
        struct Payload: Encodable {
            let createdAt: Date
            let raw: Data
        }

        let date = Date(timeIntervalSince1970: 12.5)
        let payload = Payload(createdAt: date, raw: Data([0x41, 0x42]))
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                dateEncodingStrategy: .secondsSince1970,
                dataEncodingStrategy: .base64
            )
        )

        let tree = try encoder.encodeTree(payload)
        XCTAssertEqual(textForFirstChild(named: "createdAt", in: tree.root), "12.5")
        XCTAssertEqual(textForFirstChild(named: "raw", in: tree.root), "QUI=")
    }

    func test_encodeTree_dataEncodingStrategy_hex_emitsHexLexicalValue() throws {
        struct Payload: Encodable {
            let raw: Data
        }

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                dataEncodingStrategy: .hex
            )
        )

        let tree = try encoder.encodeTree(Payload(raw: Data([0x41, 0x42])))
        XCTAssertEqual(textForFirstChild(named: "raw", in: tree.root), "4142")
    }

    func test_encodeTree_dateEncodingStrategy_formatter_usesFoundationFormatterDescriptor() throws {
        struct Payload: Encodable {
            let createdAt: Date
        }

        let descriptor = XMLDateFormatterDescriptor(
            format: "yyyy/MM/dd HH:mm:ss",
            localeIdentifier: "en_US_POSIX",
            timeZoneIdentifier: "UTC"
        )
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                dateEncodingStrategy: .formatter(descriptor)
            )
        )

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let tree = try encoder.encodeTree(Payload(createdAt: date))
        XCTAssertEqual(textForFirstChild(named: "createdAt", in: tree.root), "2023/11/14 22:13:20")
    }

    func test_encodeTree_dateEncodingStrategy_custom_receivesContextAndReturnsLexicalValue() throws {
        struct Payload: Encodable {
            let createdAt: Date
        }

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                dateEncodingStrategy: .custom { date, context in
                    let seconds = Int(date.timeIntervalSince1970)
                    return "\(context.localName ?? "unknown"):\(seconds)"
                }
            )
        )

        let tree = try encoder.encodeTree(
            Payload(createdAt: Date(timeIntervalSince1970: 25))
        )
        XCTAssertEqual(textForFirstChild(named: "createdAt", in: tree.root), "createdAt:25")
    }

    func test_encode_writesParsableXMLData() throws {
        struct Payload: Encodable {
            let message: String
            let numbers: [Int]
        }

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Envelope",
                writerConfiguration: .init(prettyPrinted: false)
            )
        )
        let data = try encoder.encode(
            Payload(message: "hello", numbers: [7, 8])
        )

        let parser = XMLTreeParser()
        let parsed = try parser.parse(data: data)

        XCTAssertEqual(parsed.root.name.localName, "Envelope")
        XCTAssertEqual(textForFirstChild(named: "message", in: parsed.root), "hello")
        guard let numbers = firstChild(named: "numbers", in: parsed.root) else {
            return XCTFail("Expected numbers element.")
        }
        let items = children(named: "item", in: numbers)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(textContent(of: items[0]), "7")
        XCTAssertEqual(textContent(of: items[1]), "8")
    }

    // MARK: - POST-XML-6: itemElementName sanitization

    func test_encodeTree_itemElementName_withSpace_isSanitized() throws {
        // "item name" → makeXMLSafeName → "item_name"; must never reach libxml2 writer with a space.
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Root",
                itemElementName: "item name"
            )
        )
        let tree = try encoder.encodeTree([1, 2, 3])
        XCTAssertEqual(children(named: "item_name", in: tree.root).count, 3)
    }

    func test_encodeTree_itemElementName_validName_unchanged() throws {
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Root",
                itemElementName: "entry"
            )
        )
        let tree = try encoder.encodeTree([42])
        XCTAssertEqual(children(named: "entry", in: tree.root).count, 1)
    }

    func test_encodeTree_itemElementName_namespacePrefixed_stripsPrefix() throws {
        // "soap:item" must strip the namespace prefix → "item", not "soap_item".
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Root",
                itemElementName: "soap:item"
            )
        )
        let tree = try encoder.encodeTree([1, 2])
        XCTAssertEqual(children(named: "item", in: tree.root).count, 2)
    }

    // MARK: - POST-XML-6: CodingKey element name early validation

    func test_encodeTree_codingKeyWithWhitespace_throwsEarlyDiagnostic() throws {
        struct BadKeys: Encodable {
            enum CodingKeys: String, CodingKey {
                case field = "my field"
            }
            let field: String
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(field, forKey: .field)
            }
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try encoder.encodeTree(BadKeys(field: "v"))) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_FIELD_NAME_INVALID"))
        }
    }

    func test_encodeTree_codingKeyWithXMLMetacharacter_throwsEarlyDiagnostic() throws {
        struct BadKeys: Encodable {
            enum CodingKeys: String, CodingKey {
                case field = "a<b"
            }
            let field: Int
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(field, forKey: .field)
            }
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try encoder.encodeTree(BadKeys(field: 1))) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_FIELD_NAME_INVALID"))
        }
    }

    func test_encodeTree_encodeNil_invalidFieldName_throwsEarlyDiagnostic() throws {
        struct ManualNil: Encodable {
            enum CodingKeys: String, CodingKey {
                case bad = "bad&key"
            }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeNil(forKey: .bad)
            }
        }

        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "Root",
            nilEncodingStrategy: .emptyElement
        ))
        XCTAssertThrowsError(try encoder.encodeTree(ManualNil())) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_FIELD_NAME_INVALID"))
        }
    }

    func test_encodeTree_validCodingKeys_encodeSuccessfully() throws {
        struct Good: Encodable {
            enum CodingKeys: String, CodingKey {
                case firstName, lastName = "last_name", value123
            }
            let firstName: String
            let lastName: String
            let value123: Int
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Good"))
        XCTAssertNoThrow(try encoder.encodeTree(Good(firstName: "a", lastName: "b", value123: 1)))
    }

    // MARK: - POST-XML-7: NilEncodingStrategy semantics

    func test_encodeTree_synthesizedCodable_nilOptional_alwaysAbsentRegardlessOfStrategy() throws {
        struct S: Encodable { var name: String? }

        for strategy: XMLEncoder.NilEncodingStrategy in [.emptyElement, .omitElement] {
            let encoder = XMLEncoder(configuration: .init(
                rootElementName: "S",
                nilEncodingStrategy: strategy
            ))
            let tree = try encoder.encodeTree(S(name: nil))
            XCTAssertNil(
                firstChild(named: "name", in: tree.root),
                "Synthesised Codable nil optional must be absent with strategy .\(strategy)."
            )
        }
    }

    func test_encodeTree_encodeNilForAttributeKindField_alwaysOmitted() throws {
        // encodeNil(forKey:) for a field that resolves to .attribute kind must be silently
        // dropped regardless of NilEncodingStrategy — XML attributes have no empty-element form.
        struct S: Encodable {
            enum CodingKeys: String, CodingKey { case id, value }
            let value: String
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeNil(forKey: .id)   // "id" is an attribute via overrides
                try c.encode(value, forKey: .value)
            }
        }

        let overrides = XMLFieldCodingOverrides().setting(path: [], key: "id", as: .attribute)
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "S",
            fieldCodingOverrides: overrides,
            nilEncodingStrategy: .emptyElement
        ))
        let tree = try encoder.encodeTree(S(value: "v"))
        XCTAssertTrue(
            tree.root.attributes.isEmpty,
            "encodeNil for an attribute-kind field must always produce no attribute in output."
        )
        XCTAssertEqual(textForFirstChild(named: "value", in: tree.root), "v")
    }

    private func firstChild(named name: String, in element: XMLTreeElement) -> XMLTreeElement? {
        element.children.first { node in
            guard case .element(let child) = node else { return false }
            return child.name.localName == name
        }.flatMap { node in
            guard case .element(let child) = node else { return nil }
            return child
        }
    }

    private func children(named name: String, in element: XMLTreeElement) -> [XMLTreeElement] {
        element.children.compactMap { node in
            guard case .element(let child) = node, child.name.localName == name else {
                return nil
            }
            return child
        }
    }

    private func textForFirstChild(named name: String, in element: XMLTreeElement) -> String? {
        guard let child = firstChild(named: name, in: element) else {
            return nil
        }
        return textContent(of: child)
    }

    private func textContent(of element: XMLTreeElement) -> String? {
        element.children.first { node in
            if case .text = node { return true }
            return false
        }.flatMap { node in
            guard case .text(let value) = node else { return nil }
            return value
        }
    }
}
