import Foundation

/// A forward-only, pull-style cursor over a pre-parsed sequence of ``XMLStreamEvent`` values.
///
/// `XMLEventCursor` provides caller-controlled event consumption: you advance the cursor
/// explicitly by calling ``next()`` or ``advance(toElement:)``, unlike the push-based
/// ``XMLStreamParser`` where libxml2 drives execution.
///
/// ## Memory model
///
/// All events are materialised in memory when the cursor is created. Peak memory is
/// proportional to the number of events in the document, which is typically far smaller
/// than the full DOM tree produced by ``XMLTreeParser``.
///
/// ```swift
/// let cursor = try XMLEventCursor(data: xmlData)
/// while let event = cursor.next() {
///     if case .startElement(let name, _, _) = event {
///         print(name.localName)
///     }
/// }
/// ```
///
/// ## Thread safety
///
/// `XMLEventCursor` is **not thread-safe**. Call ``next()``, ``peek()``, and
/// ``advance(toElement:)`` from a single call context. Do not share a cursor across
/// concurrent tasks without external synchronisation.
///
/// ## Relationship to the push API
///
/// `XMLEventCursor` wraps ``XMLStreamParser`` internally: the full document is parsed
/// synchronously on ``init(data:configuration:)`` using the SAX API, then the resulting
/// event array is exposed through a cursor interface. For documents where you need
/// per-item `Codable` decoding, use ``XMLItemDecoder`` which builds on top of this type.
///
/// - SeeAlso: ``XMLStreamParser``, ``XMLItemDecoder``, ``XMLStreamEvent``
public final class XMLEventCursor: @unchecked Sendable {

    // MARK: - Stored properties

    private let _events: [XMLStreamEvent]
    private var _index: Int

    // MARK: - Initialiser

    /// Creates a cursor by fully parsing `data` with the given configuration.
    ///
    /// Parsing is synchronous. If parsing succeeds, all events are available for
    /// pull-style consumption immediately.
    ///
    /// - Parameters:
    ///   - data: Raw UTF-8 encoded XML bytes.
    ///   - configuration: Parser options. Defaults to ``XMLTreeParser/Configuration/init()``.
    /// - Throws: ``XMLParsingError`` on parse failure or security-limit violation.
    public init(
        data: Data,
        configuration: XMLTreeParser.Configuration = XMLTreeParser.Configuration()
    ) throws {
        var buffer: [XMLStreamEvent] = []
        try XMLStreamParser(configuration: configuration).parse(data: data) { buffer.append($0) }
        self._events = buffer
        self._index = 0
    }

    // MARK: - Cursor state

    /// The total number of events in this cursor.
    public var count: Int { _events.count }

    /// Whether the cursor has been fully consumed.
    public var isAtEnd: Bool { _index >= _events.count }

    /// The current position of the cursor (0-based index into the event sequence).
    public var position: Int { _index }

    // MARK: - Navigation

    /// Returns the next event and advances the cursor, or `nil` if exhausted.
    ///
    /// This is the primary navigation method. Call it in a `while` loop to process
    /// all events:
    ///
    /// ```swift
    /// while let event = cursor.next() { ... }
    /// ```
    public func next() -> XMLStreamEvent? {
        guard _index < _events.count else { return nil }
        defer { _index += 1 }
        return _events[_index]
    }

    /// Returns the next event **without** advancing the cursor, or `nil` if exhausted.
    ///
    /// Repeated calls to `peek()` return the same event. Call ``next()`` to consume it.
    public func peek() -> XMLStreamEvent? {
        guard _index < _events.count else { return nil }
        return _events[_index]
    }

    /// Skips events until a ``XMLStreamEvent/startElement(name:attributes:namespaceDeclarations:)``
    /// whose local name equals `localName` is found, consuming that event.
    ///
    /// All events before the match are discarded. If no matching start element is found,
    /// the cursor is advanced to the end and `nil` is returned.
    ///
    /// ```swift
    /// if let event = cursor.advance(toElement: "Product") {
    ///     // cursor is now positioned after the <Product> start tag
    /// }
    /// ```
    ///
    /// - Parameter localName: The element local name to search for.
    /// - Returns: The matching ``XMLStreamEvent/startElement(name:attributes:namespaceDeclarations:)`` event, or `nil`.
    @discardableResult
    public func advance(toElement localName: String) -> XMLStreamEvent? {
        while let event = next() {
            if case .startElement(let name, _, _) = event, name.localName == localName {
                return event
            }
        }
        return nil
    }
}

// MARK: - IteratorProtocol

/// `XMLEventCursor` conforms to `IteratorProtocol` via its ``next()`` method,
/// enabling use with `AnyIterator` and iterator-based combinators.
extension XMLEventCursor: IteratorProtocol {}
