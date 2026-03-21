import Foundation
import Logging

/// Parses raw XML data into a stream of ``XMLStreamEvent`` values using libxml2's SAX API.
///
/// Unlike ``XMLTreeParser``, `XMLStreamParser` does **not** materialise the full document
/// in memory. It emits events as the parser encounters them, making it suitable for large
/// documents or pipelines that only need a subset of the data.
///
/// ## Security limits
/// `XMLStreamParser` reuses ``XMLTreeParser/Configuration`` and its associated
/// ``XMLTreeParser/Limits``. For untrusted inputs, use
/// ``XMLTreeParser/Configuration/untrustedInputProfile(whitespaceTextNodePolicy:logger:)``.
///
/// ## Callback API (all Swift versions)
///
/// ```swift
/// let parser = XMLStreamParser()
/// try parser.parse(data: xmlData) { event in
///     if case .startElement(let name, _, _) = event {
///         process(name.localName)
///     }
/// }
/// ```
///
/// ## AsyncSequence API (macOS 12+, iOS 15+)
///
/// ```swift
/// let parser = XMLStreamParser()
/// for try await event in parser.events(for: xmlData) {
///     if case .startElement(let name, _, _) = event {
///         process(name.localName)
///     }
/// }
/// ```
///
/// - SeeAlso: ``XMLStreamEvent``, ``XMLStreamWriter``, ``XMLTreeParser``
public struct XMLStreamParser: Sendable {

    /// The active configuration for this parser.
    ///
    /// Reuses ``XMLTreeParser/Configuration``: whitespace policy, libxml2 parsing options,
    /// security limits, and logger are all shared between the two parser types.
    public let configuration: XMLTreeParser.Configuration

    /// Creates an XML stream parser with the given configuration.
    ///
    /// - Parameter configuration: Parser options. Defaults to ``XMLTreeParser/Configuration/init()``.
    public init(configuration: XMLTreeParser.Configuration = XMLTreeParser.Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Sync callback API

    #if swift(>=6.0)
    /// Parses raw XML data, calling `onEvent` for each ``XMLStreamEvent``.
    ///
    /// Parsing is synchronous: this method blocks until the full document is parsed or an
    /// error occurs. `onEvent` is called in document order from the calling thread.
    ///
    /// - Parameters:
    ///   - data: Raw UTF-8 encoded XML bytes.
    ///   - onEvent: Closure invoked for each event. Called synchronously; must not retain
    ///     the parser or cause re-entrant parsing.
    /// - Throws: ``XMLParsingError`` on parse failure or limit violation.
    public func parse(
        data: Data,
        onEvent: (XMLStreamEvent) -> Void
    ) throws(XMLParsingError) {
        do {
            try parseSAX(data: data, onEvent: onEvent)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLStreamParser error.")
        }
    }
    #else
    /// Parses raw XML data, calling `onEvent` for each ``XMLStreamEvent``.
    ///
    /// - Parameters:
    ///   - data: Raw UTF-8 encoded XML bytes.
    ///   - onEvent: Closure invoked for each event in document order.
    /// - Throws: ``XMLParsingError`` on parse failure or limit violation.
    public func parse(
        data: Data,
        onEvent: (XMLStreamEvent) -> Void
    ) throws {
        try parseSAX(data: data, onEvent: onEvent)
    }
    #endif

    // MARK: - AsyncSequence API

    /// Returns an ``AsyncThrowingStream`` that emits ``XMLStreamEvent`` values as the XML
    /// document is parsed.
    ///
    /// The SAX parse runs on the calling async context. Task cancellation is checked before
    /// each event is yielded; if cancelled, parsing is aborted and the stream terminates
    /// without error.
    ///
    /// ```swift
    /// for try await event in parser.events(for: data) {
    ///     // process event
    /// }
    /// ```
    ///
    /// - Parameter data: Raw UTF-8 encoded XML bytes.
    /// - Returns: A stream of ``XMLStreamEvent`` values in document order.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func events(for data: Data) -> AsyncThrowingStream<XMLStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                try parseSAX(data: data) { event in
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
