import Foundation
import Logging

/// Encodes `Encodable` values into XML trees or raw XML data.
///
/// `XMLEncoder` is the primary entry point for serialising Swift model types to XML.
/// It uses the `Codable` machinery internally and supports configurable strategies
/// for nils, dates, binary data, and element ordering.
///
/// ```swift
/// let encoder = XMLEncoder()
/// let data = try encoder.encode(myValue)
/// ```
///
/// The encoder is `Sendable` and can be shared across concurrent contexts without
/// additional synchronisation.
public struct XMLEncoder: Sendable {
    /// Controls how optional (`nil`) values are represented in the XML output.
    ///
    /// Applies to all optional properties, including those with compiler-synthesised
    /// `Encodable` conformances. Both `encodeIfPresent` and explicit `encodeNil` calls
    /// respect this strategy.
    ///
    /// ```swift
    /// struct Example: Encodable { var name: String? }
    /// // name == nil with .omitElement → no <name> element in the output
    /// // name == nil with .emptyElement → <name/> in the output (default)
    /// ```
    ///
    /// `nil` values in `@XMLAttribute`-wrapped properties are always **omitted**
    /// regardless of this strategy (XML convention: absent attribute ≡ not set).
    public enum NilEncodingStrategy: Sendable, Hashable {
        /// Emit an empty element (`<field/>`). This is the default.
        case emptyElement
        /// Omit the element entirely from the output.
        case omitElement
    }

    /// Controls how `Date` values are serialised to XML text content.
    public enum DateEncodingStrategy: Sendable {
        /// Delegate to `Date`'s default `Encodable` behaviour (a Double).
        case deferredToDate
        /// Encode as seconds elapsed since Unix epoch (floating-point string).
        case secondsSince1970
        /// Encode as milliseconds elapsed since Unix epoch (floating-point string).
        case millisecondsSince1970
        /// Encode in XSD `dateTime` format (`YYYY-MM-DDThh:mm:ssZ`). This is the default.
        case xsdDateTimeISO8601
        /// Encode in ISO 8601 format as produced by `ISO8601DateFormatter`.
        case iso8601
        /// Encode a `Date` as XSD `xs:date` (`YYYY-MM-DD`), using UTC unless a timezone is specified.
        ///
        /// The time-of-day and sub-second components are discarded. To use a specific timezone,
        /// pass it via the `timeZone` parameter.
        ///
        /// - Parameter timeZone: The timezone used to extract year/month/day. Defaults to UTC.
        case xsdDate(timeZone: TimeZone = .utc)
        /// Encode a `Date` as XSD `xs:time` (`hh:mm:ss[.SSS]Z`).
        ///
        /// The date component is discarded. The result always carries a `Z` (UTC) or the provided
        /// timezone suffix.
        ///
        /// - Parameter timeZone: The timezone used to extract the time components. Defaults to UTC.
        case xsdTime(timeZone: TimeZone = .utc)
        /// Encode a `Date` as XSD `xs:gYear` (`YYYY`).
        ///
        /// - Parameter timeZone: The timezone used to extract the year. Defaults to UTC.
        case xsdGYear(timeZone: TimeZone = .utc)
        /// Encode a `Date` as XSD `xs:gYearMonth` (`YYYY-MM`).
        ///
        /// - Parameter timeZone: The timezone used to extract year and month. Defaults to UTC.
        case xsdGYearMonth(timeZone: TimeZone = .utc)
        /// Encode a `Date` as XSD `xs:gMonth` (`--MM`).
        ///
        /// - Parameter timeZone: The timezone used to extract the month. Defaults to UTC.
        case xsdGMonth(timeZone: TimeZone = .utc)
        /// Encode a `Date` as XSD `xs:gDay` (`---DD`).
        ///
        /// - Parameter timeZone: The timezone used to extract the day. Defaults to UTC.
        case xsdGDay(timeZone: TimeZone = .utc)
        /// Encode a `Date` as XSD `xs:gMonthDay` (`--MM-DD`).
        ///
        /// - Parameter timeZone: The timezone used to extract month and day. Defaults to UTC.
        case xsdGMonthDay(timeZone: TimeZone = .utc)
        /// Encode using a custom `XMLDateFormatterDescriptor`.
        case formatter(XMLDateFormatterDescriptor)
        /// Encode using a custom closure.
        case custom(XMLDateEncodingClosure)
    }

    /// Controls how `String` values are serialised as XML text content.
    ///
    /// Applies to all `String` properties when no per-field `@XMLCDATA` override is present.
    ///
    /// - Note: `@XMLAttribute`-wrapped `String` properties are always emitted as plain text —
    ///   CDATA is not valid in XML attributes. The strategy is silently ignored for attributes.
    public enum StringEncodingStrategy: Sendable, Hashable {
        /// Emit strings as plain XML text (special characters are escaped). This is the default.
        case text
        /// Wrap string values in a CDATA section (`<![CDATA[...]]>`).
        ///
        /// Use this when the content contains characters that are frequently escaped (e.g. HTML
        /// fragments, embedded XML, or SQL) and you prefer human-readable output.
        case cdata
    }

    /// Controls how `Data` values are serialised to XML text content.
    public enum DataEncodingStrategy: Sendable, Hashable {
        /// Delegate to `Data`'s default `Encodable` behaviour.
        case deferredToData
        /// Encode as Base-64 text. This is the default.
        case base64
        /// Encode as lowercase hexadecimal text.
        case hex
    }

    /// Encoding configuration applied to every encode call on this instance.
    public struct Configuration: @unchecked Sendable {
        /// Override the root element name.
        /// When `nil`, the encoder derives the name from `@XMLRootNode` or the type name.
        public let rootElementName: String?
        /// Element name used for items in collection types.  Defaults to `"item"`.
        public let itemElementName: String
        /// Field-level coding overrides (e.g. attribute vs element, custom element names).
        public let fieldCodingOverrides: XMLFieldCodingOverrides
        /// Strategy for encoding `nil` optionals.  Defaults to `.emptyElement`.
        public let nilEncodingStrategy: NilEncodingStrategy
        /// Strategy for encoding `Date` values.  Defaults to `.xsdDateTimeISO8601`.
        public let dateEncodingStrategy: DateEncodingStrategy
        /// Strategy for encoding `Data` values.  Defaults to `.base64`.
        public let dataEncodingStrategy: DataEncodingStrategy
        /// Strategy for encoding `String` values.  Defaults to `.text`.
        ///
        /// Set to `.cdata` to wrap all string content in CDATA sections. Use the `@XMLCDATA`
        /// macro to override this on a per-field basis.
        public let stringEncodingStrategy: StringEncodingStrategy
        /// Strategy for transforming Swift coding keys into XML element and attribute names.
        ///
        /// Defaults to `.useDefaultKeys` (identity — no transformation).
        /// Set to `.capitalized` for SOAP/PascalCase XML, `.convertToSnakeCase` for snake_case XML, etc.
        public let keyTransformStrategy: XMLKeyTransformStrategy
        /// Configuration forwarded to the underlying `XMLTreeWriter`.
        public let writerConfiguration: XMLTreeWriter.Configuration
        /// Validation policy applied during encoding.
        ///
        /// Controls whether element names and other structural values are validated.
        /// Defaults to ``XMLValidationPolicy/default``, which respects the
        /// `SWIFT_XML_CODER_STRICT_VALIDATION` compile-time flag.
        public let validationPolicy: XMLValidationPolicy
        /// Logger used for encode-time diagnostics.
        ///
        /// Defaults to `Logger(label: "SwiftXMLCoder")` with a `.critical` effective threshold
        /// until `LoggingSystem.bootstrap` is called by the application.
        public let logger: Logger
        /// Contextual user information forwarded to every `encode(to:)` call via `encoder.userInfo`.
        ///
        /// Use this to pass application-specific context (feature flags, locale, DI tokens, etc.)
        /// into custom `Encodable` implementations without polluting the type signature.
        ///
        /// ```swift
        /// let key = CodingUserInfoKey(rawValue: "locale")!
        /// var config = XMLEncoder.Configuration()
        /// config = XMLEncoder.Configuration(userInfo: [key: Locale.current])
        /// ```
        public let userInfo: [CodingUserInfoKey: Any]

        /// Creates an encoder configuration.
        ///
        /// - Parameters:
        ///   - rootElementName: Override the root element name. `nil` resolves from `@XMLRootNode` or the type name.
        ///   - itemElementName: Element name for collection items. Defaults to `"item"`.
        ///   - fieldCodingOverrides: Per-field node-kind overrides. Defaults to empty (all elements).
        ///   - nilEncodingStrategy: How `nil` values are represented. Defaults to `.emptyElement`.
        ///   - dateEncodingStrategy: How `Date` values are serialised. Defaults to `.xsdDateTimeISO8601`.
        ///   - dataEncodingStrategy: How `Data` values are serialised. Defaults to `.base64`.
        ///   - stringEncodingStrategy: How `String` values are serialised. Defaults to `.text`. Use `.cdata` to wrap all strings in CDATA sections.
        ///   - keyTransformStrategy: Transformation applied to coding key names. Defaults to `.useDefaultKeys`.
        ///   - writerConfiguration: Writer options forwarded to `XMLTreeWriter`.
        ///   - validationPolicy: Structural validation policy. Defaults to ``XMLValidationPolicy/default``.
        ///   - logger: Logger for encode-time diagnostics. Defaults to `Logger(label: "SwiftXMLCoder")`.
        ///   - userInfo: Context dictionary forwarded to `encoder.userInfo`. Defaults to empty.
        public init(
            rootElementName: String? = nil,
            itemElementName: String = "item",
            fieldCodingOverrides: XMLFieldCodingOverrides = XMLFieldCodingOverrides(),
            nilEncodingStrategy: NilEncodingStrategy = .emptyElement,
            dateEncodingStrategy: DateEncodingStrategy = .xsdDateTimeISO8601,
            dataEncodingStrategy: DataEncodingStrategy = .base64,
            stringEncodingStrategy: StringEncodingStrategy = .text,
            keyTransformStrategy: XMLKeyTransformStrategy = .useDefaultKeys,
            writerConfiguration: XMLTreeWriter.Configuration = XMLTreeWriter.Configuration(),
            validationPolicy: XMLValidationPolicy = .default,
            logger: Logger = Logger(label: "SwiftXMLCoder"),
            userInfo: [CodingUserInfoKey: Any] = [:]
        ) {
            self.rootElementName = rootElementName
            self.itemElementName = itemElementName
            self.fieldCodingOverrides = fieldCodingOverrides
            self.nilEncodingStrategy = nilEncodingStrategy
            self.dateEncodingStrategy = dateEncodingStrategy
            self.dataEncodingStrategy = dataEncodingStrategy
            self.stringEncodingStrategy = stringEncodingStrategy
            self.keyTransformStrategy = keyTransformStrategy
            self.writerConfiguration = writerConfiguration
            self.validationPolicy = validationPolicy
            self.logger = logger
            self.userInfo = userInfo
        }
    }

    /// The configuration used by this encoder.
    public let configuration: Configuration

    /// Creates a new encoder with the supplied configuration.
    /// - Parameter configuration: Encoding options.  Defaults to `Configuration()`.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    #if swift(>=6.0)
    /// Encodes `value` into an `XMLTreeDocument`.
    ///
    /// Use this when you need to inspect or manipulate the tree before serialising.
    /// - Parameter value: The value to encode.
    /// - Returns: An `XMLTreeDocument` whose root element represents `value`.
    /// - Throws: `XMLParsingError` on encoding failure.
    public func encodeTree<T: Encodable>(_ value: T) throws(XMLParsingError) -> XMLTreeDocument {
        do {
            return try encodeTreeImpl(value)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML encode tree error.")
        }
    }

    /// Encodes `value` into raw XML `Data`.
    ///
    /// Internally encodes to an `XMLTreeDocument` and then serialises using the
    /// `writerConfiguration` from `configuration`.
    /// - Parameter value: The value to encode.
    /// - Returns: UTF-8 encoded XML data.
    /// - Throws: `XMLParsingError` on encoding or serialisation failure.
    public func encode<T: Encodable>(_ value: T) throws(XMLParsingError) -> Data {
        do {
            let tree = try encodeTreeImpl(value)
            let writer = XMLTreeWriter(configuration: configuration.writerConfiguration)
            return try writer.writeData(tree)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML encode error.")
        }
    }
    #else
    /// Encodes `value` into an `XMLTreeDocument`.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: An `XMLTreeDocument` whose root element represents `value`.
    /// - Throws: `XMLParsingError` on encoding failure.
    public func encodeTree<T: Encodable>(_ value: T) throws -> XMLTreeDocument {
        try encodeTreeImpl(value)
    }

    /// Encodes `value` into raw XML `Data`.
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: UTF-8 encoded XML data.
    /// - Throws: `XMLParsingError` on encoding or serialisation failure.
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let tree = try encodeTreeImpl(value)
        let writer = XMLTreeWriter(configuration: configuration.writerConfiguration)
        return try writer.writeData(tree)
    }
    #endif

    private func encodeTreeImpl<T: Encodable>(_ value: T) throws -> XMLTreeDocument {
        var logger = configuration.logger
        logger[metadataKey: "component"] = "XMLEncoder"
        let rootElementName = try resolveRootElementName(for: T.self, logger: logger)
        logger.debug("XML encode started", metadata: ["type": "\(T.self)", "rootElement": "\(rootElementName)"])
        let rootNamespaceURI = XMLRootNameResolver.implicitRootElementNamespaceURI(for: T.self)
        let rootNamespaceDeclarations: [XMLNamespaceDeclaration] = rootNamespaceURI.map {
            [XMLNamespaceDeclaration(prefix: nil, uri: $0)]
        } ?? []
        let rootNode = _XMLTreeElementBox(
            name: XMLQualifiedName(localName: rootElementName, namespaceURI: rootNamespaceURI),
            namespaceDeclarations: rootNamespaceDeclarations
        )
        var options = try _XMLEncoderOptions(configuration: configuration)
        options.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        options.perPropertyStringHints = _xmlPropertyStringHints(for: T.self)
        options.perPropertyExpandEmptyKeys = _xmlPropertyExpandEmptyKeys(for: T.self)
        let encoder = _XMLTreeEncoder(
            options: options,
            codingPath: [],
            node: rootNode,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self)
        )
        // Intercept Foundation scalar types (URL, UUID, Decimal, Date, Data, …) whose
        // Codable conformances use keyed containers internally, bypassing our scalar path.
        // Box them directly as root element text content, mirroring the decoder intercept.
        if let scalar = try encoder.boxedScalar(value, codingPath: [], localName: rootElementName) {
            rootNode.appendText(scalar)
        } else {
            try value.encode(to: encoder)
        }
        let root = rootNode.makeElement()
        logger.debug(
            "XML encode completed",
            metadata: ["rootElement": "\(rootElementName)", "childCount": "\(root.children.count)"]
        )
        return XMLTreeDocument(root: root)
    }

    private func resolveRootElementName<T>(for type: T.Type, logger: Logger) throws -> String {
        let policy = configuration.validationPolicy

        if let explicitName = try XMLRootNameResolver.explicitRootElementName(
            from: configuration.rootElementName,
            validationPolicy: policy
        ) {
            let raw = configuration.rootElementName ?? ""
            if explicitName != raw {
                logger.warning(
                    "rootElementName sanitized",
                    metadata: ["original": "\(raw)", "sanitized": "\(explicitName)"]
                )
            }
            return explicitName
        }

        if let implicitName = try XMLRootNameResolver.implicitRootElementName(for: type, validationPolicy: policy) {
            if let rawName = (type as? XMLRootNode.Type)?.xmlRootElementName, rawName != implicitName {
                logger.warning(
                    "XMLRootNode.xmlRootElementName sanitized",
                    metadata: ["type": "\(T.self)", "original": "\(rawName)", "sanitized": "\(implicitName)"]
                )
            }
            return implicitName
        }

        let fallback = XMLRootNameResolver.fallbackRootElementName(for: type)
        logger.debug(
            "Root element name derived from type name",
            metadata: ["type": "\(T.self)", "rootElement": "\(fallback)"]
        )
        return fallback
    }
}
