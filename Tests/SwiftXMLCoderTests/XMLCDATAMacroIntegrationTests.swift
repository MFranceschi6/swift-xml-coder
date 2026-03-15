import Foundation
import XCTest

@testable import SwiftXMLCoder

// MARK: - Test fixtures

// NOTE: The @XMLCodable + @XMLCDATA macros are only available when building with
// Swift 5.9+ toolchains. Integration tests here exercise the runtime path directly by
// manually conforming to XMLStringCodingOverrideProvider, which mirrors what @XMLCodable
// synthesises, but is available on all supported Swift versions.

// Simulates what @XMLCodable + @XMLCDATA generates on Article.body.
private struct Article: Codable, Equatable {
    var title: String  // uses global stringEncodingStrategy (default: .text)
    var body: String   // per-property CDATA override
}

extension Article: XMLFieldCodingOverrideProvider {
    static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] { [:] }
}

extension Article: XMLStringCodingOverrideProvider {
    static var xmlPropertyStringHints: [String: XMLStringEncodingHint] {
        ["body": .cdata]
    }
}

// A type with no string overrides — global strategy must still apply.
private struct PlainContent: Codable, Equatable {
    var title: String
    var description: String
}

extension PlainContent: XMLFieldCodingOverrideProvider {
    static var xmlFieldNodeKinds: [String: XMLFieldNodeKind] { [:] }
}

// MARK: - Tests

final class XMLCDATAMacroIntegrationTests: XCTestCase {

    // MARK: - Per-property CDATA override

    func test_perPropertyCDATA_emitsCDATAForAnnotatedField() throws {
        let encoder = XMLEncoder()  // global: .text
        let tree = try encoder.encodeTree(Article(title: "News", body: "<p>Hello</p>"))

        let bodyEl = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child, el.name.localName == "body" else { return nil }
            return el
        }.first
        XCTAssertNotNil(bodyEl)

        let cdataValue = bodyEl?.children.compactMap { child -> String? in
            if case .cdata(let v) = child { return v }
            return nil
        }.first
        XCTAssertEqual(cdataValue, "<p>Hello</p>", "body field should be CDATA")
    }

    func test_perPropertyCDATA_emitsPlainTextForUnannotatedField() throws {
        let encoder = XMLEncoder()  // global: .text
        let tree = try encoder.encodeTree(Article(title: "News", body: "<p>Hello</p>"))

        let titleEl = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child, el.name.localName == "title" else { return nil }
            return el
        }.first
        XCTAssertNotNil(titleEl)

        let hasText = titleEl?.children.contains { child in
            if case .text = child { return true }
            return false
        } ?? false
        let hasCDATA = titleEl?.children.contains { child in
            if case .cdata = child { return true }
            return false
        } ?? false
        XCTAssertTrue(hasText, "title should be plain text")
        XCTAssertFalse(hasCDATA, "title should not be CDATA")
    }

    func test_perPropertyCDATA_overridesGlobalCDATAStrategy_withTextHint() throws {
        // If global is .cdata but per-property would be .text, per-property wins.
        // Currently @XMLCDATA only emits .cdata hints; .text can only come from the global.
        // This test verifies the priority: per-property .cdata > global .text.
        let encoder = XMLEncoder(configuration: .init(stringEncodingStrategy: .text))
        let tree = try encoder.encodeTree(Article(title: "News", body: "<p>Hello</p>"))
        let bodyEl = tree.root.children.compactMap { child -> XMLTreeElement? in
            guard case .element(let el) = child, el.name.localName == "body" else { return nil }
            return el
        }.first
        let hasCDATA = bodyEl?.children.contains { child in
            if case .cdata = child { return true }
            return false
        } ?? false
        XCTAssertTrue(hasCDATA, "per-property .cdata should override global .text")
    }

    func test_perPropertyCDATA_roundtrip() throws {
        let original = Article(title: "Tech News", body: "<h1>Hello & World</h1>")
        let encoder = XMLEncoder()
        let decoder = XMLDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Article.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_perPropertyCDATA_serialisedXMLContainsCDATASyntax() throws {
        let encoder = XMLEncoder()
        let data = try encoder.encode(Article(title: "News", body: "<p>Content & more</p>"))
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("<![CDATA["), "body should be serialised as CDATA: \(xml)")
        XCTAssertTrue(xml.contains("<p>Content & more</p>"), "CDATA content unescaped: \(xml)")
        // title should be escaped, not CDATA
        XCTAssertTrue(xml.contains("<title>News</title>"), "title should be plain: \(xml)")
    }

    // MARK: - No override — global strategy applies

    func test_noStringOverride_usesGlobalTextStrategy() throws {
        let encoder = XMLEncoder()
        let tree = try encoder.encodeTree(PlainContent(title: "Hello", description: "World"))
        for child in tree.root.children {
            guard case .element(let el) = child else { continue }
            let hasCDATA = el.children.contains { child in
                if case .cdata = child { return true }
                return false
            }
            XCTAssertFalse(hasCDATA, "No CDATA expected with default strategy for \(el.name.localName)")
        }
    }
}
