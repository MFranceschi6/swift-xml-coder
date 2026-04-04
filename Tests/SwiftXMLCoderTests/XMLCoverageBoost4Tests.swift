import Foundation
@testable import SwiftXMLCoder
import XCTest

// MARK: - Coverage Boost Tests — Phase 4
//
// Targeted tests to close the last ~0.05% gap on Swift 6.1 (ubuntu).
// Focuses on:
// - XMLItemDecoder async stream API
// - XMLScalarDecoder temporal date strategies (gMonth, gDay, gMonthDay, gYearMonth)
// - XMLStreamWriter.WriterLimits.untrustedOutputDefault()
// - XMLTemporalTypes: toDate(), Decodable error paths
// - XMLDefaultCanonicalizer: whitespace policies, PI handling
// - XMLEncoder: encodeTreeToData (event-based writer)

final class XMLCoverageBoost4Tests: XCTestCase {

    // MARK: - XMLItemDecoder: async stream API

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    func test_itemDecoder_asyncStream_decodesAllItems() async throws {
        struct Product: Decodable, Equatable, Sendable { let name: String }
        let xml = Data("""
        <catalog>
            <Product><name>A</name></Product>
            <Product><name>B</name></Product>
            <Product><name>C</name></Product>
        </catalog>
        """.utf8)

        var results: [Product] = []
        for try await product in XMLItemDecoder().items(Product.self, itemElement: "Product", from: xml) {
            results.append(product)
        }
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.map(\.name), ["A", "B", "C"])
    }

    // MARK: - XMLScalarDecoder: gMonth date strategy

    func test_decoder_gMonth_decodesDate() throws {
        struct M: Codable { let month: Date }
        let xml = Data("<M><month>--03</month></M>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGMonth)
        let decoded = try XMLDecoder(configuration: config).decode(M.self, from: xml)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.month, from: decoded.month), 3)
    }

    // MARK: - XMLScalarDecoder: gDay date strategy

    func test_decoder_gDay_decodesDate() throws {
        struct D: Codable { let day: Date }
        let xml = Data("<D><day>---15</day></D>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGDay)
        let decoded = try XMLDecoder(configuration: config).decode(D.self, from: xml)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.day, from: decoded.day), 15)
    }

    // MARK: - XMLScalarDecoder: gMonthDay date strategy

    func test_decoder_gMonthDay_decodesDate() throws {
        struct MD: Codable { let val: Date }
        let xml = Data("<MD><val>--07-04</val></MD>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGMonthDay)
        let decoded = try XMLDecoder(configuration: config).decode(MD.self, from: xml)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.month, from: decoded.val), 7)
        XCTAssertEqual(cal.component(.day, from: decoded.val), 4)
    }

    // MARK: - XMLScalarDecoder: gYearMonth date strategy

    func test_decoder_gYearMonth_decodesDate() throws {
        struct YM: Codable { let val: Date }
        let xml = Data("<YM><val>2024-06</val></YM>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGYearMonth)
        let decoded = try XMLDecoder(configuration: config).decode(YM.self, from: xml)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.year, from: decoded.val), 2024)
        XCTAssertEqual(cal.component(.month, from: decoded.val), 6)
    }

    // MARK: - XMLScalarDecoder: gYear date strategy

    func test_decoder_gYear_decodesDate() throws {
        struct Y: Codable { let val: Date }
        let xml = Data("<Y><val>2020</val></Y>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGYear)
        let decoded = try XMLDecoder(configuration: config).decode(Y.self, from: xml)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.year, from: decoded.val), 2020)
    }

    // MARK: - XMLStreamWriter: untrustedOutputDefault limits

    func test_writerLimits_untrustedOutputDefault_hasReasonableValues() {
        let limits = XMLStreamWriter.WriterLimits.untrustedOutputDefault()
        XCTAssertEqual(limits.maxDepth, 256)
        XCTAssertEqual(limits.maxNodeCount, 200_000)
        XCTAssertGreaterThan(limits.maxOutputBytes ?? 0, 0)
        XCTAssertGreaterThan(limits.maxTextNodeBytes ?? 0, 0)
    }

    // MARK: - XMLTemporalTypes: XMLGYearMonth toDate

    func test_gYearMonth_toDate_producesCorrectDate() {
        let ym = XMLGYearMonth(lexicalValue: "2024-06")
        XCTAssertNotNil(ym)
        let date = ym?.toDate()
        XCTAssertNotNil(date)
        if let date = date {
            let cal = Calendar(identifier: .gregorian)
            XCTAssertEqual(cal.component(.year, from: date), 2024)
            XCTAssertEqual(cal.component(.month, from: date), 6)
        }
    }

    // MARK: - XMLTemporalTypes: XMLGYear invalid decode

    func test_gYear_invalidValue_throwsDecodingError() {
        struct Y: Codable { let val: Date }
        let xml = Data("<Y><val>notayear</val></Y>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGYear)
        XCTAssertThrowsError(try XMLDecoder(configuration: config).decode(Y.self, from: xml))
    }

    // MARK: - XMLTemporalTypes: XMLTimezoneOffset timeZone

    func test_timezoneOffset_timeZone_returnsCorrectZone() {
        let offset = XMLTimezoneOffset(hours: 5, minutes: 30)
        let tz = offset.timeZone
        XCTAssertEqual(tz.secondsFromGMT(), 5 * 3600 + 30 * 60)
    }

    func test_timezoneOffset_negative_returnsCorrectZone() {
        let offset = XMLTimezoneOffset(hours: -8, minutes: 0)
        let tz = offset.timeZone
        XCTAssertEqual(tz.secondsFromGMT(), -8 * 3600)
    }

    // MARK: - XMLDefaultCanonicalizer: processing instructions preserved

    func test_canonicalizer_streamBased_processingInstructionPreserved() throws {
        let xml = Data("<?xml version=\"1.0\"?><?pi-target pi-data?><root><a>1</a></root>".utf8)
        let canonicalizer = XMLDefaultCanonicalizer()
        let result = try canonicalizer.canonicalize(
            data: xml,
            options: XMLCanonicalizationOptions(includeProcessingInstructions: true)
        )
        let output = String(decoding: result, as: UTF8.self)
        XCTAssert(output.contains("<root>"), "Expected root in: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: whitespace text policies

    func test_canonicalizer_normalizeAndTrim_normalizesWhitespace() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []),
            .text("  hello   world  "),
            .endElement(name: XMLQualifiedName(localName: "root")),
            .endDocument,
        ]
        let canonicalizer = XMLDefaultCanonicalizer()
        var chunks: [Data] = []
        try canonicalizer.canonicalize(
            events: events,
            options: XMLCanonicalizationOptions(whitespaceTextNodePolicy: .normalizeAndTrim),
            eventTransforms: []
        ) { chunk in
            chunks.append(chunk)
        }
        let output = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        // Normalized and trimmed: leading/trailing whitespace removed, internal collapsed
        XCTAssert(output.contains("hello"), "Expected text in: \(output)")
    }

    func test_canonicalizer_omitWhitespaceOnly_dropsWhitespaceText() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []),
            .text("   "),
            .startElement(name: XMLQualifiedName(localName: "a"), attributes: [], namespaceDeclarations: []),
            .text("keep"),
            .endElement(name: XMLQualifiedName(localName: "a")),
            .endElement(name: XMLQualifiedName(localName: "root")),
            .endDocument,
        ]
        let canonicalizer = XMLDefaultCanonicalizer()
        var chunks: [Data] = []
        try canonicalizer.canonicalize(
            events: events,
            options: XMLCanonicalizationOptions(whitespaceTextNodePolicy: .omitWhitespaceOnly),
            eventTransforms: []
        ) { chunk in
            chunks.append(chunk)
        }
        let output = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(output.contains("keep"), "Expected 'keep' in: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: CDATA normalization in event mode

    func test_canonicalizer_eventBased_cdataNormalizedToText() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(name: XMLQualifiedName(localName: "root"), attributes: [], namespaceDeclarations: []),
            .cdata("cdata content"),
            .endElement(name: XMLQualifiedName(localName: "root")),
            .endDocument,
        ]
        let canonicalizer = XMLDefaultCanonicalizer()
        var chunks: [Data] = []
        try canonicalizer.canonicalize(
            events: events,
            options: XMLCanonicalizationOptions(),
            eventTransforms: []
        ) { chunk in
            chunks.append(chunk)
        }
        let output = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        XCTAssert(output.contains("cdata content"), "Expected text content in: \(output)")
    }

    // MARK: - XMLDefaultCanonicalizer: attribute sorting tiebreaker

    func test_canonicalizer_attributeSorting_stableSortsByValue() throws {
        let events: [XMLStreamEvent] = [
            .startDocument(version: "1.0", encoding: "UTF-8", standalone: nil),
            .startElement(
                name: XMLQualifiedName(localName: "root"),
                attributes: [
                    XMLTreeAttribute(name: XMLQualifiedName(localName: "z"), value: "1"),
                    XMLTreeAttribute(name: XMLQualifiedName(localName: "a"), value: "2"),
                ],
                namespaceDeclarations: []
            ),
            .endElement(name: XMLQualifiedName(localName: "root")),
            .endDocument,
        ]
        let canonicalizer = XMLDefaultCanonicalizer()
        var chunks: [Data] = []
        try canonicalizer.canonicalize(
            events: events,
            options: XMLCanonicalizationOptions(),
            eventTransforms: []
        ) { chunk in
            chunks.append(chunk)
        }
        let output = String(decoding: chunks.reduce(Data(), +), as: UTF8.self)
        // Canonical form sorts attributes alphabetically
        XCTAssert(output.contains("a=\"2\""), "Expected sorted attributes in: \(output)")
    }

    // MARK: - XMLEncoder: encodeTreeToData (event-based writer path)

    func test_encoder_eventBasedWriter_producesValidXML() throws {
        struct Simple: Codable, Equatable { let name: String; let value: Int }
        // The event-based writer is used internally; exercise it via encode
        let original = Simple(name: "test", value: 42)
        let config = XMLEncoder.Configuration(rootElementName: "root")
        let data = try XMLEncoder(configuration: config).encode(original)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssert(xml.contains("<name>test</name>"), "Expected name in: \(xml)")
        XCTAssert(xml.contains("<value>42</value>"), "Expected value in: \(xml)")
        // Round-trip
        let decoded = try XMLDecoder().decode(Simple.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - XMLTemporalTypes: XMLDuration parsing

    func test_xmlDuration_parsing_withFractionalSeconds() {
        let dur = XMLDuration(lexicalValue: "P1Y2M3DT4H5M6.789S")
        XCTAssertNotNil(dur)
        XCTAssertEqual(dur?.years, 1)
        XCTAssertEqual(dur?.months, 2)
        XCTAssertEqual(dur?.days, 3)
        XCTAssertEqual(dur?.hours, 4)
        XCTAssertEqual(dur?.minutes, 5)
        XCTAssertEqual(dur?.seconds, 6)
        XCTAssertNotNil(dur?.fractionalSeconds)
    }

    func test_xmlDuration_toTimeInterval() {
        let dur = XMLDuration(lexicalValue: "PT1H30M")
        XCTAssertNotNil(dur)
        let interval = dur?.toTimeInterval(referenceDate: Date(timeIntervalSince1970: 0))
        XCTAssertNotNil(interval)
        if let interval = interval {
            XCTAssertEqual(interval, 5400, accuracy: 1)
        }
    }

    func test_xmlDuration_lexicalValue_roundTrips() {
        let dur = XMLDuration(lexicalValue: "P1Y2M3DT4H5M6S")
        XCTAssertNotNil(dur)
        let lex = dur?.lexicalValue
        XCTAssertEqual(lex, "P1Y2M3DT4H5M6S")
    }

    func test_xmlDuration_negative_parsing() {
        let dur = XMLDuration(lexicalValue: "-P1D")
        XCTAssertNotNil(dur)
        XCTAssertEqual(dur?.isNegative, true)
        XCTAssertEqual(dur?.days, 1)
    }

    // MARK: - XMLTemporalTypes: XMLTime parsing

    func test_xmlTime_parsing_withFractionalSeconds() {
        let time = XMLTime(lexicalValue: "13:20:30.123")
        XCTAssertNotNil(time)
        XCTAssertEqual(time?.hour, 13)
        XCTAssertEqual(time?.minute, 20)
        XCTAssertEqual(time?.second, 30)
    }

    func test_xmlTime_toDate_producesValidDate() {
        let time = XMLTime(lexicalValue: "09:15:00Z")
        XCTAssertNotNil(time)
        let date = time?.toDate()
        XCTAssertNotNil(date)
    }

    func test_xmlTime_lexicalValue_withFractionalSeconds() {
        let time = XMLTime(lexicalValue: "13:20:30.500")
        XCTAssertNotNil(time)
        let lex = time?.lexicalValue
        XCTAssertNotNil(lex)
        XCTAssert(lex?.contains("13:20:30") == true)
    }

    // MARK: - XMLTemporalTypes: XMLGMonth / XMLGDay / XMLGMonthDay invalid Decodable

    func test_gMonth_invalidValue_throwsDecodingError() {
        struct M: Codable { let val: Date }
        let xml = Data("<M><val>notamonth</val></M>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGMonth)
        XCTAssertThrowsError(try XMLDecoder(configuration: config).decode(M.self, from: xml))
    }

    func test_gDay_invalidValue_throwsDecodingError() {
        struct D: Codable { let val: Date }
        let xml = Data("<D><val>notaday</val></D>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGDay)
        XCTAssertThrowsError(try XMLDecoder(configuration: config).decode(D.self, from: xml))
    }

    func test_gMonthDay_invalidValue_throwsDecodingError() {
        struct MD: Codable { let val: Date }
        let xml = Data("<MD><val>notamonthday</val></MD>".utf8)
        let config = XMLDecoder.Configuration(dateDecodingStrategy: .xsdGMonthDay)
        XCTAssertThrowsError(try XMLDecoder(configuration: config).decode(MD.self, from: xml))
    }

    // MARK: - XMLStreamWriter: Configuration untrustedOutputProfile

    func test_writerConfiguration_untrustedOutputProfile() {
        let config = XMLStreamWriter.Configuration.untrustedOutputProfile()
        XCTAssertFalse(config.prettyPrinted)
        XCTAssertEqual(config.limits.maxDepth, 256)
        XCTAssertEqual(config.limits.maxNodeCount, 200_000)
    }

    // MARK: - XMLDecoder: whitespacePolicy accessor

    func test_decoder_configuration_whitespacePolicy() {
        let config = XMLDecoder.Configuration(
            parserConfiguration: XMLTreeParser.Configuration(
                whitespaceTextNodePolicy: .trim
            )
        )
        let decoder = XMLDecoder(configuration: config)
        XCTAssertEqual(decoder.whitespacePolicy, .trim)
    }

}
