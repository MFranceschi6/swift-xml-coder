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
/// Pass raw XML `Data` and the name of the repeating element to decode each item
/// as the streaming parser encounters it:
///
/// ```swift
/// let decoder  = XMLItemDecoder()
/// let products = try decoder.decode(Product.self, itemElement: "Product", from: catalogData)
/// ```
///
/// For asynchronous, backpressure-aware consumption (macOS 12+):
///
/// ```swift
/// let decoder = XMLItemDecoder()
/// for try await product in decoder.items(Product.self, itemElement: "Product", from: catalogData) {
///     await process(product)   // next item is not decoded until this returns
/// }
/// ```
///
/// ## Memory model
///
/// `XMLItemDecoder` uses a chunk-based SAX parser that feeds libxml2 in 32 KB
/// increments. Each item is decoded inline as its events arrive from the parser
/// session. Peak memory is proportional to the largest single item, not the full
/// document. Previously decoded items are released immediately.
///
/// ## Item extraction
///
/// `XMLItemDecoder` scans children of the root element for each occurrence of
/// `itemElement`. When found, it creates a streaming decoder that reads the item's
/// events directly from the parser session, correctly handling nested elements with
/// the same name. Non-matching sibling elements are skipped efficiently.
///
/// - SeeAlso: ``XMLDecoder``, ``XMLStreamParser``
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
    /// Decodes all occurrences of `itemElement` from raw XML data using a streaming
    /// session, returning them as an array.
    ///
    /// This method does **not** pre-parse the entire document into an event array.
    /// Instead it uses a chunk-based SAX parser session that feeds libxml2 in 32 KB
    /// increments and decodes each item inline as its events arrive. Peak memory is
    /// proportional to the largest single item, not the full document.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode each item as.
    ///   - itemElement: The XML element local name that wraps each item.
    ///   - data: Raw UTF-8 encoded XML bytes.
    ///   - parserConfiguration: Parser options. Defaults to ``XMLTreeParser/Configuration/init()``.
    /// - Returns: An array of decoded values, in document order.
    /// - Throws: ``XMLParsingError`` if parsing or decoding fails.
    public func decode<T: Decodable>(
        _ type: T.Type,
        itemElement: String,
        from data: Data,
        parserConfiguration: XMLTreeParser.Configuration = XMLTreeParser.Configuration()
    ) throws(XMLParsingError) -> [T] {
        do {
            return try decodeItemsStreaming(type, itemElement: itemElement, data: data, parserConfiguration: parserConfiguration)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLItemDecoder streaming error.")
        }
    }
    #else
    /// Decodes all occurrences of `itemElement` from raw XML data using a streaming
    /// session, returning them as an array.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode each item as.
    ///   - itemElement: The XML element local name that wraps each item.
    ///   - data: Raw UTF-8 encoded XML bytes.
    ///   - parserConfiguration: Parser options. Defaults to ``XMLTreeParser/Configuration/init()``.
    /// - Returns: An array of decoded values, in document order.
    /// - Throws: ``XMLParsingError`` if parsing or decoding fails.
    public func decode<T: Decodable>(
        _ type: T.Type,
        itemElement: String,
        from data: Data,
        parserConfiguration: XMLTreeParser.Configuration = XMLTreeParser.Configuration()
    ) throws -> [T] {
        try decodeItemsStreaming(type, itemElement: itemElement, data: data, parserConfiguration: parserConfiguration)
    }
    #endif

    // MARK: - Async API

    /// Returns an `AsyncThrowingStream` that decodes and yields each occurrence of
    /// `itemElement` from raw XML data using a streaming session.
    ///
    /// Unlike tree-based decoding, this method does **not** pre-parse the entire
    /// document. Peak memory is proportional to the largest single item.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to decode each item as.
    ///   - itemElement: The XML element local name that wraps each item.
    ///   - data: Raw UTF-8 encoded XML bytes.
    ///   - parserConfiguration: Parser options. Defaults to ``XMLTreeParser/Configuration/init()``.
    /// - Returns: An async stream of decoded values in document order.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func items<T: Decodable & Sendable>(
        _ type: T.Type,
        itemElement: String,
        from data: Data,
        parserConfiguration: XMLTreeParser.Configuration = XMLTreeParser.Configuration()
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            do {
                let session = try _XMLStreamingParserSession(data: data, configuration: parserConfiguration)
                try Self.forEachItemStreaming(
                    type,
                    itemElement: itemElement,
                    session: session,
                    configuration: self.configuration
                ) { item in
                    guard !Task.isCancelled else {
                        continuation.finish()
                        return false
                    }
                    continuation.yield(item)
                    return true
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Streaming implementation

    private func decodeItemsStreaming<T: Decodable>(
        _ type: T.Type,
        itemElement: String,
        data: Data,
        parserConfiguration: XMLTreeParser.Configuration
    ) throws -> [T] {
        let session = try _XMLStreamingParserSession(data: data, configuration: parserConfiguration)
        var results: [T] = []
        try Self.forEachItemStreaming(
            type,
            itemElement: itemElement,
            session: session,
            configuration: configuration
        ) { item in
            results.append(item)
            return true
        }
        return results
    }

    /// Core streaming loop: advances a session past the root element, finds each
    /// `<itemElement>`, decodes it via `_XMLStreamingDecoder`, and calls `body`.
    /// Returns when the root's `endElement` or EOF is reached.
    /// `body` returns `false` to stop iteration early (e.g. task cancellation).
    private static func forEachItemStreaming<T: Decodable>(
        _ type: T.Type,
        itemElement: String,
        session: _XMLStreamingParserSession,
        configuration: XMLDecoder.Configuration,
        body: (T) throws -> Bool
    ) throws {
        // Advance past startDocument / whitespace to the root startElement.
        while let event = try session.nextEvent() {
            if case .startElement = event {
                break
            }
        }

        var options = _XMLDecoderOptions(configuration: configuration)
        options.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let fieldNodeKinds = _xmlFieldNodeKinds(for: T.self)
        let fieldNamespaces = _xmlFieldNamespaces(for: T.self)

        // Scan children of the root element for matching item elements.
        var rootDepth = 1
        while let event = try session.nextEvent() {
            switch event {
            case .startElement(let name, _, _):
                if rootDepth == 1 && name.localName == itemElement {
                    // Decode this item inline from the session.
                    let state = try _XMLStreamingElementState(session: session, start: event)
                    let decoder = _XMLStreamingDecoder(
                        options: options,
                        state: state,
                        fieldNodeKinds: fieldNodeKinds,
                        fieldNamespaces: fieldNamespaces,
                        codingPath: []
                    )

                    let item: T
                    if let scalar: T = try decoder.decodeScalarFromCurrentElement(type, codingPath: []) {
                        item = scalar
                    } else {
                        item = try T(from: decoder)
                        try decoder.finish()
                    }

                    let shouldContinue = try body(item)
                    if !shouldContinue { return }
                } else {
                    // Non-matching startElement: skip entire subtree.
                    rootDepth += 1
                    var skipDepth = 1
                    while skipDepth > 0 {
                        guard let inner = try session.nextEvent() else { break }
                        switch inner {
                        case .startElement: skipDepth += 1
                        case .endElement: skipDepth -= 1
                        default: break
                        }
                    }
                    rootDepth -= 1
                }
            case .endElement:
                rootDepth -= 1
                if rootDepth == 0 { return }
            default:
                break
            }
        }
    }
}
