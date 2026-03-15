import Foundation
import XMLCoderCompatibility
import SwiftXMLCoderCShim

/// Parses raw XML data into an immutable ``XMLTreeDocument``.
///
/// `XMLTreeParser` is the read-side of the XML tree layer. It wraps libxml2's SAX
/// parser and produces a fully materialised ``XMLTreeDocument`` tree.
///
/// ## Security limits
/// All limits default to unlimited. For untrusted inputs, use
/// ``XMLTreeParser/Configuration/untrustedInputProfile(preserveWhitespaceTextNodes:whitespaceTextNodePolicy:)``
/// which enforces conservative caps on input size, depth, node count, and text sizes.
///
/// - SeeAlso: ``XMLTreeDocument``, ``XMLTreeWriter``, ``XMLDecoder``
public struct XMLTreeParser: Sendable {
    /// Controls how whitespace-only text nodes are handled after parsing.
    public enum WhitespaceTextNodePolicy: Sendable, Hashable {
        /// Preserve all text nodes exactly as parsed.
        case preserve
        /// Drop text nodes that consist entirely of whitespace characters.
        case dropWhitespaceOnly
        /// Trim leading and trailing whitespace from all text nodes.
        case trim
        /// Normalise runs of whitespace and trim leading/trailing whitespace.
        case normalizeAndTrim
    }

    /// Input size limits enforced during parsing.
    ///
    /// All limits default to unlimited. Use ``untrustedInputDefault()`` for sensible
    /// defensive values when parsing inputs from untrusted sources.
    public struct Limits: Sendable, Hashable {
        /// Maximum allowed input byte count before parsing begins. `nil` = unlimited.
        public let maxInputBytes: Int?
        /// Maximum allowed element nesting depth. Default: 4096.
        public let maxDepth: Int
        /// Maximum total node count across the tree. `nil` = unlimited.
        public let maxNodeCount: Int?
        /// Maximum attribute count per element. `nil` = unlimited.
        public let maxAttributesPerElement: Int?
        /// Maximum size of any single text node in bytes. `nil` = unlimited.
        public let maxTextNodeBytes: Int?
        /// Maximum size of any CDATA block in bytes. `nil` = unlimited.
        public let maxCDATABlockBytes: Int?

        /// Creates parser limits.
        public init(
            maxInputBytes: Int? = nil,
            maxDepth: Int = 4096,
            maxNodeCount: Int? = nil,
            maxAttributesPerElement: Int? = nil,
            maxTextNodeBytes: Int? = nil,
            maxCDATABlockBytes: Int? = nil
        ) {
            self.maxInputBytes = maxInputBytes
            self.maxDepth = max(1, maxDepth)
            self.maxNodeCount = maxNodeCount
            self.maxAttributesPerElement = maxAttributesPerElement
            self.maxTextNodeBytes = maxTextNodeBytes
            self.maxCDATABlockBytes = maxCDATABlockBytes
        }

        /// Sensible conservative limits for parsing input from untrusted sources.
        ///
        /// Caps: `maxInputBytes`=16 MiB, `maxDepth`=256, `maxNodeCount`=200,000,
        /// `maxAttributesPerElement`=256, `maxTextNodeBytes`=1 MiB, `maxCDATABlockBytes`=4 MiB.
        public static func untrustedInputDefault() -> Limits {
            Limits(
                maxInputBytes: 16 * 1024 * 1024,
                maxDepth: 256,
                maxNodeCount: 200_000,
                maxAttributesPerElement: 256,
                maxTextNodeBytes: 1 * 1024 * 1024,
                maxCDATABlockBytes: 4 * 1024 * 1024
            )
        }
    }

    /// Full configuration for the XML tree parser.
    public struct Configuration: Sendable, Hashable {
        /// How whitespace-only text nodes are handled. Defaults to `.dropWhitespaceOnly`.
        public let whitespaceTextNodePolicy: WhitespaceTextNodePolicy
        /// Low-level libxml2 parsing configuration (DTD, entity, external resource policies).
        public let parsingConfiguration: XMLDocument.ParsingConfiguration
        /// Input size limits. Defaults to unlimited.
        public let limits: Limits

        /// `true` when `whitespaceTextNodePolicy == .preserve`.
        public var preserveWhitespaceTextNodes: Bool {
            whitespaceTextNodePolicy == .preserve
        }

        /// Creates a parser configuration.
        ///
        /// - Parameters:
        ///   - preserveWhitespaceTextNodes: Legacy flag. When `whitespaceTextNodePolicy` is `nil`,
        ///     `true` resolves to `.preserve` and `false` to `.dropWhitespaceOnly`.
        ///   - whitespaceTextNodePolicy: Explicit whitespace policy. Overrides the legacy flag.
        ///   - parsingConfiguration: Low-level libxml2 parsing options.
        ///   - limits: Input size limits. Defaults to unlimited.
        public init(
            preserveWhitespaceTextNodes: Bool = false,
            whitespaceTextNodePolicy: WhitespaceTextNodePolicy? = nil,
            parsingConfiguration: XMLDocument.ParsingConfiguration = XMLDocument.ParsingConfiguration(),
            limits: Limits = Limits()
        ) {
            self.whitespaceTextNodePolicy = whitespaceTextNodePolicy ?? (
                preserveWhitespaceTextNodes ? .preserve : .dropWhitespaceOnly
            )
            self.parsingConfiguration = parsingConfiguration
            self.limits = limits
        }

        /// A configuration profile for parsing input from untrusted sources.
        ///
        /// Applies ``Limits/untrustedInputDefault()``, forbids network external resources,
        /// forbids DTD loading, and preserves entity references.
        public static func untrustedInputProfile(
            preserveWhitespaceTextNodes: Bool = false,
            whitespaceTextNodePolicy: WhitespaceTextNodePolicy? = nil
        ) -> Configuration {
            let resolvedWhitespacePolicy = whitespaceTextNodePolicy ?? (
                preserveWhitespaceTextNodes ? .preserve : .dropWhitespaceOnly
            )
            return Configuration(
                preserveWhitespaceTextNodes: preserveWhitespaceTextNodes,
                whitespaceTextNodePolicy: resolvedWhitespacePolicy,
                parsingConfiguration: XMLDocument.ParsingConfiguration(
                    trimBlankTextNodes: resolvedWhitespacePolicy != .preserve,
                    externalResourceLoadingPolicy: .forbidNetwork,
                    dtdLoadingPolicy: .forbid,
                    entityDecodingPolicy: .preserveReferences
                ),
                limits: .untrustedInputDefault()
            )
        }
    }

    struct ParseState {
        var nodeCount: Int = 0
    }

    /// The active configuration for this parser.
    public let configuration: Configuration

    /// Creates an XML tree parser with the given configuration.
    ///
    /// - Parameter configuration: Parser options. Defaults to ``Configuration/init()``.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    #if swift(>=6.0)
    /// Parses raw XML data into an ``XMLTreeDocument``.
    ///
    /// - Parameter data: Raw UTF-8 encoded XML bytes.
    /// - Returns: A fully materialised ``XMLTreeDocument``.
    /// - Throws: ``XMLParsingError`` on parse failure or limit violation.
    public func parse(data: Data) throws(XMLParsingError) -> XMLTreeDocument {
        do {
            try ensureLimit(
                actual: data.count,
                limit: configuration.limits.maxInputBytes,
                code: "XML6_2H_MAX_INPUT_BYTES",
                context: "XML input bytes"
            )

            let document = try XMLDocument(
                data: data,
                parsingConfiguration: effectiveParsingConfiguration()
            )
            return try parse(document: document)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML tree parse error.")
        }
    }

    /// Parses a pre-loaded ``XMLDocument`` into an ``XMLTreeDocument``.
    ///
    /// Use this when the libxml2 document is already available, avoiding a second parse.
    ///
    /// - Parameter document: The libxml2 document wrapper.
    /// - Returns: A fully materialised ``XMLTreeDocument``.
    /// - Throws: ``XMLParsingError`` on conversion failure or limit violation.
    public func parse(document: XMLDocument) throws(XMLParsingError) -> XMLTreeDocument {
        do {
            return try parseDocument(document)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML tree parse error.")
        }
    }
    #else
    /// Parses raw XML data into an ``XMLTreeDocument``.
    ///
    /// - Parameter data: Raw UTF-8 encoded XML bytes.
    /// - Returns: A fully materialised ``XMLTreeDocument``.
    /// - Throws: ``XMLParsingError`` on parse failure or limit violation.
    public func parse(data: Data) throws -> XMLTreeDocument {
        try ensureLimit(
            actual: data.count,
            limit: configuration.limits.maxInputBytes,
            code: "XML6_2H_MAX_INPUT_BYTES",
            context: "XML input bytes"
        )

        let document = try XMLDocument(
            data: data,
            parsingConfiguration: effectiveParsingConfiguration()
        )
        return try parse(document: document)
    }

    /// Parses a pre-loaded ``XMLDocument`` into an ``XMLTreeDocument``.
    ///
    /// - Parameter document: The libxml2 document wrapper.
    /// - Returns: A fully materialised ``XMLTreeDocument``.
    /// - Throws: ``XMLParsingError`` on conversion failure or limit violation.
    public func parse(document: XMLDocument) throws -> XMLTreeDocument {
        try parseDocument(document)
    }
    #endif
}
