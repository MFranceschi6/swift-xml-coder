import Foundation

// MARK: - encodeEach overloads (II.7)

@available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
extension XMLStreamEncoder {

    // MARK: - Core overload (custom encodeItem)

    /// Encodes each element of an `AsyncSequence` into a stream of ``XMLStreamEvent`` values.
    ///
    /// Events are emitted as items arrive — without materialising the full sequence.
    /// The `preamble` events are yielded first, then the encoded events for each item,
    /// then the `postamble` events.
    ///
    /// - Parameters:
    ///   - items: An `AsyncSequence` of encodable items. Must be `Sendable`.
    ///   - preamble: Events yielded before the first item. Defaults to `[]`.
    ///   - postamble: Events yielded after the last item. Defaults to `[]`.
    ///   - encodeItem: A `@Sendable` closure that converts one item into its events.
    /// - Returns: A stream of ``XMLStreamEvent`` values in document order.
    public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
        _ items: S,
        preamble: [XMLStreamEvent] = [],
        postamble: [XMLStreamEvent] = [],
        encodeItem: @Sendable @escaping (T) throws -> [XMLStreamEvent]
    ) -> AsyncThrowingStream<XMLStreamEvent, Error> where S.Element == T {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for event in preamble { continuation.yield(event) }
                    for try await item in items {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        for event in try encodeItem(item) { continuation.yield(event) }
                    }
                    for event in postamble { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Default encodeItem overload

    /// Encodes each element of an `AsyncSequence` using this encoder's configuration.
    ///
    /// Equivalent to calling ``encodeEach(_:preamble:postamble:encodeItem:)`` with
    /// a default `encodeItem` that wraps `XMLStreamEncoder(configuration:).encode(_:)`.
    ///
    /// - Parameters:
    ///   - items: An `AsyncSequence` of encodable items. Must be `Sendable`.
    ///   - preamble: Events yielded before the first item. Defaults to `[]`.
    ///   - postamble: Events yielded after the last item. Defaults to `[]`.
    /// - Returns: A stream of ``XMLStreamEvent`` values in document order.
    public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
        _ items: S,
        preamble: [XMLStreamEvent] = [],
        postamble: [XMLStreamEvent] = []
    ) -> AsyncThrowingStream<XMLStreamEvent, Error> where S.Element == T {
        let configuration = self.configuration
        return encodeEach(items, preamble: preamble, postamble: postamble) { item in
            // Strip startDocument/endDocument so item events are embeddable inside a
            // larger stream (e.g. inside a wrappedIn wrapper element).
            try XMLStreamEncoder(configuration: configuration).encode(item).filter { event in
                if case .startDocument = event { return false }
                if case .endDocument   = event { return false }
                return true
            }
        }
    }

    // MARK: - wrappedIn convenience

    /// Encodes each element of an `AsyncSequence` wrapped in a named XML element.
    ///
    /// Automatically generates preamble and postamble events for the wrapper element.
    /// When `includeDocument` is `true` (the default), a ``XMLStreamEvent/startDocument``
    /// and ``XMLStreamEvent/endDocument`` pair is also emitted.
    ///
    /// ```swift
    /// // Full XML document wrapping all rows
    /// let stream = encoder.encodeEach(dbCursor, wrappedIn: "Items")
    /// let data = try await XMLStreamWriter().write(stream)
    /// ```
    ///
    /// - Parameters:
    ///   - items: An `AsyncSequence` of encodable items. Must be `Sendable`.
    ///   - elementName: The local name of the wrapper element.
    ///   - attributes: Attributes on the wrapper element. Defaults to `[]`.
    ///   - namespaceDeclarations: Namespace declarations on the wrapper element. Defaults to `[]`.
    ///   - includeDocument: When `true`, wraps the output in `startDocument`/`endDocument`. Defaults to `true`.
    /// - Returns: A stream of ``XMLStreamEvent`` values in document order.
    public func encodeEach<T: Encodable, S: AsyncSequence & Sendable>(
        _ items: S,
        wrappedIn elementName: String,
        attributes: [XMLTreeAttribute] = [],
        namespaceDeclarations: [XMLNamespaceDeclaration] = [],
        includeDocument: Bool = true
    ) -> AsyncThrowingStream<XMLStreamEvent, Error> where S.Element == T {
        let wrapperName = XMLQualifiedName(localName: elementName)
        let encoding = configuration.writerConfiguration.encoding

        var preamble: [XMLStreamEvent] = []
        if includeDocument {
            preamble.append(.startDocument(version: "1.0", encoding: encoding, standalone: nil))
        }
        preamble.append(.startElement(
            name: wrapperName,
            attributes: attributes,
            namespaceDeclarations: namespaceDeclarations
        ))

        var postamble: [XMLStreamEvent] = [.endElement(name: wrapperName)]
        if includeDocument {
            postamble.append(.endDocument)
        }

        return encodeEach(items, preamble: preamble, postamble: postamble)
    }
}
