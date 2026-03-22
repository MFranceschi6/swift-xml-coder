import Foundation
import SwiftXMLCoder
import XCTest

private struct GeneratedAmountContract: Codable, Equatable {
    @XMLAttribute var currency: String
    @XMLTextContent var value: Decimal

    init(currency: String, value: Decimal) {
        self.currency = currency
        self.value = value
    }
}

private struct GeneratedInvoiceContract: Codable, Equatable, XMLRootNode, XMLFieldNamespaceProvider {
    static let xmlRootElementName = "invoice"
    static let xmlRootElementNamespaceURI: String? = "urn:billing"

    static var xmlFieldNamespaces: [String: XMLNamespace] {
        [
            "line": XMLNamespace(prefix: "bill", uri: "urn:billing"),
            "amount": XMLNamespace(prefix: "bill", uri: "urn:billing"),
            "issuedAt": XMLNamespace(prefix: "bill", uri: "urn:billing"),
            "attachment": XMLNamespace(prefix: "bin", uri: "urn:binary")
        ]
    }

    @XMLAttribute var id: String
    var line: [String]
    var amount: GeneratedAmountContract
    var issuedAt: Date
    var attachment: Data?

    init(id: String, line: [String], amount: GeneratedAmountContract, issuedAt: Date, attachment: Data?) {
        self.id = id
        self.line = line
        self.amount = amount
        self.issuedAt = issuedAt
        self.attachment = attachment
    }
}

final class GeneratedModelContractTests: XCTestCase {
    func test_generatedStyleModel_roundTripsRootNamespaceWrappersAndScalarStrategies() throws {
        let payload = GeneratedInvoiceContract(
            id: "INV-42",
            line: ["alpha", "beta"],
            amount: GeneratedAmountContract(currency: "eur", value: Decimal(string: "12.50")!),
            issuedAt: Date(timeIntervalSince1970: 0),
            attachment: Data([0x41, 0x42])
        )
        let encoder = XMLEncoder(configuration: .init(
            dateEncodingStrategy: .xsdDateTimeISO8601,
            dataEncodingStrategy: .base64
        ))
        let decoder = XMLDecoder(configuration: .init(
            dateDecodingStrategy: .xsdDateTimeISO8601,
            dataDecodingStrategy: .base64
        ))

        let tree = try encoder.encodeTree(payload)
        let xml = try XCTUnwrap(String(data: try encoder.encode(payload), encoding: .utf8))
        let amount = try XCTUnwrap(firstChild(named: "amount", in: tree.root))
        let issuedAt = try XCTUnwrap(firstChild(named: "issuedAt", in: tree.root))
        let attachment = try XCTUnwrap(firstChild(named: "attachment", in: tree.root))

        XCTAssertEqual(tree.root.name.localName, "invoice")
        XCTAssertEqual(tree.root.name.namespaceURI, "urn:billing")
        XCTAssertEqual(tree.root.attributes.first?.name.localName, "id")
        XCTAssertEqual(tree.root.attributes.first?.value, "INV-42")
        XCTAssertEqual(amount.attributes.first?.name.localName, "currency")
        XCTAssertEqual(amount.attributes.first?.value, "eur")
        XCTAssertEqual(textContent(of: amount), "12.5")
        XCTAssertEqual(issuedAt.name.namespaceURI, "urn:billing")
        XCTAssertEqual(issuedAt.name.prefix, "bill")
        XCTAssertEqual(attachment.name.namespaceURI, "urn:binary")
        XCTAssertEqual(attachment.name.prefix, "bin")
        XCTAssertTrue(xml.contains("xmlns:bill=\"urn:billing\""))
        XCTAssertTrue(xml.contains("xmlns:bin=\"urn:binary\""))

        let decoded = try decoder.decode(GeneratedInvoiceContract.self, from: Data(xml.utf8))
        XCTAssertEqual(decoded, payload)
    }

    func test_generatedStyleModel_preservesOptionalBinaryAndArrayPayloads() throws {
        let payload = GeneratedInvoiceContract(
            id: "INV-99",
            line: ["single"],
            amount: GeneratedAmountContract(currency: "usd", value: Decimal(string: "8.00")!),
            issuedAt: Date(timeIntervalSince1970: 86_400),
            attachment: nil
        )
        let encoder = XMLEncoder(configuration: .init(dateEncodingStrategy: .xsdDateTimeISO8601))
        let decoder = XMLDecoder(configuration: .init(dateDecodingStrategy: .xsdDateTimeISO8601))

        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(GeneratedInvoiceContract.self, from: data)

        XCTAssertEqual(decoded, payload)
    }
}

private func firstChild(named name: String, in element: XMLTreeElement) -> XMLTreeElement? {
    element.children.first { child in
        guard case let .element(candidate) = child else {
            return false
        }
        return candidate.name.localName == name
    }
    .flatMap { child in
        guard case let .element(candidate) = child else {
            return nil
        }
        return candidate
    }
}

private func textContent(of element: XMLTreeElement) -> String? {
    element.children.compactMap { child in
        guard case let .text(value) = child else {
            return nil
        }
        return value
    }
    .joined()
}
