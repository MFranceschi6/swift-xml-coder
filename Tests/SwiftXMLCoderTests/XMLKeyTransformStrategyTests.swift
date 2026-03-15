import Foundation
import SwiftXMLCoder
import XCTest

final class XMLKeyTransformStrategyTests: XCTestCase {

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T, strategy: XMLKeyTransformStrategy) throws -> XMLTreeDocument {
        let encoder = XMLEncoder(configuration: .init(keyTransformStrategy: strategy))
        return try encoder.encodeTree(value)
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        xml: String,
        strategy: XMLKeyTransformStrategy
    ) throws -> T {
        let decoder = XMLDecoder(configuration: .init(keyTransformStrategy: strategy))
        return try decoder.decode(type, from: Data(xml.utf8))
    }

    private func childName(at index: Int, in tree: XMLTreeDocument) -> String? {
        let elements = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child else { return nil }
            return el
        }
        guard index < elements.count else { return nil }
        return elements[index].name.localName
    }

    // MARK: - useDefaultKeys (identity)

    func test_useDefaultKeys_preservesSwiftPropertyNames() throws {
        struct Payload: Encodable { let firstName: String; let lastName: String }
        let tree = try encode(Payload(firstName: "Mario", lastName: "Rossi"), strategy: .useDefaultKeys)
        XCTAssertEqual(childName(at: 0, in: tree), "firstName")
        XCTAssertEqual(childName(at: 1, in: tree), "lastName")
    }

    // MARK: - convertToSnakeCase

    func test_convertToSnakeCase_encodesCorrectXMLNames() throws {
        struct Person: Encodable { let firstName: String; let lastName: String }
        let tree = try encode(Person(firstName: "Mario", lastName: "Rossi"), strategy: .convertToSnakeCase)
        XCTAssertEqual(childName(at: 0, in: tree), "first_name")
        XCTAssertEqual(childName(at: 1, in: tree), "last_name")
    }

    func test_convertToSnakeCase_decodesCorrectly() throws {
        struct Person: Decodable { let firstName: String; let lastName: String }
        let xml = "<Person><first_name>Mario</first_name><last_name>Rossi</last_name></Person>"
        let person = try decode(Person.self, xml: xml, strategy: .convertToSnakeCase)
        XCTAssertEqual(person.firstName, "Mario")
        XCTAssertEqual(person.lastName, "Rossi")
    }

    func test_convertToSnakeCase_roundtrip() throws {
        struct Person: Codable, Equatable { let firstName: String; let city: String }
        let original = Person(firstName: "Mario", city: "Milano")
        let encoder = XMLEncoder(configuration: .init(keyTransformStrategy: .convertToSnakeCase))
        let decoder = XMLDecoder(configuration: .init(keyTransformStrategy: .convertToSnakeCase))
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Person.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - convertToKebabCase

    func test_convertToKebabCase_encodesCorrectXMLNames() throws {
        struct Order: Encodable { let orderId: Int; let itemCount: Int }
        let tree = try encode(Order(orderId: 42, itemCount: 3), strategy: .convertToKebabCase)
        XCTAssertEqual(childName(at: 0, in: tree), "order-id")
        XCTAssertEqual(childName(at: 1, in: tree), "item-count")
    }

    func test_convertToKebabCase_roundtrip() throws {
        struct Order: Codable, Equatable { let orderId: Int; let itemCount: Int }
        let original = Order(orderId: 42, itemCount: 3)
        let encoder = XMLEncoder(configuration: .init(keyTransformStrategy: .convertToKebabCase))
        let decoder = XMLDecoder(configuration: .init(keyTransformStrategy: .convertToKebabCase))
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Order.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - capitalized (SOAP / PascalCase)

    func test_capitalized_encodesFirstLetterUppercased() throws {
        struct Envelope: Encodable { let body: String; let header: String }
        let tree = try encode(Envelope(body: "content", header: "token"), strategy: .capitalized)
        XCTAssertEqual(childName(at: 0, in: tree), "Body")
        XCTAssertEqual(childName(at: 1, in: tree), "Header")
    }

    func test_capitalized_roundtrip() throws {
        struct Envelope: Codable, Equatable { let body: String; let header: String }
        let original = Envelope(body: "content", header: "token")
        let encoder = XMLEncoder(configuration: .init(keyTransformStrategy: .capitalized))
        let decoder = XMLDecoder(configuration: .init(keyTransformStrategy: .capitalized))
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Envelope.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - uppercased

    func test_uppercased_encodes_uppercaseXMLNames() throws {
        struct Item: Encodable { let id: Int; let name: String }
        let tree = try encode(Item(id: 1, name: "test"), strategy: .uppercased)
        XCTAssertEqual(childName(at: 0, in: tree), "ID")
        XCTAssertEqual(childName(at: 1, in: tree), "NAME")
    }

    // MARK: - lowercased

    func test_lowercased_encodesLowercaseXMLNames() throws {
        // swiftlint:disable:next identifier_name
        struct Item: Encodable { let ID: String; let fullName: String }
        let tree = try encode(Item(ID: "x", fullName: "y"), strategy: .lowercased)
        XCTAssertEqual(childName(at: 0, in: tree), "id")
        XCTAssertEqual(childName(at: 1, in: tree), "fullname")
    }

    // MARK: - custom

    func test_custom_appliesUserDefinedTransform() throws {
        struct Payload: Codable, Equatable { let value: String }
        let strategy: XMLKeyTransformStrategy = .custom { "x_" + $0 }
        let encoder = XMLEncoder(configuration: .init(keyTransformStrategy: strategy))
        let decoder = XMLDecoder(configuration: .init(keyTransformStrategy: strategy))
        let original = Payload(value: "hello")
        let data = try encoder.encode(original)
        // verify the XML element name was transformed
        let tree = try XMLTreeParser().parse(data: data)
        let element = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child else { return nil }
            return el
        }.first
        XCTAssertEqual(element?.name.localName, "x_value")
        let decoded = try decoder.decode(Payload.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - useDefaultKeys is the default

    func test_defaultConfiguration_usesIdentityTransform() throws {
        // Default strategy must not transform property names.
        struct Payload: Codable, Equatable { let firstName: String }
        let original = Payload(firstName: "Mario")
        let data = try XMLEncoder().encode(original)
        let tree = try XMLTreeParser().parse(data: data)
        let child = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child else { return nil }
            return el
        }.first
        XCTAssertEqual(child?.name.localName, "firstName", "Default strategy must preserve camelCase names")
    }
}
