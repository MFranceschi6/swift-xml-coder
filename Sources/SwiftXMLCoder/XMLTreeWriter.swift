import Foundation
import XMLCoderCompatibility
import SwiftXMLCoderCShim

/// Serialises an ``XMLTreeDocument`` to an ``XMLDocument`` or raw UTF-8 XML `Data`.
///
/// `XMLTreeWriter` is the write-side of the XML tree layer. It takes an immutable
/// ``XMLTreeDocument`` value produced by ``XMLEncoder`` (or assembled manually) and
/// emits well-formed XML output via libxml2.
///
/// ## Security limits
/// All size limits default to unlimited. For untrusted output destinations, use
/// ``XMLTreeWriter/Configuration/untrustedInputProfile(encoding:prettyPrinted:)`` which
/// caps `maxDepth`, `maxNodeCount`, `maxOutputBytes`, and text content sizes.
///
/// - SeeAlso: ``XMLTreeDocument``, ``XMLTreeParser``, ``XMLEncoder``
public struct XMLTreeWriter: Sendable {
    /// Controls the serialisation order of XML attributes.
    public enum AttributeOrderingPolicy: Sendable, Hashable {
        /// Preserve the order attributes were added to the element.
        case preserve
        /// Sort attributes lexicographically by local name for deterministic output.
        case lexicographical
    }

    /// Controls the serialisation order of `xmlns:` namespace declarations.
    public enum NamespaceDeclarationOrderingPolicy: Sendable, Hashable {
        /// Preserve the order namespace declarations were added to the element.
        case preserve
        /// Sort namespace declarations lexicographically by prefix for deterministic output.
        case lexicographical
    }

    /// Controls how whitespace-only text nodes are handled during serialisation.
    public enum WhitespaceTextNodePolicy: Sendable, Hashable {
        /// Emit whitespace-only text nodes unchanged.
        case preserve
        /// Drop text nodes whose content is entirely whitespace.
        case omitWhitespaceOnly
        /// Trim leading and trailing whitespace from all text nodes.
        case trim
        /// Normalise runs of whitespace and trim leading/trailing whitespace.
        case normalizeAndTrim
    }

    /// Controls whether serialisation output is fully deterministic.
    public enum DeterministicSerializationMode: Sendable, Hashable {
        /// No additional sorting; preserve natural insertion order.
        case disabled
        /// Sort attributes and namespace declarations for deterministic output (implies lexicographical policies).
        case stable
    }

    /// Controls how missing namespace declarations are handled during serialisation.
    public enum NamespaceValidationMode: Sendable, Hashable {
        /// Throw an error if a namespace prefix is used without a corresponding declaration.
        case strict
        /// Automatically synthesise missing `xmlns:prefix="uri"` declarations.
        case synthesizeMissingDeclarations

        var validatorMode: XMLNamespaceValidator.Mode {
            switch self {
            case .strict:
                return .strict
            case .synthesizeMissingDeclarations:
                return .synthesizeMissingDeclarations
            }
        }
    }

    /// Output size limits enforced during serialisation.
    ///
    /// All limits default to unlimited. Use ``untrustedInputDefault()`` for sensible
    /// defensive values when writing output that will be sent to untrusted consumers.
    public struct Limits: Sendable, Hashable {
        /// Maximum allowed element nesting depth. Default: 4096.
        public let maxDepth: Int
        /// Maximum total node count across the tree. `nil` = unlimited.
        public let maxNodeCount: Int?
        /// Maximum serialised output size in bytes. `nil` = unlimited.
        public let maxOutputBytes: Int?
        /// Maximum size of any single text node in bytes. `nil` = unlimited.
        public let maxTextNodeBytes: Int?
        /// Maximum size of any CDATA block in bytes. `nil` = unlimited.
        public let maxCDATABlockBytes: Int?
        /// Maximum size of any XML comment in bytes. `nil` = unlimited.
        public let maxCommentBytes: Int?

        /// Creates writer limits.
        ///
        /// - Parameters:
        ///   - maxDepth: Maximum nesting depth. Values below 1 are clamped to 1.
        ///   - maxNodeCount: Maximum node count. `nil` = unlimited.
        ///   - maxOutputBytes: Maximum serialised byte count. `nil` = unlimited.
        ///   - maxTextNodeBytes: Maximum text node size. `nil` = unlimited.
        ///   - maxCDATABlockBytes: Maximum CDATA block size. `nil` = unlimited.
        ///   - maxCommentBytes: Maximum XML comment size. `nil` = unlimited.
        public init(
            maxDepth: Int = 4096,
            maxNodeCount: Int? = nil,
            maxOutputBytes: Int? = nil,
            maxTextNodeBytes: Int? = nil,
            maxCDATABlockBytes: Int? = nil,
            maxCommentBytes: Int? = nil
        ) {
            self.maxDepth = max(1, maxDepth)
            self.maxNodeCount = maxNodeCount
            self.maxOutputBytes = maxOutputBytes
            self.maxTextNodeBytes = maxTextNodeBytes
            self.maxCDATABlockBytes = maxCDATABlockBytes
            self.maxCommentBytes = maxCommentBytes
        }

        /// Sensible conservative limits for output sent to untrusted consumers.
        ///
        /// Caps: `maxDepth`=256, `maxNodeCount`=200,000, `maxOutputBytes`=16 MiB,
        /// `maxTextNodeBytes`=1 MiB, `maxCDATABlockBytes`=4 MiB, `maxCommentBytes`=256 KiB.
        public static func untrustedInputDefault() -> Limits {
            Limits(
                maxDepth: 256,
                maxNodeCount: 200_000,
                maxOutputBytes: 16 * 1024 * 1024,
                maxTextNodeBytes: 1 * 1024 * 1024,
                maxCDATABlockBytes: 4 * 1024 * 1024,
                maxCommentBytes: 256 * 1024
            )
        }
    }

    /// Full configuration for the XML tree writer.
    public struct Configuration: Sendable, Hashable {
        /// The XML encoding declaration. Defaults to `"UTF-8"`.
        public let encoding: String
        /// Whether to emit indented, human-readable output. Defaults to `false`.
        public let prettyPrinted: Bool
        /// How attributes are ordered. Defaults to `.preserve`.
        public let attributeOrderingPolicy: AttributeOrderingPolicy
        /// How namespace declarations are ordered. Defaults to `.preserve`.
        public let namespaceDeclarationOrderingPolicy: NamespaceDeclarationOrderingPolicy
        /// How whitespace-only text nodes are handled. Defaults to `.preserve`.
        public let whitespaceTextNodePolicy: WhitespaceTextNodePolicy
        /// Whether output is fully deterministic. Defaults to `.disabled`.
        public let deterministicSerializationMode: DeterministicSerializationMode
        /// How missing namespace declarations are handled. Defaults to `.strict`.
        public let namespaceValidationMode: NamespaceValidationMode
        /// Output size limits. Defaults to unlimited.
        public let limits: Limits

        /// Creates a writer configuration.
        public init(
            encoding: String = "UTF-8",
            prettyPrinted: Bool = false,
            attributeOrderingPolicy: AttributeOrderingPolicy = .preserve,
            namespaceDeclarationOrderingPolicy: NamespaceDeclarationOrderingPolicy = .preserve,
            whitespaceTextNodePolicy: WhitespaceTextNodePolicy = .preserve,
            deterministicSerializationMode: DeterministicSerializationMode = .disabled,
            namespaceValidationMode: NamespaceValidationMode = .strict,
            limits: Limits = Limits()
        ) {
            self.encoding = encoding
            self.prettyPrinted = prettyPrinted
            self.attributeOrderingPolicy = attributeOrderingPolicy
            self.namespaceDeclarationOrderingPolicy = namespaceDeclarationOrderingPolicy
            self.whitespaceTextNodePolicy = whitespaceTextNodePolicy
            self.deterministicSerializationMode = deterministicSerializationMode
            self.namespaceValidationMode = namespaceValidationMode
            self.limits = limits
        }

        /// A configuration profile for serialising output sent to untrusted consumers.
        ///
        /// Applies ``Limits/untrustedInputDefault()`` and `.strict` namespace validation.
        public static func untrustedInputProfile(
            encoding: String = "UTF-8",
            prettyPrinted: Bool = false
        ) -> Configuration {
            Configuration(
                encoding: encoding,
                prettyPrinted: prettyPrinted,
                attributeOrderingPolicy: .preserve,
                namespaceDeclarationOrderingPolicy: .preserve,
                whitespaceTextNodePolicy: .preserve,
                deterministicSerializationMode: .disabled,
                namespaceValidationMode: .strict,
                limits: .untrustedInputDefault()
            )
        }
    }

    struct WriteState {
        var nodeCount: Int = 0
    }

    /// The active configuration for this writer.
    public let configuration: Configuration

    /// Creates an XML tree writer with the given configuration.
    ///
    /// - Parameter configuration: Writer options. Defaults to ``Configuration/init()``.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    #if swift(>=6.0)
    /// Serialises the tree document into a libxml2 ``XMLDocument`` object.
    ///
    /// Use this when you need access to the intermediate `XMLDocument` (e.g. for XPath queries).
    ///
    /// - Parameter treeDocument: The tree document to serialise.
    /// - Returns: An ``XMLDocument`` ready for further manipulation or serialisation.
    /// - Throws: ``XMLParsingError`` on serialisation failure or limit violation.
    public func writeDocument(_ treeDocument: XMLTreeDocument) throws(XMLParsingError) -> XMLDocument {
        do {
            return try writeDocumentImpl(treeDocument)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML tree writer error.")
        }
    }

    /// Serialises the tree document to raw UTF-8 XML `Data`.
    ///
    /// - Parameter treeDocument: The tree document to serialise.
    /// - Returns: Well-formed UTF-8 XML bytes.
    /// - Throws: ``XMLParsingError`` on serialisation failure or limit violation.
    public func writeData(_ treeDocument: XMLTreeDocument) throws(XMLParsingError) -> Data {
        do {
            let xmlDocument = try writeDocument(treeDocument)
            let xmlData = try xmlDocument.serializedData(
                encoding: configuration.encoding,
                prettyPrinted: configuration.prettyPrinted
            )
            try ensureLimit(
                actual: xmlData.count,
                limit: configuration.limits.maxOutputBytes,
                code: "XML6_2H_MAX_OUTPUT_BYTES",
                context: "serialized XML output bytes"
            )
            return xmlData
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XML tree writer error.")
        }
    }
    #else
    /// Serialises the tree document into a libxml2 ``XMLDocument`` object.
    ///
    /// - Parameter treeDocument: The tree document to serialise.
    /// - Returns: An ``XMLDocument`` ready for further manipulation or serialisation.
    /// - Throws: ``XMLParsingError`` on serialisation failure or limit violation.
    public func writeDocument(_ treeDocument: XMLTreeDocument) throws -> XMLDocument {
        try writeDocumentImpl(treeDocument)
    }

    /// Serialises the tree document to raw UTF-8 XML `Data`.
    ///
    /// - Parameter treeDocument: The tree document to serialise.
    /// - Returns: Well-formed UTF-8 XML bytes.
    /// - Throws: ``XMLParsingError`` on serialisation failure or limit violation.
    public func writeData(_ treeDocument: XMLTreeDocument) throws -> Data {
        let xmlDocument = try writeDocument(treeDocument)
        let xmlData = try xmlDocument.serializedData(
            encoding: configuration.encoding,
            prettyPrinted: configuration.prettyPrinted
        )
        try ensureLimit(
            actual: xmlData.count,
            limit: configuration.limits.maxOutputBytes,
            code: "XML6_2H_MAX_OUTPUT_BYTES",
            context: "serialized XML output bytes"
        )
        return xmlData
    }
    #endif

}
