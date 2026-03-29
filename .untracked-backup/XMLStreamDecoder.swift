import Foundation

/// Decodes a sequence of ``XMLStreamEvent`` values into a `Decodable` value.
///
/// `XMLStreamDecoder` is the Codable bridge for the streaming layer. It consumes events
/// produced by ``XMLStreamParser`` (or ``XMLStreamEncoder``) and decodes them directly
/// using ``XMLStreamEventDecoder`` — a cursor-based `Decoder` that operates on the
/// flat event array without building an intermediate ``XMLTreeDocument``.
///
/// > Note: `Decodable` requires synchronous, random-access key lookup over all fields.
/// > This means the decoder must buffer the full event stream before decoding can begin —
/// > this is a constraint of the Swift `Decodable` protocol, not a design limitation.
/// > The async overload collects all events first, then decodes.
///
/// ## Sync decoding from a collected event array
///
/// ```swift
/// var events: [XMLStreamEvent] = []
/// try XMLStreamParser().parse(data: xmlData) { events.append($0) }
/// let value = try XMLStreamDecoder().decode(MyType.self, from: events)
/// ```
///
/// ## Async decoding from an AsyncSequence (macOS 12+)
///
/// ```swift
/// let value = try await XMLStreamDecoder().decode(
///     MyType.self,
///     from: XMLStreamParser().events(for: xmlData)
/// )
/// ```
///
/// ## Round-trip with XMLStreamEncoder
///
/// ```swift
/// let events  = try XMLStreamEncoder().encode(original)
/// let decoded = try XMLStreamDecoder().decode(MyType.self, from: events)
/// // decoded == original
/// ```
///
/// - SeeAlso: ``XMLStreamEncoder``, ``XMLStreamParser``, ``XMLDecoder``
public struct XMLStreamDecoder: Sendable {

    /// The decoder configuration forwarded to the underlying ``XMLDecoder``.
    public let configuration: XMLDecoder.Configuration

    /// Creates an XML stream decoder with the given configuration.
    ///
    /// - Parameter configuration: Decoder options. Defaults to ``XMLDecoder/Configuration/init()``.
    public init(configuration: XMLDecoder.Configuration = XMLDecoder.Configuration()) {
        self.configuration = configuration
    }

    // MARK: - Sync API

    #if swift(>=6.0)
    /// Decodes a value of `type` from a sequence of ``XMLStreamEvent`` values.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - events: Any `Sequence` whose element is ``XMLStreamEvent``.
    /// - Returns: A decoded value of `type`.
    /// - Throws: ``XMLParsingError`` if the event stream is malformed or decoding fails.
    public func decode<T: Decodable, S: Sequence>(
        _ type: T.Type,
        from events: S
    ) throws(XMLParsingError) -> T where S.Element == XMLStreamEvent {
        do {
            return try decodeImpl(type, from: events)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLStreamDecoder error.")
        }
    }
    #else
    /// Decodes a value of `type` from a sequence of ``XMLStreamEvent`` values.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - events: Any `Sequence` whose element is ``XMLStreamEvent``.
    /// - Returns: A decoded value of `type`.
    /// - Throws: ``XMLParsingError`` if the event stream is malformed or decoding fails.
    public func decode<T: Decodable, S: Sequence>(
        _ type: T.Type,
        from events: S
    ) throws -> T where S.Element == XMLStreamEvent {
        try decodeImpl(type, from: events)
    }
    #endif

    // MARK: - Async API

    /// Decodes a value of `type` by collecting all events from `events` then decoding.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - events: Any `AsyncSequence` whose element is ``XMLStreamEvent``.
    /// - Returns: A decoded value of `type`.
    /// - Throws: ``XMLParsingError`` if the event stream is malformed or decoding fails.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func decode<T: Decodable, S: AsyncSequence>(
        _ type: T.Type,
        from events: S
    ) async throws -> T where S.Element == XMLStreamEvent {
        var collected: [XMLStreamEvent] = []
        for try await event in events {
            collected.append(event)
        }
        return try decodeImpl(type, from: collected)
    }

    // MARK: - Private implementation

    private func decodeImpl<T: Decodable, S: Sequence>(
        _ type: T.Type,
        from events: S
    ) throws -> T where S.Element == XMLStreamEvent {
        let eventArray = Array(events)
        let rootScope = try findRootScope(in: eventArray)

        // Root element name validation — mirrors XMLDecoder.decodeTreeImpl
        if let expectedRoot = try resolveExpectedRootName(for: type),
           case .startElement(let name, _, _) = eventArray[rootScope.start],
           name.localName != expectedRoot {
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_ROOT_MISMATCH] Expected root '\(expectedRoot)' but found '\(name.localName)'."
            )
        }

        var options = _XMLDecoderOptions(configuration: configuration)
        options.perPropertyDateHints = _xmlPropertyDateHints(for: T.self)
        let eventDecoder = XMLStreamEventDecoder(
            events: eventArray,
            scope: rootScope,
            options: options,
            fieldNodeKinds: _xmlFieldNodeKinds(for: T.self)
        )

        // Intercept known scalar types — mirrors XMLDecoder.decodeTreeImpl
        let rootName: String
        if case .startElement(let elemName, _, _) = eventArray[rootScope.start] {
            rootName = elemName.localName
        } else {
            rootName = ""
        }
        if type == String.self {
            let text = _streamExtractText(events: eventArray, scope: rootScope)
            if let result = text as? T { return result }
        } else if eventDecoder.scalarOracle.isKnownScalarType(type) {
            let lexical = _streamExtractText(events: eventArray, scope: rootScope)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !lexical.isEmpty,
               let scalar: T = try eventDecoder.scalarOracle.decodeScalarFromLexical(
                   lexical, as: T.self, codingPath: [], localName: rootName, isAttribute: false
               ) {
                return scalar
            }
            throw XMLParsingError.parseFailed(
                message: "[XML6_5_SCALAR_PARSE_FAILED] Unable to decode scalar at root element '\(rootName)'."
            )
        }

        return try T(from: eventDecoder)
    }

    /// Finds the EventRange of the document's root element by tracking depth.
    private func findRootScope(in events: [XMLStreamEvent]) throws -> EventRange {
        var start = -1
        var depth = 0
        for (idx, event) in events.enumerated() {
            switch event {
            case .startElement:
                if depth == 0 { start = idx }
                depth += 1
            case .endElement:
                depth -= 1
                if depth == 0 {
                    guard start >= 0 else {
                        throw XMLParsingError.parseFailed(
                            message: "[STREAM_DEC_001] endElement with no matching startElement."
                        )
                    }
                    return EventRange(start: start, end: idx)
                }
            default:
                break
            }
        }
        throw XMLParsingError.parseFailed(
            message: "[STREAM_DEC_002] No root element found in event stream."
        )
    }

    /// Replicates `XMLDecoder.resolveExpectedRootElementName` for the stream pipeline.
    private func resolveExpectedRootName<T>(for type: T.Type) throws -> String? {
        let policy = configuration.validationPolicy
        if let explicit = try XMLRootNameResolver.explicitRootElementName(
            from: configuration.rootElementName,
            validationPolicy: policy
        ) {
            return explicit
        }
        return try XMLRootNameResolver.implicitRootElementName(for: type, validationPolicy: policy)
    }
}
