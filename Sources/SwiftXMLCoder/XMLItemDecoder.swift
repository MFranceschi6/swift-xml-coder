import Foundation

/// Decodes `Decodable` items one at a time from a named repeating element in an XML
/// document, without loading all items into memory simultaneously.
///
/// `XMLItemDecoder` addresses the common pattern of a large XML collection:
///
/// ```xml
/// <Catalog>
///     <Product><sku>ABC</sku><price>9.99</price></Product>
///     <Product><sku>DEF</sku><price>14.99</price></Product>
///     <!-- ... thousands more ... -->
/// </Catalog>
/// ```
///
/// Use it with an ``XMLEventCursor`` to decode each item as the cursor advances:
///
/// ```swift
/// let cursor  = try XMLEventCursor(data: catalogData)
/// let decoder = XMLItemDecoder()
/// let products = try decoder.decode(Product.self, itemElement: "Product", from: cursor)
/// ```
///
/// For asynchronous, backpressure-aware consumption (macOS 12+):
///
/// ```swift
/// let cursor  = try XMLEventCursor(data: catalogData)
/// let decoder = XMLItemDecoder()
/// for try await product in decoder.items(Product.self, itemElement: "Product", from: cursor) {
///     await process(product)   // next item is not decoded until this returns
/// }
/// ```
///
/// ## Memory model
///
/// At any moment only the events for a single item are held in a temporary buffer while
/// they are being serialised and decoded. Previously decoded items are released
/// immediately. The ``XMLEventCursor`` itself holds all events for the full document, so
/// peak memory is proportional to the event count of the full document (not the DOM tree).
///
/// ## Item extraction
///
/// `XMLItemDecoder` uses the cursor to locate each occurrence of `itemElement`,
/// collects all events from its opening tag to the matching closing tag (correctly
/// handling nested elements with the same name), serialises those events as a
/// self-contained XML document fragment, then passes the bytes to ``XMLDecoder``.
///
/// - SeeAlso: ``XMLEventCursor``, ``XMLDecoder``, ``XMLStreamParser``
public struct XMLItemDecoder: Sendable {

    // MARK: - Stored properties

    /// The decoding configuration applied to each item.
    ///
    /// The ``XMLDecoder/Configuration/rootElementName`` in this configuration is
    /// overridden per-call with the `itemElement` parameter; all other settings
    /// (date strategy, field overrides, key transform, etc.) are forwarded as-is.
    public let configuration: XMLDecoder.Configuration

    // MARK: - Initialiser

    /// Creates an item decoder with the given configuration.
    ///
    /// - Parameter configuration: Decoder options applied to each item. Defaults to
    ///   ``XMLDecoder/Configuration/init()``.
    public init(configuration: XMLDecoder.Configuration = XMLDecoder.Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Sync API

    #if swift(>=6.0)
    /// Decodes all occurrences of `itemElement` in the cursor as values of type `T`,
    /// returning them as an array.
    ///
    /// The cursor is advanced past each decoded item. Remaining events after the last
    /// occurrence of `itemElement` are left unconsumed.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode each item as.
    ///   - itemElement: The XML element local name that wraps each item.
    ///   - cursor: A pre-parsed event cursor, typically created with ``XMLEventCursor``.
    /// - Returns: An array of decoded values, in document order.
    /// - Throws: ``XMLParsingError`` if any item cannot be decoded.
    public func decode<T: Decodable>(
        _ type: T.Type,
        itemElement: String,
        from cursor: XMLEventCursor
    ) throws(XMLParsingError) -> [T] {
        do {
            var results: [T] = []
            while let span = cursor.nextItemSpan(itemElement: itemElement) {
                let events = cursor.eventsInRange(span)
                let item = try decodeItemFromSpan(type, itemElement: itemElement, events: events)
                results.append(item)
            }
            return results
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLItemDecoder error.")
        }
    }
    #else
    /// Decodes all occurrences of `itemElement` in the cursor as values of type `T`,
    /// returning them as an array.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode each item as.
    ///   - itemElement: The XML element local name that wraps each item.
    ///   - cursor: A pre-parsed event cursor.
    /// - Returns: An array of decoded values, in document order.
    /// - Throws: ``XMLParsingError`` if any item cannot be decoded.
    public func decode<T: Decodable>(
        _ type: T.Type,
        itemElement: String,
        from cursor: XMLEventCursor
    ) throws -> [T] {
        var results: [T] = []
        while let span = cursor.nextItemSpan(itemElement: itemElement) {
            let events = cursor.eventsInRange(span)
            let item = try decodeItemFromSpan(type, itemElement: itemElement, events: events)
            results.append(item)
        }
        return results
    }
    #endif

    // MARK: - Async API

    /// Returns an `AsyncThrowingStream` that decodes and yields each occurrence of
    /// `itemElement` in the cursor one at a time.
    ///
    /// The next item is only decoded once the consumer has requested it — either by
    /// awaiting the next value from a `for try await` loop or by calling `next()` on
    /// the iterator. This provides natural backpressure: slow consumers do not buffer
    /// ahead of themselves.
    ///
    /// Task cancellation is checked before each yield. If the task is cancelled, the
    /// stream terminates cleanly without throwing.
    ///
    /// ```swift
    /// for try await product in decoder.items(Product.self, itemElement: "Product", from: cursor) {
    ///     await persist(product)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode each item as.
    ///   - itemElement: The XML element local name that wraps each item.
    ///   - cursor: A pre-parsed event cursor.
    /// - Returns: An async stream of decoded values in document order.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func items<T: Decodable & Sendable>(
        _ type: T.Type,
        itemElement: String,
        from cursor: XMLEventCursor
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            do {
                while let span = cursor.nextItemSpan(itemElement: itemElement) {
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return
                    }
                    let events = cursor.eventsInRange(span)
                    let item = try decodeItemFromSpan(type, itemElement: itemElement, events: events)
                    continuation.yield(item)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Internal helpers

    /// Decodes a single item from a contiguous event span via `_XMLSAXDecoder`,
    /// bypassing tree materialisation entirely.
    private func decodeItemFromSpan<T: Decodable>(
        _ type: T.Type,
        itemElement: String,
        events: ContiguousArray<XMLStreamEvent>
    ) throws -> T {
        let buffer = _XMLEventBuffer(events: events, lineTable: nil)
        let spanStart = 0
        let spanEnd = events.count - 1

        var options = _XMLDecoderOptions(configuration: configuration)
        options.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let saxDecoder = _XMLSAXDecoder(
            options: options,
            buffer: buffer,
            start: spanStart,
            end: spanEnd,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self),
            fieldNamespaces: _xmlFieldNamespaces(for: T.self),
            codingPath: []
        )

        if let scalar: T = try saxDecoder.decodeScalarFromSpan(
            type, spanStart: spanStart, spanEnd: spanEnd,
            localName: itemElement, codingPath: []
        ) {
            return scalar
        }
        return try T(from: saxDecoder)
    }
}
