import Foundation

/// Serialises a sequence of ``XMLStreamEvent`` values to well-formed UTF-8 XML `Data`
/// using libxml2's `xmlTextWriter` API.
///
/// `XMLStreamWriter` is the event-driven counterpart to ``XMLStreamParser``. It accepts
/// any `Sequence` (or `AsyncSequence`) of ``XMLStreamEvent`` values and writes them
/// incrementally to an in-memory buffer, producing `Data` on completion.
///
/// ## Symmetric round-trip
///
/// ```swift
/// // Sync
/// var events: [XMLStreamEvent] = []
/// try XMLStreamParser().parse(data: input) { events.append($0) }
/// let output = try XMLStreamWriter().write(events)
///
/// // Async (macOS 12+)
/// let output = try await XMLStreamWriter().write(XMLStreamParser().events(for: input))
/// ```
///
/// ## Security limits
/// All limits default to unlimited. Use
/// ``XMLStreamWriter/Configuration/untrustedOutputProfile(encoding:prettyPrinted:)``
/// to apply defensive caps when writing output that will be consumed by untrusted systems.
///
/// - SeeAlso: ``XMLStreamEvent``, ``XMLStreamParser``, ``XMLTreeWriter``
public struct XMLStreamWriter: Sendable {

    // MARK: - WriterLimits

    /// Output size limits enforced during serialisation.
    public struct WriterLimits: Sendable, Hashable {
        /// Maximum element nesting depth. `nil` = unlimited.
        public let maxDepth: Int?
        /// Maximum total node count. `nil` = unlimited.
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
        public init(
            maxDepth: Int? = nil,
            maxNodeCount: Int? = nil,
            maxOutputBytes: Int? = nil,
            maxTextNodeBytes: Int? = nil,
            maxCDATABlockBytes: Int? = nil,
            maxCommentBytes: Int? = nil
        ) {
            self.maxDepth = maxDepth
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
        public static func untrustedOutputDefault() -> WriterLimits {
            WriterLimits(
                maxDepth: 256,
                maxNodeCount: 200_000,
                maxOutputBytes: 16 * 1024 * 1024,
                maxTextNodeBytes: 1 * 1024 * 1024,
                maxCDATABlockBytes: 4 * 1024 * 1024,
                maxCommentBytes: 256 * 1024
            )
        }
    }

    // MARK: - Configuration

    /// Full configuration for the XML stream writer.
    public struct Configuration: Sendable, Hashable {
        /// The XML encoding declaration. Defaults to `"UTF-8"`.
        public let encoding: String
        /// Whether to emit indented, human-readable output. Defaults to `false`.
        public let prettyPrinted: Bool
        /// Whether empty elements are always expanded as `<tag></tag>` instead of `<tag/>`.
        ///
        /// Defaults to `false`.
        public let expandEmptyElements: Bool
        /// Output size limits. Defaults to unlimited.
        public let limits: WriterLimits

        /// Creates a writer configuration.
        public init(
            encoding: String = "UTF-8",
            prettyPrinted: Bool = false,
            expandEmptyElements: Bool = false,
            limits: WriterLimits = WriterLimits()
        ) {
            self.encoding = encoding
            self.prettyPrinted = prettyPrinted
            self.expandEmptyElements = expandEmptyElements
            self.limits = limits
        }

        /// A configuration profile for output sent to untrusted consumers.
        ///
        /// Applies ``WriterLimits/untrustedOutputDefault()``.
        public static func untrustedOutputProfile(
            encoding: String = "UTF-8",
            prettyPrinted: Bool = false
        ) -> Configuration {
            Configuration(
                encoding: encoding,
                prettyPrinted: prettyPrinted,
                expandEmptyElements: false,
                limits: .untrustedOutputDefault()
            )
        }
    }

    // MARK: - Stored properties

    /// The active configuration for this writer.
    public let configuration: Configuration

    /// Creates an XML stream writer with the given configuration.
    ///
    /// - Parameter configuration: Writer options. Defaults to ``Configuration/init()``.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Sync API

    #if swift(>=6.0)
    /// Serialises a sequence of ``XMLStreamEvent`` values to UTF-8 XML `Data`.
    ///
    /// - Parameter events: Any `Sequence` whose element is ``XMLStreamEvent``.
    ///   A plain `[XMLStreamEvent]` array works directly.
    /// - Returns: Well-formed UTF-8 XML bytes.
    /// - Throws: ``XMLParsingError`` on serialisation failure or limit violation.
    public func write<S: Sequence>(
        _ events: S
    ) throws(XMLParsingError) -> Data where S.Element == XMLStreamEvent {
        do {
            return try writeImpl(events)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLStreamWriter error.")
        }
    }
    #else
    /// Serialises a sequence of ``XMLStreamEvent`` values to UTF-8 XML `Data`.
    ///
    /// - Parameter events: Any `Sequence` whose element is ``XMLStreamEvent``.
    /// - Returns: Well-formed UTF-8 XML bytes.
    /// - Throws: ``XMLParsingError`` on serialisation failure or limit violation.
    public func write<S: Sequence>(
        _ events: S
    ) throws -> Data where S.Element == XMLStreamEvent {
        try writeImpl(events)
    }
    #endif

    // MARK: - Async API

    /// Serialises an async sequence of ``XMLStreamEvent`` values to UTF-8 XML `Data`.
    ///
    /// Consumes `events` one at a time, writing each to the output buffer. Suitable for
    /// piping directly from ``XMLStreamParser/events(for:)``.
    ///
    /// ```swift
    /// let output = try await writer.write(parser.events(for: data))
    /// ```
    ///
    /// - Parameter events: Any `AsyncSequence` whose element is ``XMLStreamEvent``.
    /// - Returns: Well-formed UTF-8 XML bytes.
    /// - Throws: ``XMLParsingError`` on serialisation failure or limit violation.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func write<S: AsyncSequence>(
        _ events: S
    ) async throws -> Data where S.Element == XMLStreamEvent {
        var collected: [XMLStreamEvent] = []
        for try await event in events {
            collected.append(event)
        }
        return try writeImpl(collected)
    }
}
