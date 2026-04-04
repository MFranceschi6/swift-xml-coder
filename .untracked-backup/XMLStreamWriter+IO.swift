import Foundation
import CLibXML2

// MARK: - Real IO overloads for XMLStreamWriter

extension XMLStreamWriter {

    // MARK: - OutputStream (sync)

    #if swift(>=6.0)
    /// Serialises a sequence of ``XMLStreamEvent`` values directly to an `OutputStream`.
    ///
    /// Uses delta tracking: after each event the buffer is flushed and only the bytes
    /// added since the last flush are written to `stream`. This avoids accumulating the
    /// full document in memory before writing.
    ///
    /// The stream is opened if not already open and is closed on return (success or error).
    ///
    /// - Parameters:
    ///   - events: Any `Sequence` whose element is ``XMLStreamEvent``.
    ///   - stream: The destination `OutputStream`.
    /// - Throws: ``XMLParsingError`` on serialisation failure, limit violation, or stream write error.
    public func write<S: Sequence>(
        _ events: S,
        to stream: OutputStream
    ) throws(XMLParsingError) where S.Element == XMLStreamEvent {
        do {
            try writeToStream(events, stream: stream)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLStreamWriter IO error.")
        }
    }
    #else
    /// Serialises a sequence of ``XMLStreamEvent`` values directly to an `OutputStream`.
    ///
    /// - Parameters:
    ///   - events: Any `Sequence` whose element is ``XMLStreamEvent``.
    ///   - stream: The destination `OutputStream`.
    /// - Throws: ``XMLParsingError`` on serialisation failure, limit violation, or stream write error.
    public func write<S: Sequence>(
        _ events: S,
        to stream: OutputStream
    ) throws where S.Element == XMLStreamEvent {
        try writeToStream(events, stream: stream)
    }
    #endif

    // MARK: - Chunked async (AsyncSequence → AsyncThrowingStream<Data>)

    /// Serialises an async sequence of ``XMLStreamEvent`` values, yielding one `Data`
    /// chunk per event.
    ///
    /// Each chunk contains only the bytes produced by that event (delta tracking). Chunks
    /// may be empty if an event produces no output (e.g. an attribute-only element whose
    /// start tag has not been closed yet). The stream terminates after all events are
    /// consumed or on the first error.
    ///
    /// This API is designed for HTTP streaming frameworks: pipe the chunks directly to
    /// the response body without buffering the entire document.
    ///
    /// ```swift
    /// let chunks = XMLStreamWriter().writeChunked(XMLStreamEncoder().encodeAsync(value))
    /// for try await chunk in chunks {
    ///     try await response.body.write(chunk)
    /// }
    /// ```
    ///
    /// - Parameter events: Any `AsyncSequence & Sendable` whose element is ``XMLStreamEvent``.
    /// - Returns: A stream of `Data` chunks, one per event.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func writeChunked<S: AsyncSequence & Sendable>(
        _ events: S
    ) -> AsyncThrowingStream<Data, Error> where S.Element == XMLStreamEvent {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await writeChunkedImpl(events, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private implementation

    private func writeToStream<S: Sequence>(_ events: S, stream: OutputStream) throws
    where S.Element == XMLStreamEvent {
        LibXML2.ensureInitialized()

        let buf = xmlBufferCreate()
        guard let buf else {
            throw XMLParsingError.documentCreationFailed(message: "xmlBufferCreate failed.")
        }
        defer { xmlBufferFree(buf) }

        let writer = xmlNewTextWriterMemory(buf, 0)
        guard let writer else {
            throw XMLParsingError.documentCreationFailed(message: "xmlNewTextWriterMemory failed.")
        }
        defer { xmlFreeTextWriter(writer) }

        if configuration.prettyPrinted {
            xmlTextWriterSetIndent(writer, 1)
            _ = "  ".withXMLChar { xmlTextWriterSetIndentString(writer, $0) }
        }

        if stream.streamStatus == .notOpen { stream.open() }
        defer { stream.close() }

        var state = WriteState()
        var checkpoint = 0

        for event in events {
            try writeEvent(event, writer: writer, state: &state)
            xmlTextWriterFlush(writer)

            let length = Int(xmlBufferLength(buf))
            if length > checkpoint, let contentPtr = xmlBufferContent(buf) {
                let newBytes = length - checkpoint
                if let maxBytes = configuration.limits.maxOutputBytes,
                   length > maxBytes {
                    throw XMLParsingError.parseFailed(
                        message: "[XML6_2H_MAX_OUTPUT_BYTES] Output size \(length) bytes"
                            + " exceeds limit \(maxBytes) bytes."
                    )
                }
                let written = (contentPtr + checkpoint).withMemoryRebound(to: UInt8.self, capacity: newBytes) { ptr in
                    stream.write(ptr, maxLength: newBytes)
                }
                if written < 0 {
                    let detail = stream.streamError?.localizedDescription ?? "unknown"
                    throw XMLParsingError.parseFailed(
                        message: "[STREAM_IO_003] OutputStream write error: \(detail)."
                    )
                }
                checkpoint = length
            }
        }
    }

    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    private func writeChunkedImpl<S: AsyncSequence>(
        _ events: S,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) async throws where S.Element == XMLStreamEvent {
        LibXML2.ensureInitialized()

        let buf = xmlBufferCreate()
        guard let buf else {
            throw XMLParsingError.documentCreationFailed(message: "xmlBufferCreate failed.")
        }
        defer { xmlBufferFree(buf) }

        let writer = xmlNewTextWriterMemory(buf, 0)
        guard let writer else {
            throw XMLParsingError.documentCreationFailed(message: "xmlNewTextWriterMemory failed.")
        }
        defer { xmlFreeTextWriter(writer) }

        if configuration.prettyPrinted {
            xmlTextWriterSetIndent(writer, 1)
            _ = "  ".withXMLChar { xmlTextWriterSetIndentString(writer, $0) }
        }

        var state = WriteState()
        var checkpoint = 0

        for try await event in events {
            try writeEvent(event, writer: writer, state: &state)
            xmlTextWriterFlush(writer)

            let length = Int(xmlBufferLength(buf))
            if length > checkpoint, let contentPtr = xmlBufferContent(buf) {
                let newBytes = length - checkpoint
                if let maxBytes = configuration.limits.maxOutputBytes,
                   length > maxBytes {
                    throw XMLParsingError.parseFailed(
                        message: "[XML6_2H_MAX_OUTPUT_BYTES] Output size \(length) bytes"
                            + " exceeds limit \(maxBytes) bytes."
                    )
                }
                let chunk = Data(bytes: UnsafeRawPointer(contentPtr + checkpoint), count: newBytes)
                continuation.yield(chunk)
                checkpoint = length
            }
        }
    }
}
