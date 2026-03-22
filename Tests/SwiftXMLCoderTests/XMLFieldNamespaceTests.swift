import Foundation
import SwiftXMLCoder
import XCTest
#if canImport(SwiftXMLCoderMacros)
import SwiftXMLCoderMacros
#endif

// MARK: - Manual-conformance test fixtures

private struct SoapEnvelope: Codable, Equatable, XMLFieldNamespaceProvider {
    var body: String

    static var xmlFieldNamespaces: [String: XMLNamespace] {
        ["body": XMLNamespace(prefix: "soap", uri: "http://schemas.xmlsoap.org/soap/envelope/")]
    }
}

private struct DefaultNSFields: Codable, Equatable, XMLFieldNamespaceProvider {
    var title: String

    static var xmlFieldNamespaces: [String: XMLNamespace] {
        ["title": XMLNamespace(uri: "http://purl.org/dc/elements/1.1/")]
    }
}

private struct NamespacedAttrFixture: Codable, Equatable,
    XMLFieldCodingOverrideProvider, XMLFieldNamespaceProvider {

    var id: String

    static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] { ["id": .attribute] }

    static var xmlFieldNamespaces: [String: XMLNamespace] {
        ["id": XMLNamespace(prefix: "wsa", uri: "http://www.w3.org/2005/08/addressing")]
    }
}

private struct MixedFields: Codable, Equatable, XMLFieldNamespaceProvider {
    var plain: String
    var qualified: String

    static var xmlFieldNamespaces: [String: XMLNamespace] {
        ["qualified": XMLNamespace(prefix: "ex", uri: "http://example.com/")]
    }
}

// MARK: - Macro test fixtures (Swift 5.9+ only)

#if canImport(SwiftXMLCoderMacros)

@XMLCodable
private struct MacroNamespacedChild: Codable, Equatable {
    @XMLFieldNamespace(prefix: "ns", uri: "http://test.example.com/")
    @XMLChild var value: String
}

@XMLCodable
private struct MacroDefaultNamespace: Codable, Equatable {
    @XMLFieldNamespace(uri: "http://default.example.com/")
    var item: String
}

#endif

// MARK: - Tests

final class XMLFieldNamespaceTests: XCTestCase {

    // MARK: Encoding — prefixed namespace on child element

    func test_encode_prefixedNamespace_emitsQualifiedElement() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Envelope"))
        let data = try encoder.encode(SoapEnvelope(body: "hello"))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("xmlns:soap=\"http://schemas.xmlsoap.org/soap/envelope/\""),
                      "Expected xmlns:soap declaration; got: \(xml)")
        XCTAssertTrue(xml.contains("soap:body"),
                      "Expected soap:body element; got: \(xml)")
        XCTAssertTrue(xml.contains("hello"), "Expected content value; got: \(xml)")
    }

    // MARK: Encoding — default namespace (no prefix) on child element

    func test_encode_defaultNamespace_emitsXmlnsDeclaration() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try encoder.encode(DefaultNSFields(title: "Swift"))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("xmlns=\"http://purl.org/dc/elements/1.1/\""),
                      "Expected default xmlns declaration; got: \(xml)")
        XCTAssertTrue(xml.contains("<title>") || xml.contains("title"),
                      "Expected title element; got: \(xml)")
    }

    // MARK: Encoding — prefixed namespace on attribute

    func test_encode_prefixedNamespaceOnAttribute_emitsQualifiedAttribute() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Item"))
        let data = try encoder.encode(NamespacedAttrFixture(id: "urn:uuid:abc"))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("wsa:id") || xml.contains("xmlns:wsa"),
                      "Expected wsa:id attribute or xmlns:wsa declaration; got: \(xml)")
        XCTAssertTrue(xml.contains("urn:uuid:abc"), "Expected attribute value; got: \(xml)")
    }

    // MARK: Encoding — mixed namespaced and plain fields

    func test_encode_mixedFields_onlyQualifiedFieldIsNamespaced() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Mix"))
        let data = try encoder.encode(MixedFields(plain: "abc", qualified: "xyz"))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("<plain>abc</plain>"),
                      "Plain field should be unqualified; got: \(xml)")
        XCTAssertTrue(xml.contains("ex:qualified"),
                      "Qualified field should carry prefix; got: \(xml)")
        XCTAssertTrue(xml.contains("xmlns:ex=\"http://example.com/\""),
                      "Namespace declaration should appear; got: \(xml)")
    }

    // MARK: Tree-level — correct namespaceURI on element

    func test_encodeTree_prefixedField_elementHasCorrectNamespaceURI() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Envelope"))
        let tree = try encoder.encodeTree(SoapEnvelope(body: "test"))

        let bodyEl = tree.root.children.compactMap { (child: XMLTreeNode) -> XMLTreeElement? in
            if case .element(let el) = child { return el } else { return nil }
        }.first(where: { $0.name.localName == "body" })

        XCTAssertNotNil(bodyEl, "Expected child element named 'body'")
        XCTAssertEqual(bodyEl?.name.namespaceURI,
                       "http://schemas.xmlsoap.org/soap/envelope/")
        XCTAssertEqual(bodyEl?.name.prefix, "soap")
    }

    // MARK: Tree-level — namespace declaration on parent

    func test_encodeTree_namespaceDeclarationAddedToParent() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Envelope"))
        let tree = try encoder.encodeTree(SoapEnvelope(body: "test"))

        let hasDecl = tree.root.namespaceDeclarations.contains {
            $0.prefix == "soap" && $0.uri == "http://schemas.xmlsoap.org/soap/envelope/"
        }
        XCTAssertTrue(hasDecl, "Expected xmlns:soap on root; got: \(tree.root.namespaceDeclarations)")
    }

    // MARK: Round-trips

    func test_roundTrip_prefixedNamespacedChild_decodesCorrectly() throws {
        let original = SoapEnvelope(body: "world")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Envelope"))
        let data = try encoder.encode(original)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Envelope"))
        let decoded = try decoder.decode(SoapEnvelope.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_roundTrip_defaultNamespacedChild_decodesCorrectly() throws {
        let original = DefaultNSFields(title: "Architecture")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try encoder.encode(original)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        let decoded = try decoder.decode(DefaultNSFields.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_roundTrip_mixedFields_decodesCorrectly() throws {
        let original = MixedFields(plain: "hello", qualified: "world")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try encoder.encode(original)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        let decoded = try decoder.decode(MixedFields.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: Regression — no namespace fields unchanged

    func test_regression_noNamespaceFieldsUnchanged() throws {
        struct Plain: Codable, Equatable {
            var name: String
        }
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try encoder.encode(Plain(name: "test"))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("<name>test</name>"),
                      "Plain field should encode unqualified; got: \(xml)")
        XCTAssertFalse(xml.contains("xmlns"), "No namespace declarations expected; got: \(xml)")
    }

    // MARK: Macro-path tests

    #if canImport(SwiftXMLCoderMacros)

    func test_macro_xmlFieldNamespace_encodesWithPrefix() throws {
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try encoder.encode(MacroNamespacedChild(value: "hello"))
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.contains("xmlns:ns=\"http://test.example.com/\""),
                      "Expected xmlns:ns declaration; got: \(xml)")
        XCTAssertTrue(xml.contains("ns:value"),
                      "Expected ns:value element; got: \(xml)")
    }

    func test_macro_xmlFieldNamespace_roundTrip() throws {
        let original = MacroNamespacedChild(value: "world")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try encoder.encode(original)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        let decoded = try decoder.decode(MacroNamespacedChild.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_macro_defaultNamespace_roundTrip() throws {
        let original = MacroDefaultNamespace(item: "foo")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "Root"))
        let data = try encoder.encode(original)

        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        let decoded = try decoder.decode(MacroDefaultNamespace.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    #endif
}
