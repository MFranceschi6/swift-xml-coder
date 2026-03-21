import Foundation
import SwiftXMLCoder
import XCTest
#if canImport(SwiftXMLCoderMacros)
import SwiftXMLCoderMacros
#endif

#if canImport(SwiftXMLCoderMacros)
@XMLCodable
private struct MacroMappedPayload: Codable, Equatable {
    @XMLAttribute let id: Int
    @XMLChild let name: String
}

@XMLCodable
@XMLRootNamespace("http://example.com/orders")
private struct MacroNamespacePayload: Codable, Equatable {
    var id: String
    var total: Double

    init(id: String, total: Double) {
        self.id = id
        self.total = total
    }
}

@XMLCodable
private struct MacroIgnorePayload: Codable, Equatable {
    var name: String
    var value: Int
    @XMLIgnore var cachedHash: Int? = nil

    init(name: String, value: Int) {
        self.name = name
        self.value = value
    }
}

@XMLCodable
private struct MacroTextPayload: Codable, Equatable {
    @XMLAttribute var currency: String
    @XMLText      var value: Double

    init(currency: String, value: Double) {
        self.currency = currency
        self.value = value
    }
}

@XMLCodable
private struct MacroTextOptional: Codable, Equatable {
    @XMLAttribute var id: String
    @XMLText      var label: String?

    init(id: String, label: String?) {
        self.id = id
        self.label = label
    }
}
#endif

final class XMLFieldMappingTests: XCTestCase {
    func test_wrappers_encodeAndDecode_attributeAndElementMapping() throws {
        struct Payload: Codable, Equatable {
            @SwiftXMLCoder.XMLAttribute var id: Int
            @SwiftXMLCoder.XMLChild var name: String

            init(id: Int, name: String) {
                self.id = id
                self.name = name
            }
        }

        let input = Payload(id: 42, name: "soap")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Payload"))
        let tree = try encoder.encodeTree(input)

        XCTAssertEqual(tree.root.attributes.count, 1)
        XCTAssertEqual(tree.root.attributes[0].name.localName, "id")
        XCTAssertEqual(tree.root.attributes[0].value, "42")
        XCTAssertEqual(firstChild(named: "name", in: tree.root)?.children, [.text("soap")])

        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let output = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(output, input)
    }

    func test_runtimeOverrides_encodeAndDecode_attributeMapping() throws {
        struct Payload: Codable, Equatable {
            let id: Int
            let name: String
        }

        let overrides = XMLFieldCodingOverrides()
            .setting(path: [], key: "id", as: .attribute)
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                fieldCodingOverrides: overrides
            )
        )

        let input = Payload(id: 9, name: "alpha")
        let tree = try encoder.encodeTree(input)
        XCTAssertEqual(tree.root.attributes.map(\.name.localName), ["id"])
        XCTAssertEqual(tree.root.attributes.first?.value, "9")
        XCTAssertEqual(firstChild(named: "name", in: tree.root)?.children, [.text("alpha")])

        let data = try encoder.encode(input)
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                fieldCodingOverrides: overrides
            )
        )
        let output = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(output, input)
    }

    func test_runtimeOverrides_nestedPath_encodesNestedAttribute() throws {
        struct Child: Codable, Equatable {
            let id: Int
        }

        struct Payload: Codable, Equatable {
            let child: Child
        }

        let overrides = XMLFieldCodingOverrides()
            .setting(path: ["child"], key: "id", as: .attribute)
        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                fieldCodingOverrides: overrides
            )
        )

        let tree = try encoder.encodeTree(Payload(child: Child(id: 17)))
        guard let child = firstChild(named: "child", in: tree.root) else {
            return XCTFail("Expected child element.")
        }
        XCTAssertEqual(child.attributes.map(\.name.localName), ["id"])
        XCTAssertEqual(child.attributes.first?.value, "17")
    }

    func test_attributeMapping_supportsDateCustomContext_withIsAttributeTrue() throws {
        struct Payload: Codable, Equatable {
            let timestamp: Date
        }

        let overrides = XMLFieldCodingOverrides()
            .setting(path: [], key: "timestamp", as: .attribute)

        let encoder = XMLEncoder(
            configuration: .init(
                rootElementName: "Payload",
                fieldCodingOverrides: overrides,
                dateEncodingStrategy: .custom { date, context in
                    let flag = context.isAttribute ? "attr" : "elem"
                    return "\(flag):\(Int(date.timeIntervalSince1970))"
                }
            )
        )
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Payload",
                fieldCodingOverrides: overrides,
                dateDecodingStrategy: .custom { lexical, context in
                    guard context.isAttribute,
                          lexical.hasPrefix("attr:"),
                          let seconds = Double(lexical.replacingOccurrences(of: "attr:", with: ""))
                    else {
                        throw XMLParsingError.parseFailed(message: "invalid custom attribute date")
                    }
                    return Date(timeIntervalSince1970: seconds)
                }
            )
        )

        let input = Payload(timestamp: Date(timeIntervalSince1970: 123))
        let data = try encoder.encode(input)
        let output = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(output, input)
    }

    func test_xmlAttributeWrapper_withNonScalarValue_throwsDeterministicError() throws {
        struct Child: Codable {
            let value: Int
        }

        struct Payload: Encodable {
            @SwiftXMLCoder.XMLAttribute var child: Child
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "Payload"))
        XCTAssertThrowsError(try encoder.encodeTree(Payload(child: Child(value: 1)))) { error in
            guard case let XMLParsingError.parseFailed(message) = error else {
                return XCTFail("Expected parseFailed.")
            }
            XCTAssertTrue((message ?? "").contains("XML6_6_ATTRIBUTE_ENCODE_UNSUPPORTED"))
        }
    }

    func test_macroMapping_encodeAndDecode_attributeAndElementMapping() throws {
#if canImport(SwiftXMLCoderMacros)
        let input = MacroMappedPayload(id: 12, name: "macro")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Payload"))
        let tree = try encoder.encodeTree(input)

        XCTAssertEqual(tree.root.attributes.count, 1)
        XCTAssertEqual(tree.root.attributes[0].name.localName, "id")
        XCTAssertEqual(tree.root.attributes[0].value, "12")
        XCTAssertEqual(firstChild(named: "name", in: tree.root)?.children, [.text("macro")])

        let data = try encoder.encode(input)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Payload"))
        let output = try decoder.decode(MacroMappedPayload.self, from: data)
        XCTAssertEqual(output, input)
#else
        throw XCTSkip("Macro module not available on this lane.")
#endif
    }

    // MARK: - @XMLRootNamespace tests

    func test_macroRootNamespace_encodesNamespaceOnRootElement() throws {
#if canImport(SwiftXMLCoderMacros)
        let encoder = XMLEncoder()
        let input = MacroNamespacePayload(id: "ORD-1", total: 99.9)
        let tree = try encoder.encodeTree(input)

        XCTAssertEqual(tree.root.name.localName, "MacroNamespacePayload")
        XCTAssertEqual(tree.root.name.namespaceURI, "http://example.com/orders")
#else
        throw XCTSkip("Macro module not available on this lane.")
#endif
    }

    func test_macroRootNamespace_roundTrip() throws {
#if canImport(SwiftXMLCoderMacros)
        let encoder = XMLEncoder()
        let decoder = XMLDecoder()
        let input = MacroNamespacePayload(id: "ORD-42", total: 12.5)
        let data = try encoder.encode(input)
        let output = try decoder.decode(MacroNamespacePayload.self, from: data)
        XCTAssertEqual(output, input)
#else
        throw XCTSkip("Macro module not available on this lane.")
#endif
    }

    // MARK: - @XMLIgnore / .ignored tests

    func test_ignoredField_runtimeOverride_isSkippedDuringEncode() throws {
        struct Config: Codable, Equatable {
            var host: String
            var port: Int
            var _secret: String?
        }

        let overrides = XMLFieldCodingOverrides()
            .setting(path: [], key: "_secret", as: .ignored)
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Config", fieldCodingOverrides: overrides))

        let input = Config(host: "localhost", port: 8080, _secret: "s3cr3t")
        let tree = try encoder.encodeTree(input)

        // _secret must not appear in the output.
        let childNames = tree.root.children.compactMap { node -> String? in
            guard case .element(let child) = node else { return nil }
            return child.name.localName
        }
        XCTAssertFalse(childNames.contains("_secret"), "Ignored field must not be serialised.")
        XCTAssertTrue(childNames.contains("host"))
        XCTAssertTrue(childNames.contains("port"))
    }

    func test_ignoredField_runtimeOverride_optionalDecodesAsNil() throws {
        struct Config: Codable, Equatable {
            var host: String
            var port: Int
            var computed: String?
        }

        let overrides = XMLFieldCodingOverrides()
            .setting(path: [], key: "computed", as: .ignored)
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Config", fieldCodingOverrides: overrides))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Config", fieldCodingOverrides: overrides))

        let input = Config(host: "localhost", port: 8080, computed: "will be ignored")
        let data = try encoder.encode(input)
        let output = try decoder.decode(Config.self, from: data)
        XCTAssertEqual(output.host, "localhost")
        XCTAssertEqual(output.port, 8080)
        XCTAssertNil(output.computed, "Ignored optional field must decode as nil.")
    }

    func test_macroIgnore_encodeAndDecode_fieldAbsentFromXML() throws {
#if canImport(SwiftXMLCoderMacros)
        let encoder = XMLEncoder(configuration: .init(rootElementName: "item"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "item"))

        let input = MacroIgnorePayload(name: "foo", value: 42)
        let data = try encoder.encode(input)

        let tree = try encoder.encodeTree(input)
        let childNames = tree.root.children.compactMap { node -> String? in
            guard case .element(let child) = node else { return nil }
            return child.name.localName
        }
        XCTAssertFalse(childNames.contains("cachedHash"), "Ignored field must not appear in XML.")
        XCTAssertTrue(childNames.contains("name"))
        XCTAssertTrue(childNames.contains("value"))

        let output = try decoder.decode(MacroIgnorePayload.self, from: data)
        XCTAssertEqual(output.name, input.name)
        XCTAssertEqual(output.value, input.value)
        XCTAssertNil(output.cachedHash, "Ignored optional field must be nil after decode.")
#else
        throw XCTSkip("Macro module not available on this lane.")
#endif
    }

    // MARK: - @XMLText / XMLTextContent tests

    func test_textContentWrapper_encodeAndDecode_roundTrip() throws {
        struct Price: Codable, Equatable {
            @SwiftXMLCoder.XMLAttribute var currency: String
            @SwiftXMLCoder.XMLTextContent var amount: Double

            init(currency: String, amount: Double) {
                self.currency = currency
                self.amount = amount
            }
        }

        let encoder = XMLEncoder(configuration: .init(rootElementName: "price"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "price"))

        let input = Price(currency: "USD", amount: 9.99)
        let data = try encoder.encode(input)

        // Verify the XML structure: attribute on root, text content on root.
        let tree = try encoder.encodeTree(input)
        XCTAssertEqual(tree.root.attributes.count, 1)
        XCTAssertEqual(tree.root.attributes[0].name.localName, "currency")
        XCTAssertEqual(tree.root.attributes[0].value, "USD")
        // No child elements — only text content.
        let childElements = tree.root.children.filter { if case .element = $0 { return true }; return false }
        XCTAssertTrue(childElements.isEmpty, "Expected no child elements, text content only.")
        // Text node present.
        let textNodes = tree.root.children.compactMap { node -> String? in
            guard case .text(let t) = node else { return nil }
            return t
        }
        XCTAssertFalse(textNodes.isEmpty, "Expected a text node for the amount.")

        let output = try decoder.decode(Price.self, from: data)
        XCTAssertEqual(output, input)
    }

    func test_textContentWrapper_decodesFromXML_withAttributeAndTextContent() throws {
        struct Price: Codable, Equatable {
            @SwiftXMLCoder.XMLAttribute var currency: String
            @SwiftXMLCoder.XMLTextContent var amount: Double

            init(currency: String, amount: Double) {
                self.currency = currency
                self.amount = amount
            }
        }

        let xml = Data("<price currency=\"EUR\">12.5</price>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "price"))
        let result = try decoder.decode(Price.self, from: xml)
        XCTAssertEqual(result.currency, "EUR")
        XCTAssertEqual(result.amount, 12.5)
    }

    func test_textContentWrapper_runtimeOverride_textContent() throws {
        struct Price: Codable, Equatable {
            let currency: String
            let amount: Double
        }

        let overrides = XMLFieldCodingOverrides()
            .setting(path: [], key: "currency", as: .attribute)
            .setting(path: [], key: "amount", as: .textContent)

        let encoder = XMLEncoder(configuration: .init(rootElementName: "price", fieldCodingOverrides: overrides))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "price", fieldCodingOverrides: overrides))

        let input = Price(currency: "GBP", amount: 7.0)
        let data = try encoder.encode(input)
        let output = try decoder.decode(Price.self, from: data)
        XCTAssertEqual(output, input)
    }

    func test_macroTextMapping_encodeAndDecode_roundTrip() throws {
#if canImport(SwiftXMLCoderMacros)
        let encoder = XMLEncoder(configuration: .init(rootElementName: "price"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "price"))

        let input = MacroTextPayload(currency: "JPY", value: 1500.0)
        let data = try encoder.encode(input)

        let tree = try encoder.encodeTree(input)
        XCTAssertEqual(tree.root.attributes.map(\.name.localName), ["currency"])
        // No child elements.
        let childElements = tree.root.children.filter { if case .element = $0 { return true }; return false }
        XCTAssertTrue(childElements.isEmpty)

        let output = try decoder.decode(MacroTextPayload.self, from: data)
        XCTAssertEqual(output, input)
#else
        throw XCTSkip("Macro module not available on this lane.")
#endif
    }

    func test_macroTextMapping_decodesFromHandwrittenXML() throws {
#if canImport(SwiftXMLCoderMacros)
        let xml = Data("<price currency=\"CHF\">42.0</price>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "price"))
        let result = try decoder.decode(MacroTextPayload.self, from: xml)
        XCTAssertEqual(result.currency, "CHF")
        XCTAssertEqual(result.value, 42.0)
#else
        throw XCTSkip("Macro module not available on this lane.")
#endif
    }

    private func firstChild(named name: String, in element: XMLTreeElement) -> XMLTreeElement? {
        element.children.compactMap { node -> XMLTreeElement? in
            guard case .element(let child) = node else {
                return nil
            }
            return child
        }.first(where: { $0.name.localName == name })
    }
}
