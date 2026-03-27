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

    // MARK: - D.1: rootElementName strict validation

    func test_encodeTree_rootElementName_withSpace_strictPolicy_throwsEarlyDiagnostic() throws {
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "bad root",
            validationPolicy: .strict
        ))
        XCTAssertThrowsError(try encoder.encodeTree(["x"])) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_ROOT_NAME_INVALID"), "got: \(message ?? "")")
        }
    }

    func test_encodeTree_rootElementName_withDigitPrefix_strictPolicy_throwsEarlyDiagnostic() throws {
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "9Root",
            validationPolicy: .strict
        ))
        XCTAssertThrowsError(try encoder.encodeTree(["x"])) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_ROOT_NAME_INVALID"), "got: \(message ?? "")")
        }
    }

    func test_encodeTree_rootElementName_validName_strictPolicy_succeeds() throws {
        struct S: Encodable { let v: Int }
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root_1", validationPolicy: .strict))
        XCTAssertNoThrow(try encoder.encodeTree(S(v: 1)))
    }

    func test_encodeTree_xmlRootNode_invalidName_strictPolicy_throwsEarlyDiagnostic() throws {
        struct Bad: Encodable, XMLRootNode {
            static let xmlRootElementName = "bad name"
            let v: Int
        }
        let encoder = XMLEncoder(configuration: .init(validationPolicy: .strict))
        XCTAssertThrowsError(try encoder.encodeTree(Bad(v: 1))) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_ROOT_NAME_INVALID"), "got: \(message ?? "")")
        }
    }

    // MARK: - D.1: itemElementName strict validation

    func test_encodeTree_itemElementName_withSpace_strictPolicy_throwsEarlyDiagnostic() throws {
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "Root",
            itemElementName: "bad item",
            validationPolicy: .strict
        ))
        XCTAssertThrowsError(try encoder.encodeTree([1, 2])) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected XMLParsingError.parseFailed, got \(error).")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_ITEM_NAME_INVALID"), "got: \(message ?? "")")
        }
    }

    func test_encodeTree_itemElementName_validName_strictPolicy_succeeds() throws {
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "Root",
            itemElementName: "entry",
            validationPolicy: .strict
        ))
        XCTAssertNoThrow(try encoder.encodeTree([1, 2]))
    }

    // MARK: - D.1: lenient mode — invalid names are sanitized, not rejected

    func test_encodeTree_rootElementName_withSpace_lenientPolicy_sanitizesAndSucceeds() throws {
        struct S: Encodable { let v: Int }
        let encoder = XMLEncoder(configuration: .init(rootElementName: "bad root", validationPolicy: .lenient))
        let tree = try encoder.encodeTree(S(v: 1))
        XCTAssertEqual(tree.root.name.localName, "bad_root")
    }

    func test_encodeTree_itemElementName_withSpace_lenientPolicy_sanitizesAndSucceeds() throws {
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "Root",
            itemElementName: "bad item",
            validationPolicy: .lenient
        ))
        let tree = try encoder.encodeTree([1, 2])
        XCTAssertEqual(children(named: "bad_item", in: tree.root).count, 2)
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

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root", validationPolicy: .strict))
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

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root", validationPolicy: .strict))
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
            nilEncodingStrategy: .emptyElement,
            validationPolicy: .strict
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

    // MARK: - NilEncodingStrategy semantics

    func test_encodeTree_synthesizedCodable_nilOptional_respectsStrategy() throws {
        // H.2a: encodeIfPresent override makes nilEncodingStrategy work for synthesised Codable.
        struct S: Encodable { var name: String? }

        let emptyEncoder = XMLEncoder(configuration: .init(rootElementName: "S", nilEncodingStrategy: .emptyElement))
        let emptyTree = try emptyEncoder.encodeTree(S(name: nil))
        XCTAssertNotNil(
            firstChild(named: "name", in: emptyTree.root),
            ".emptyElement strategy should emit an empty <name/> for a nil synthesised optional"
        )

        let omitEncoder = XMLEncoder(configuration: .init(rootElementName: "S", nilEncodingStrategy: .omitElement))
        let omitTree = try omitEncoder.encodeTree(S(name: nil))
        XCTAssertNil(
            firstChild(named: "name", in: omitTree.root),
            ".omitElement strategy should omit nil synthesised optional entirely"
        )
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

    // MARK: - H.2a: nilEncodingStrategy on synthesised Codable optionals

    func test_encodeTree_nilEncodingStrategy_omitElement_synthesisedOptional_omitsField() throws {
        struct Address: Encodable {
            let street: String
            let line2: String?
            let city: String
        }

        let encoder = XMLEncoder(configuration: .init(nilEncodingStrategy: .omitElement))
        let tree = try encoder.encodeTree(Address(street: "Via Roma 1", line2: nil, city: "Milano"))

        XCTAssertNotNil(firstChild(named: "street", in: tree.root))
        XCTAssertNil(firstChild(named: "line2", in: tree.root), "nil field should be omitted with .omitElement")
        XCTAssertNotNil(firstChild(named: "city", in: tree.root))
    }

    func test_encodeTree_nilEncodingStrategy_emptyElement_synthesisedOptional_emitsEmptyElement() throws {
        struct Address: Encodable {
            let street: String
            let line2: String?
            let city: String
        }

        let encoder = XMLEncoder(configuration: .init(nilEncodingStrategy: .emptyElement))
        let tree = try encoder.encodeTree(Address(street: "Via Roma 1", line2: nil, city: "Milano"))

        guard let line2 = firstChild(named: "line2", in: tree.root) else {
            return XCTFail("Expected <line2/> element with .emptyElement strategy")
        }
        XCTAssertTrue(line2.children.isEmpty, "Element should be empty")
    }

    // MARK: - H.1: userInfo

    func test_encodeTree_userInfo_defaultIsEmpty() throws {
        let encoder = XMLEncoder()
        XCTAssertTrue(encoder.configuration.userInfo.isEmpty)
    }

    func test_encodeTree_userInfo_isForwardedToEncodableImplementation() throws {
        let infoKey = try XCTUnwrap(CodingUserInfoKey(rawValue: "test.greeting"))
        struct GreetingPayload: Encodable {
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                let greeting = encoder.userInfo[try XCTUnwrap(CodingUserInfoKey(rawValue: "test.greeting"))] as? String ?? "hello"
                try container.encode(greeting, forKey: .message)
            }
            enum CodingKeys: String, CodingKey { case message }
        }

        let encoder = XMLEncoder(configuration: .init(userInfo: [infoKey: "ciao"]))
        let tree = try encoder.encodeTree(GreetingPayload())
        let messageElement = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child, el.name.localName == "message" else { return nil }
            return el
        }.first
        XCTAssertNotNil(messageElement)
        let text = messageElement?.children.compactMap { child -> String? in
            guard case .text(let v) = child else { return nil }
            return v
        }.first
        XCTAssertEqual(text, "ciao")
    }

    // MARK: - H.4a: StringEncodingStrategy (global CDATA)

    func test_stringEncodingStrategy_default_emitsPlainText() throws {
        struct Article: Encodable { let body: String }
        let encoder = XMLEncoder()  // default: .text
        let tree = try encoder.encodeTree(Article(body: "Hello <world>"))
        let bodyEl = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child else { return nil }
            return el
        }.first
        XCTAssertNotNil(bodyEl)
        // Should be a plain text node, not CDATA
        let hasText = bodyEl?.children.contains { child in
            if case .text = child { return true }
            return false
        } ?? false
        let hasCDATA = bodyEl?.children.contains { child in
            if case .cdata = child { return true }
            return false
        } ?? false
        XCTAssertTrue(hasText, "Expected plain text node")
        XCTAssertFalse(hasCDATA, "Expected no CDATA node with default strategy")
    }

    func test_stringEncodingStrategy_cdata_emitsCDATANode() throws {
        struct Article: Encodable { let body: String }
        let encoder = XMLEncoder(configuration: .init(stringEncodingStrategy: .cdata))
        let tree = try encoder.encodeTree(Article(body: "Hello <world>"))
        let bodyEl = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child else { return nil }
            return el
        }.first
        XCTAssertNotNil(bodyEl)
        let cdataValue = bodyEl?.children.compactMap { child -> String? in
            if case .cdata(let v) = child { return v }
            return nil
        }.first
        XCTAssertEqual(cdataValue, "Hello <world>", "Expected CDATA node with string content")
    }

    func test_stringEncodingStrategy_cdata_serialisesToCDATASyntax() throws {
        struct Article: Encodable { let body: String }
        let encoder = XMLEncoder(configuration: .init(stringEncodingStrategy: .cdata))
        let data = try encoder.encode(Article(body: "Hello & <world>"))
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("<![CDATA["), "Expected CDATA section in serialised XML: \(xml)")
        XCTAssertTrue(xml.contains("Hello & <world>"), "CDATA content should be unescaped: \(xml)")
    }

    func test_stringEncodingStrategy_cdata_roundtrip() throws {
        struct Article: Codable, Equatable { let title: String; let body: String }
        let original = Article(title: "News", body: "<p>Hello &amp; World</p>")
        let encoder = XMLEncoder(configuration: .init(stringEncodingStrategy: .cdata))
        let decoder = XMLDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Article.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Event pipeline parity

    func test_encode_eventPipeline_roundTripsCorrectly() throws {
        struct Invoice: Codable, Equatable {
            let id: Int
            let customer: String
            let items: [Item]

            struct Item: Codable, Equatable {
                let sku: String
                let quantity: Int
            }
        }

        let original = Invoice(
            id: 99,
            customer: "ACME",
            items: [
                .init(sku: "ABC", quantity: 3),
                .init(sku: "DEF", quantity: 1)
            ]
        )

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Invoice"))
        let data = try encoder.encode(original)
        let decoded = try XMLDecoder().decode(Invoice.self, from: data)
        XCTAssertEqual(decoded, original)

        // Verify the output is well-formed XML by re-parsing it.
        var events: [XMLStreamEvent] = []
        try XMLStreamParser().parse(data: data) { events.append($0) }
        XCTAssertGreaterThan(events.count, 0)
    }
}
