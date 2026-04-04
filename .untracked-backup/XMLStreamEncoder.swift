import Foundation

/// Encodes an `Encodable` value into a sequence of ``XMLStreamEvent`` values.
///
/// `XMLStreamEncoder` is the Codable bridge for the streaming layer. It encodes an
/// `Encodable` value by delegating to ``XMLEncoder`` to produce an ``XMLTreeDocument``
/// and then walks the tree emitting one ``XMLStreamEvent`` per node.
///
/// The event sequence is identical to what ``XMLStreamParser`` would emit when parsing
/// the XML that ``XMLEncoder`` would produce for the same value and configuration.
///
/// ## Sync encoding
///
/// ```swift
/// let encoder = XMLStreamEncoder()
/// let events = try encoder.encode(myValue)
/// // pass events to XMLStreamWriter, process them, or inspect them directly
/// ```
///
/// ## Async encoding (macOS 12+)
///
/// ```swift
/// let stream = XMLStreamEncoder().encodeAsync(myValue)
/// let data = try await XMLStreamWriter().write(stream)
/// ```
///
/// ## Full pipeline (Encodable → Data via events)
///
/// ```swift
/// let events = try XMLStreamEncoder().encode(myValue)
/// let data   = try XMLStreamWriter().write(events)
/// // identical bytes to XMLEncoder().encode(myValue)
/// ```
///
/// - SeeAlso: ``XMLStreamDecoder``, ``XMLStreamWriter``, ``XMLEncoder``
public struct XMLStreamEncoder: Sendable {

    /// The encoder configuration forwarded to the underlying ``XMLEncoder``.
    public let configuration: XMLEncoder.Configuration

    /// Creates an XML stream encoder with the given configuration.
    ///
    /// - Parameter configuration: Encoder options. Defaults to ``XMLEncoder/Configuration/init()``.
    public init(configuration: XMLEncoder.Configuration = XMLEncoder.Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Sync API

    #if swift(>=6.0)
    /// Encodes `value` into an array of ``XMLStreamEvent`` values.
    ///
    /// - Parameter value: The value to encode. Must conform to `Encodable`.
    /// - Returns: An ordered array of events representing the XML document.
    /// - Throws: ``XMLParsingError`` on encoding failure.
    public func encode<T: Encodable>(_ value: T) throws(XMLParsingError) -> [XMLStreamEvent] {
        do {
            return try encodeImpl(value)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLStreamEncoder error.")
        }
    }
    #else
    /// Encodes `value` into an array of ``XMLStreamEvent`` values.
    ///
    /// - Parameter value: The value to encode. Must conform to `Encodable`.
    /// - Returns: An ordered array of events representing the XML document.
    /// - Throws: ``XMLParsingError`` on encoding failure.
    public func encode<T: Encodable>(_ value: T) throws -> [XMLStreamEvent] {
        try encodeImpl(value)
    }
    #endif

    // MARK: - Async API

    /// Returns an ``AsyncThrowingStream`` that emits ``XMLStreamEvent`` values for `value`.
    ///
    /// The encoding is performed synchronously when the stream is iterated; events are
    /// yielded one at a time. The full event array is materialised before any yield occurs
    /// — this is a protocol constraint of `Encodable` (random-access key lookup), not a
    /// design limitation.
    ///
    /// ```swift
    /// let data = try await XMLStreamWriter().write(XMLStreamEncoder().encodeAsync(myValue))
    /// ```
    ///
    /// - Parameter value: The value to encode.
    /// - Returns: A stream of ``XMLStreamEvent`` values in document order.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func encodeAsync<T: Encodable>(_ value: T) -> AsyncThrowingStream<XMLStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let events = try encodeImpl(value)
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Private implementation

    private func encodeImpl<T: Encodable>(_ value: T) throws -> [XMLStreamEvent] {
        let document = try XMLEncoder(configuration: configuration).encodeTree(value)
        return eventsFromDocument(document)
    }

    private func eventsFromDocument(_ document: XMLTreeDocument) -> [XMLStreamEvent] {
        var events: [XMLStreamEvent] = []
        events.append(.startDocument(
            version: document.metadata.xmlVersion,
            encoding: document.metadata.encoding,
            standalone: document.metadata.standalone
        ))
        eventsFromElement(document.root, into: &events)
        events.append(.endDocument)
        return events
    }

    private func eventsFromElement(_ element: XMLTreeElement, into events: inout [XMLStreamEvent]) {
        events.append(.startElement(
            name: element.name,
            attributes: element.attributes,
            namespaceDeclarations: element.namespaceDeclarations
        ))
        for child in element.children {
            switch child {
            case .element(let childElement):
                eventsFromElement(childElement, into: &events)
            case .text(let string):
                events.append(.text(string))
            case .cdata(let string):
                events.append(.cdata(string))
            case .comment(let string):
                events.append(.comment(string))
            }
        }
        events.append(.endElement(name: element.name))
    }
}
