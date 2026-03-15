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
    @XMLElement let name: String
}
#endif

final class XMLFieldMappingTests: XCTestCase {
    func test_wrappers_encodeAndDecode_attributeAndElementMapping() throws {
        struct Payload: Codable, Equatable {
            @SwiftXMLCoder.XMLAttribute var id: Int
            @SwiftXMLCoder.XMLElement var name: String

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

    private func firstChild(named name: String, in element: XMLTreeElement) -> XMLTreeElement? {
        element.children.compactMap { node -> XMLTreeElement? in
            guard case .element(let child) = node else {
                return nil
            }
            return child
        }.first(where: { $0.name.localName == name })
    }
}
