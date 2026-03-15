import Foundation

/// Decodes XML trees or raw XML data into `Decodable` Swift types.
///
/// `XMLDecoder` is the primary entry point for deserialising XML into Swift model types.
/// It uses the `Codable` machinery internally and supports configurable strategies
/// for dates and binary data.
///
/// ```swift
/// let decoder = XMLDecoder()
/// let value = try decoder.decode(MyType.self, from: xmlData)
/// ```
///
/// The decoder is `Sendable` and can be shared across concurrent contexts without
/// additional synchronisation.
public struct XMLDecoder: Sendable {
    /// Controls how XML text content is decoded into `Date` values.
    public enum DateDecodingStrategy: Sendable {
        /// Delegate to `Date`'s default `Decodable` behaviour (expects a Double).
        case deferredToDate
        /// Decode a floating-point string as seconds since Unix epoch.
        case secondsSince1970
        /// Decode a floating-point string as milliseconds since Unix epoch.
        case millisecondsSince1970
        /// Decode XSD `dateTime` format (`YYYY-MM-DDThh:mm:ssZ`). Part of the default chain.
        case xsdDateTimeISO8601
        /// Decode ISO 8601 format using `ISO8601DateFormatter`.
        case iso8601
        /// Decode an XSD `xs:date` value (`YYYY-MM-DD[Z/±HH:MM]`) into a `Foundation.Date`.
        ///
        /// The resulting `Date` represents midnight at the start of the day in the timezone
        /// encoded in the lexical value, or UTC if absent.
        case xsdDate
        /// Decode an XSD `xs:time` value (`hh:mm:ss[.SSS][Z/±HH:MM]`) into a `Foundation.Date`.
        ///
        /// The date component is set to 2000-01-01 (XSD epoch reference). Only the time is meaningful.
        case xsdTime
        /// Decode an XSD `xs:gYear` value (`YYYY[Z/±HH:MM]`) into a `Foundation.Date`.
        ///
        /// Returns the first instant of the year in the encoded timezone (or UTC if absent).
        case xsdGYear
        /// Decode an XSD `xs:gYearMonth` value (`YYYY-MM[Z/±HH:MM]`) into a `Foundation.Date`.
        ///
        /// Returns the first instant of the month in the encoded timezone (or UTC if absent).
        case xsdGYearMonth
        /// Decode an XSD `xs:gMonth` value (`--MM[Z/±HH:MM]`).
        ///
        /// Returns a `Date` on year 2000 for the encoded month, day 1, time midnight UTC.
        case xsdGMonth
        /// Decode an XSD `xs:gDay` value (`---DD[Z/±HH:MM]`).
        ///
        /// Returns a `Date` on 2000-01-DD, time midnight UTC.
        case xsdGDay
        /// Decode an XSD `xs:gMonthDay` value (`--MM-DD[Z/±HH:MM]`).
        ///
        /// Returns a `Date` on 2000-MM-DD, time midnight UTC.
        case xsdGMonthDay
        /// Decode using a custom `XMLDateFormatterDescriptor`.
        case formatter(XMLDateFormatterDescriptor)
        /// Try each strategy in turn; throw if all fail. Part of the default chain.
        case multiple([DateDecodingStrategy])
        /// Decode using a custom closure.
        case custom(XMLDateDecodingClosure)
    }

    /// Controls how XML text content is decoded into `Data` values.
    public enum DataDecodingStrategy: Sendable, Hashable {
        /// Delegate to `Data`'s default `Decodable` behaviour.
        case deferredToData
        /// Decode Base-64 encoded text.  This is the default.
        case base64
        /// Decode lowercase hexadecimal text.
        case hex
    }

    /// Decoding configuration applied to every decode call on this instance.
    public struct Configuration: Sendable {
        /// Override the expected root element name.
        /// When `nil`, the decoder derives the name from `@XMLRootNode` or skips validation.
        public let rootElementName: String?
        /// Element name expected for items in collection types.  Defaults to `"item"`.
        public let itemElementName: String
        /// Field-level coding overrides (e.g. attribute vs element, custom element names).
        public let fieldCodingOverrides: XMLFieldCodingOverrides
        /// Strategy for decoding `Date` values.  Defaults to a chain of XSD, seconds, milliseconds.
        public let dateDecodingStrategy: DateDecodingStrategy
        /// Strategy for decoding `Data` values.  Defaults to `.base64`.
        public let dataDecodingStrategy: DataDecodingStrategy
        /// Configuration forwarded to the underlying `XMLTreeParser`.
        public let parserConfiguration: XMLTreeParser.Configuration
        /// Validation policy applied during decoding.
        ///
        /// Controls whether XSD temporal values and other structural values are
        /// validated strictly. Defaults to ``XMLValidationPolicy/default``, which
        /// respects the `SWIFT_XML_CODER_STRICT_VALIDATION` compile-time flag.
        public let validationPolicy: XMLValidationPolicy

        /// Creates a decoder configuration.
        ///
        /// - Parameters:
        ///   - rootElementName: Expected root element name override. `nil` resolves from `@XMLRootNode` or skips validation.
        ///   - itemElementName: Expected element name for collection items. Defaults to `"item"`.
        ///   - fieldCodingOverrides: Per-field node-kind overrides. Defaults to empty (all elements).
        ///   - dateDecodingStrategy: How text content is decoded into `Date`. Defaults to a multi-format chain.
        ///   - dataDecodingStrategy: How text content is decoded into `Data`. Defaults to `.base64`.
        ///   - parserConfiguration: Parser options forwarded to `XMLTreeParser`.
        ///   - validationPolicy: Structural validation policy. Defaults to ``XMLValidationPolicy/default``.
        public init(
            rootElementName: String? = nil,
            itemElementName: String = "item",
            fieldCodingOverrides: XMLFieldCodingOverrides = XMLFieldCodingOverrides(),
            dateDecodingStrategy: DateDecodingStrategy = .multiple(
                [.xsdDateTimeISO8601, .secondsSince1970, .millisecondsSince1970]
            ),
            dataDecodingStrategy: DataDecodingStrategy = .base64,
            parserConfiguration: XMLTreeParser.Configuration = XMLTreeParser.Configuration(),
            validationPolicy: XMLValidationPolicy = .default
        ) {
            self.rootElementName = rootElementName
            self.itemElementName = itemElementName
            self.fieldCodingOverrides = fieldCodingOverrides
            self.dateDecodingStrategy = dateDecodingStrategy
            self.dataDecodingStrategy = dataDecodingStrategy
            self.parserConfiguration = parserConfiguration
            self.validationPolicy = validationPolicy
        }
    }

    /// The configuration used by this decoder.
    public let configuration: Configuration

    /// Creates a new decoder with the supplied configuration.
    /// - Parameter configuration: Decoding options.  Defaults to `Configuration()`.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    #if swift(>=6.0)
    /// Decodes `type` from a pre-parsed `XMLTreeDocument`.
    ///
    /// Use this when the XML tree is already available (e.g. from the SOAP wire codec).
    /// - Parameters:
    ///   - type: The `Decodable` type to decode into.
    ///   - tree: The source document tree.
    /// - Returns: A decoded instance of `type`.
    /// - Throws: `XMLParsingError` on decoding failure or root element mismatch.
    public func decodeTree<T: Decodable>(_ type: T.Type, from tree: XMLTreeDocument) throws(XMLParsingError) -> T {
        do {
            return try decodeTreeImpl(type, from: tree)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML decode tree error.")
        }
    }

    /// Decodes `type` from raw XML `Data`.
    ///
    /// Parses the data into an `XMLTreeDocument` using `parserConfiguration` and then decodes.
    /// - Parameters:
    ///   - type: The `Decodable` type to decode into.
    ///   - data: Raw UTF-8 encoded XML data.
    /// - Returns: A decoded instance of `type`.
    /// - Throws: `XMLParsingError` on parse or decode failure.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(XMLParsingError) -> T {
        do {
            let parser = XMLTreeParser(configuration: configuration.parserConfiguration)
            let tree = try parser.parse(data: data)
            return try decodeTreeImpl(type, from: tree)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML decode error.")
        }
    }
    #else
    /// Decodes `type` from a pre-parsed `XMLTreeDocument`.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode into.
    ///   - tree: The source document tree.
    /// - Returns: A decoded instance of `type`.
    /// - Throws: `XMLParsingError` on decoding failure or root element mismatch.
    public func decodeTree<T: Decodable>(_ type: T.Type, from tree: XMLTreeDocument) throws -> T {
        try decodeTreeImpl(type, from: tree)
    }

    /// Decodes `type` from raw XML `Data`.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode into.
    ///   - data: Raw UTF-8 encoded XML data.
    /// - Returns: A decoded instance of `type`.
    /// - Throws: `XMLParsingError` on parse or decode failure.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let parser = XMLTreeParser(configuration: configuration.parserConfiguration)
        let tree = try parser.parse(data: data)
        return try decodeTreeImpl(type, from: tree)
    }
    #endif

    private func decodeTreeImpl<T: Decodable>(_ type: T.Type, from tree: XMLTreeDocument) throws -> T {
        if let expectedRootName = try resolveExpectedRootElementName(for: type),
           tree.root.name.localName != expectedRootName {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_ROOT_MISMATCH] Expected root '\(expectedRootName)' but found '\(tree.root.name.localName)'."
            )
        }

        let options = _XMLDecoderOptions(configuration: configuration)
        let decoder = _XMLTreeDecoder(
            options: options,
            codingPath: [],
            node: tree.root,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self)
        )
        // Intercept Foundation scalar types (Decimal, URL, UUID, Date, Data, …) whose
        // Codable conformances call container(keyedBy:) or decode(String.self) internally,
        // bypassing our scalar path. This mirrors the JSONDecoder approach of special-casing
        // Foundation types via a direct unbox call instead of relying on T.init(from:).
        if let scalar: T = try decoder.decodeScalar(type, from: tree.root, codingPath: []) {
            return scalar
        }
        if decoder.isKnownScalarType(type) {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar at root element '\(tree.root.name.localName)'."
            )
        }
        return try T(from: decoder)
    }

    private func resolveExpectedRootElementName<T>(for type: T.Type) throws -> String? {
        let policy = configuration.validationPolicy
        if let explicitName = try XMLRootNameResolver.explicitRootElementName(
            from: configuration.rootElementName,
            validationPolicy: policy
        ) {
            return explicitName
        }

        return try XMLRootNameResolver.implicitRootElementName(for: type, validationPolicy: policy)
    }
}
