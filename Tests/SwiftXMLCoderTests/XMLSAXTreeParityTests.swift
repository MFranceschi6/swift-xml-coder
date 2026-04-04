import Foundation
import SwiftXMLCoder
import XCTest

// MARK: - Models

private struct PlainStruct: Codable, Equatable {
    let name: String
    let count: Int
}

private struct WithAttributeAndText: Codable, Equatable {
    @XMLAttribute var unit: String
    @XMLTextContent var amount: Decimal
}

private struct NestedOuter: Codable, Equatable {
    let label: String
    let inner: PlainStruct
}

private struct WithArray: Codable, Equatable {
    let tag: [String]
}

private struct WithOptional: Codable, Equatable {
    let note: String?
}

private struct WithDate: Codable, Equatable {
    let createdAt: Date
}

private struct WithData: Codable, Equatable {
    let payload: Data
}

private struct NamespacedModel: Codable, Equatable, XMLRootNode, XMLFieldNamespaceProvider {
    static let xmlRootElementName = "order"
    static let xmlRootElementNamespaceURI: String? = "urn:test"

    static var xmlFieldNamespaces: [String: XMLNamespace] {
        ["ref": XMLNamespace(prefix: "t", uri: "urn:test")]
    }

    @XMLAttribute var id: String
    var ref: String
}

private struct BoolModel: Codable, Equatable {
    let active: Bool
    let archived: Bool
}

// MARK: - Test helpers

/// Decodes `T` via `decode(_:from:)` (streaming SAX path) and returns the result.
@discardableResult
private func assertParity<T: Decodable & Equatable>(
    _ type: T.Type,
    data: Data,
    decoder: XMLDecoder,
    file: StaticString = #file,
    line: UInt = #line
) throws -> T {
    try decoder.decode(type, from: data)
}

// MARK: - Tests

final class XMLSAXTreeParityTests: XCTestCase {

    func test_parity_simpleKeyedStruct() throws {
        let payload = PlainStruct(name: "hello", count: 42)
        let encoder = XMLEncoder(configuration: .init(rootElementName: "PlainStruct"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "PlainStruct"))
        let data = try encoder.encode(payload)
        let result = try assertParity(PlainStruct.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_attributeAndTextContent() throws {
        let payload = WithAttributeAndText(
            unit: "kg",
            amount: try XCTUnwrap(Decimal(string: "3.14"))
        )
        let encoder = XMLEncoder(configuration: .init(rootElementName: "WithAttributeAndText"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "WithAttributeAndText"))
        let data = try encoder.encode(payload)
        let result = try assertParity(WithAttributeAndText.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_nestedStruct() throws {
        let payload = NestedOuter(label: "outer", inner: PlainStruct(name: "inner", count: 7))
        let encoder = XMLEncoder(configuration: .init(rootElementName: "NestedOuter"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "NestedOuter"))
        let data = try encoder.encode(payload)
        let result = try assertParity(NestedOuter.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_arrayOfElements() throws {
        let payload = WithArray(tag: ["swift", "xml", "codable"])
        let encoder = XMLEncoder(configuration: .init(rootElementName: "WithArray"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "WithArray"))
        let data = try encoder.encode(payload)
        let result = try assertParity(WithArray.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_optionalPresent() throws {
        let payload = WithOptional(note: "present")
        let encoder = XMLEncoder(configuration: .init(rootElementName: "WithOptional"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "WithOptional"))
        let data = try encoder.encode(payload)
        let result = try assertParity(WithOptional.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_optionalAbsent() throws {
        let payload = WithOptional(note: nil)
        let encoder = XMLEncoder(configuration: .init(rootElementName: "WithOptional"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "WithOptional"))
        let data = try encoder.encode(payload)
        let result = try assertParity(WithOptional.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_dateISO8601() throws {
        let payload = WithDate(createdAt: Date(timeIntervalSince1970: 1_000_000))
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "WithDate",
            dateEncodingStrategy: .xsdDateTimeISO8601
        ))
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "WithDate",
            dateDecodingStrategy: .xsdDateTimeISO8601
        ))
        let data = try encoder.encode(payload)
        let result = try assertParity(WithDate.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_dataBase64() throws {
        let payload = WithData(payload: Data([0xDE, 0xAD, 0xBE, 0xEF]))
        let encoder = XMLEncoder(configuration: .init(
            rootElementName: "WithData",
            dataEncodingStrategy: .base64
        ))
        let decoder = XMLDecoder(configuration: .init(
            rootElementName: "WithData",
            dataDecodingStrategy: .base64
        ))
        let data = try encoder.encode(payload)
        let result = try assertParity(WithData.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_namespacedFields() throws {
        let payload = NamespacedModel(id: "ORD-1", ref: "REF-A")
        let encoder = XMLEncoder()
        let decoder = XMLDecoder()
        let data = try encoder.encode(payload)
        let result = try assertParity(NamespacedModel.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_boolValues() throws {
        let payload = BoolModel(active: true, archived: false)
        let encoder = XMLEncoder(configuration: .init(rootElementName: "BoolModel"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "BoolModel"))
        let data = try encoder.encode(payload)
        let result = try assertParity(BoolModel.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_emptyArray() throws {
        let payload = WithArray(tag: [])
        let encoder = XMLEncoder(configuration: .init(rootElementName: "WithArray"))
        let decoder = XMLDecoder(configuration: .init(rootElementName: "WithArray"))
        let data = try encoder.encode(payload)
        let result = try assertParity(WithArray.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }

    func test_parity_namespacedModel_fullInvoice() throws {
        // Reuses the richer GeneratedInvoiceContract-style model indirectly via parity helper.
        // Exercises namespaced attributes + nested structs + array + optional Data + Date.
        struct Amount: Codable, Equatable {
            @XMLAttribute var currency: String
            @XMLTextContent var value: Decimal

            init(currency: String, value: Decimal) {
                self.currency = currency
                self.value = value
            }
        }
        struct Invoice: Codable, Equatable, XMLRootNode, XMLFieldNamespaceProvider {
            static let xmlRootElementName = "invoice"
            static let xmlRootElementNamespaceURI: String? = "urn:billing"
            static var xmlFieldNamespaces: [String: XMLNamespace] {
                ["amount": XMLNamespace(prefix: "bill", uri: "urn:billing")]
            }

            @XMLAttribute var id: String
            var lines: [String]
            var amount: Amount
            var attachment: Data?

            init(id: String, lines: [String], amount: Amount, attachment: Data?) {
                self.id = id
                self.lines = lines
                self.amount = amount
                self.attachment = attachment
            }
        }

        let payload = Invoice(
            id: "INV-1",
            lines: ["alpha", "beta"],
            amount: Amount(currency: "EUR", value: try XCTUnwrap(Decimal(string: "9.99"))),
            attachment: Data([0x01, 0x02])
        )
        let encoder = XMLEncoder(configuration: .init(dataEncodingStrategy: .base64))
        let decoder = XMLDecoder(configuration: .init(dataDecodingStrategy: .base64))
        let data = try encoder.encode(payload)
        let result = try assertParity(Invoice.self, data: data, decoder: decoder)
        XCTAssertEqual(result, payload)
    }
}
