import Foundation
import SwiftXMLCoder
import XCTest

// MARK: - Test fixtures

private struct Person: Codable, Equatable {
    var name: String
    var age: Int
}

private struct Wrapper: Codable, Equatable {
    var person: Person
}

private struct ScalarRoot: Codable, Equatable {
    var value: Int
}

private struct WithDate: Codable, Equatable {
    var date: Date
}

// MARK: - Tests

final class XMLDiagnosticsTests: XCTestCase {

    // MARK: XMLSourceLocation

    func test_sourceLocation_initDefaults() {
        let loc = XMLSourceLocation()
        XCTAssertNil(loc.line)
        XCTAssertNil(loc.column)
        XCTAssertNil(loc.byteOffset)
    }

    func test_sourceLocation_initWithLine() {
        let loc = XMLSourceLocation(line: 42)
        XCTAssertEqual(loc.line, 42)
        XCTAssertNil(loc.column)
        XCTAssertNil(loc.byteOffset)
    }

    func test_sourceLocation_equatable() {
        let a = XMLSourceLocation(line: 5)
        let b = XMLSourceLocation(line: 5)
        let c = XMLSourceLocation(line: 6)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: XMLParsingError.decodeFailed — shape

    func test_decodeFailed_equatable_matchingValues() {
        let a = XMLParsingError.decodeFailed(
            codingPath: ["root", "name"],
            location: XMLSourceLocation(line: 3),
            message: "[XML6_5_KEY_NOT_FOUND] Missing key 'name'."
        )
        let b = XMLParsingError.decodeFailed(
            codingPath: ["root", "name"],
            location: XMLSourceLocation(line: 3),
            message: "[XML6_5_KEY_NOT_FOUND] Missing key 'name'."
        )
        XCTAssertEqual(a, b)
    }

    func test_decodeFailed_equatable_differentPath() {
        let a = XMLParsingError.decodeFailed(codingPath: ["root", "name"], location: nil, message: "msg")
        let b = XMLParsingError.decodeFailed(codingPath: ["root", "age"], location: nil, message: "msg")
        XCTAssertNotEqual(a, b)
    }

    func test_decodeFailed_equatable_differentLocation() {
        let a = XMLParsingError.decodeFailed(codingPath: ["root"], location: XMLSourceLocation(line: 1), message: "msg")
        let b = XMLParsingError.decodeFailed(codingPath: ["root"], location: XMLSourceLocation(line: 2), message: "msg")
        XCTAssertNotEqual(a, b)
    }

    func test_decodeFailed_notEqualToParseFailed() {
        let decode = XMLParsingError.decodeFailed(codingPath: [], location: nil, message: "msg")
        let parse = XMLParsingError.parseFailed(message: "msg")
        XCTAssertNotEqual(decode, parse)
    }

    // MARK: decodeFailed thrown by XMLDecoder — missing key

    func test_missingKey_throwsDecodeFailed_withCodingPath() throws {
        let xml = Data("<Root><name>Alice</name></Root>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Person.self, from: xml)) { error in
            guard let xmlError = error as? XMLParsingError,
                  case .decodeFailed(let path, _, let message) = xmlError else {
                XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
                return
            }
            XCTAssertTrue(path.contains("age"), "Expected 'age' in coding path \(path)")
            XCTAssertTrue(message?.contains("age") == true, "Expected 'age' in message '\(message ?? "")'")
        }
    }

    func test_missingKey_throwsDecodeFailed_notParseFailed() throws {
        let xml = Data("<Root><name>Alice</name></Root>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Person.self, from: xml)) { error in
            guard let xmlError = error as? XMLParsingError else {
                XCTFail("Expected XMLParsingError, got \(type(of: error))")
                return
            }
            if case .parseFailed = xmlError {
                XCTFail("Should not throw parseFailed for Codable decode errors; got \(xmlError)")
            }
            // decodeFailed or any other case is acceptable (test above asserts decodeFailed)
        }
    }

    // MARK: decodeFailed — bad scalar

    func test_badInt_throwsDecodeFailed_withCode() throws {
        let xml = Data("<Root><name>Alice</name><age>notanumber</age></Root>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Person.self, from: xml)) { error in
            guard let xmlError = error as? XMLParsingError,
                  case .decodeFailed(let path, _, let message) = xmlError else {
                XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
                return
            }
            XCTAssertFalse(path.isEmpty, "Coding path should not be empty")
            XCTAssertTrue(message?.contains("XML6_5C_INTEGER_PARSE_FAILED") == true,
                          "Expected integer parse error code in '\(message ?? "")'")
        }
    }

    // MARK: decodeFailed — source location carried when XML has line info

    func test_missingKey_locationIsNilOrHasLine() throws {
        // Source line is populated from libxml2 when parsing real XML.
        // We verify the location field is either nil or a valid positive line.
        let xml = Data("""
        <Root>
            <name>Alice</name>
        </Root>
        """.utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Person.self, from: xml)) { error in
            guard let xmlError = error as? XMLParsingError,
                  case .decodeFailed(_, let location, _) = xmlError else {
                XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
                return
            }
            if let loc = location {
                XCTAssertTrue((loc.line ?? 0) > 0, "Line should be positive, got \(String(describing: loc.line))")
                XCTAssertNil(loc.column, "Column is not available in DOM mode")
                XCTAssertNil(loc.byteOffset, "ByteOffset is not available in DOM mode")
            }
            // nil location is also acceptable for programmatically-created elements
        }
    }

    // MARK: decodeFailed — nested coding path

    func test_nestedMissingKey_codingPathReflectsNesting() throws {
        let xml = Data("<Root><person><name>Alice</name></person></Root>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Wrapper.self, from: xml)) { error in
            guard let xmlError = error as? XMLParsingError,
                  case .decodeFailed(let path, _, _) = xmlError else {
                XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
                return
            }
            XCTAssertFalse(path.isEmpty, "Nested coding path should not be empty")
        }
    }

    // MARK: decodeFailed — bad date

    func test_badDate_throwsDecodeFailed_withDateCode() throws {
        let xml = Data("<Root><date>not-a-date</date></Root>".utf8)
        let decoder = XMLDecoder(
            configuration: .init(
                rootElementName: "Root",
                dateDecodingStrategy: .xsdDate
            )
        )
        XCTAssertThrowsError(try decoder.decode(WithDate.self, from: xml)) { error in
            guard let xmlError = error as? XMLParsingError,
                  case .decodeFailed(_, _, let message) = xmlError else {
                XCTFail("Expected XMLParsingError.decodeFailed, got \(error)")
                return
            }
            XCTAssertTrue(message?.contains("XML6_5C_DATE_PARSE_FAILED") == true,
                          "Expected date parse error code in '\(message ?? "")'")
        }
    }

    // MARK: parseFailed still used for XML-level failures

    func test_invalidXML_throwsParseFailedNotDecodeFailed() throws {
        let xml = Data("<unclosed".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        XCTAssertThrowsError(try decoder.decode(Person.self, from: xml)) { error in
            guard let xmlError = error as? XMLParsingError else {
                XCTFail("Expected XMLParsingError, got \(type(of: error))")
                return
            }
            // XML-level failures (libxml2 parse errors) must NOT use decodeFailed.
            if case .decodeFailed = xmlError {
                XCTFail("XML parse errors must use parseFailed or invalidUTF8, not decodeFailed; got \(xmlError)")
            }
            // parseFailed or other non-Codable case is expected
        }
    }

    // MARK: Regression — successful decode produces no error

    func test_validXML_decodesWithoutError() throws {
        let xml = Data("<Root><name>Alice</name><age>30</age></Root>".utf8)
        let decoder = XMLDecoder(configuration: .init(rootElementName: "Root"))
        let result = try decoder.decode(Person.self, from: xml)
        XCTAssertEqual(result, Person(name: "Alice", age: 30))
    }
}
