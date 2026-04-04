import Foundation
import Logging
import CLibXML2

// MARK: - Real IO overloads for XMLStreamParser

extension XMLStreamParser {

    // MARK: - InputStream (push parser)

    #if swift(>=6.0)
    /// Parses XML from an `InputStream` using libxml2's push parser, calling `onEvent`
    /// for each ``XMLStreamEvent``.
    ///
    /// Unlike ``parse(data:onEvent:)``, this overload does not require the full document
    /// to be in memory at once. It reads the stream in 64 KiB chunks and feeds each to
    /// libxml2's incremental push parser (`xmlParseChunk`), making it suitable for large
    /// files or network streams.
    ///
    /// The stream is opened if not already open and is closed on return (success or error).
    ///
    /// - Parameters:
    ///   - stream: An `InputStream` positioned at the start of an XML document.
    ///   - onEvent: Closure invoked for each event in document order.
    /// - Throws: ``XMLParsingError`` on parse failure, limit violation, or stream read error.
    public func parse(
        stream: InputStream,
        onEvent: (XMLStreamEvent) -> Void
    ) throws(XMLParsingError) {
        do {
            try parsePush(stream: stream, onEvent: onEvent)
        } catch let error as XMLParsingError {
            throw error
        } catch {
            throw XMLParsingError.other(underlyingError: error, message: "Unexpected XMLStreamParser IO error.")
        }
    }
    #else
    /// Parses XML from an `InputStream` using libxml2's push parser, calling `onEvent`
    /// for each ``XMLStreamEvent``.
    ///
    /// - Parameters:
    ///   - stream: An `InputStream` positioned at the start of an XML document.
    ///   - onEvent: Closure invoked for each event in document order.
    /// - Throws: ``XMLParsingError`` on parse failure, limit violation, or stream read error.
    public func parse(
        stream: InputStream,
        onEvent: (XMLStreamEvent) -> Void
    ) throws {
        try parsePush(stream: stream, onEvent: onEvent)
    }
    #endif

    // MARK: - AsyncSequence<UInt8>

    /// Returns an ``AsyncThrowingStream`` that emits ``XMLStreamEvent`` values parsed
    /// from an `AsyncSequence` of raw bytes.
    ///
    /// This overload is designed for framework compatibility: HTTP frameworks (Vapor,
    /// Hummingbird, etc.) expose request bodies as `AsyncSequence<ByteBuffer>` or similar.
    /// Adapting them to `AsyncSequence<UInt8>` allows direct use of this API without any
    /// framework-specific code in this library.
    ///
    /// Bytes are collected into a `Data` buffer before parsing begins. This is an
    /// intentional trade-off: the push-parser event stream still starts before the full
    /// document reaches disk, but `Decodable` requires buffering anyway.
    ///
    /// Task cancellation is checked before each event is yielded.
    ///
    /// - Parameter bytes: Any `AsyncSequence` whose element is `UInt8`.
    /// - Returns: A stream of ``XMLStreamEvent`` values in document order.
    @available(macOS 12, iOS 15, watchOS 8, tvOS 15, *)
    public func events<S: AsyncSequence & Sendable>(
        for bytes: S
    ) -> AsyncThrowingStream<XMLStreamEvent, Error> where S.Element == UInt8 {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var data = Data()
                    for try await byte in bytes {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }
                        data.append(byte)
                    }
                    try parseSAX(data: data) { event in
                        guard !Task.isCancelled else { return }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Push parser implementation

    // swiftlint:disable:next function_body_length
    private func parsePush(stream: InputStream, onEvent: (XMLStreamEvent) -> Void) throws {
        var logger = configuration.logger
        logger[metadataKey: "component"] = "XMLStreamParser"

        // withoutActuallyEscaping is safe: SAXContext + Unmanaged ref are released
        // before this function returns, so onEvent never truly escapes.
        try withoutActuallyEscaping(onEvent) { escapingOnEvent in
            let ctx = SAXContext(
                onEvent: escapingOnEvent,
                limits: configuration.limits,
                whitespacePolicy: configuration.whitespaceTextNodePolicy,
                logger: logger
            )

            let unmanaged = Unmanaged.passRetained(ctx)
            defer { unmanaged.release() }
            let ctxPtr = unmanaged.toOpaque()

            var handler = makeSAXHandler()

            if stream.streamStatus == .notOpen { stream.open() }
            defer { stream.close() }

            guard let pushCtxt = xmlCreatePushParserCtxt(&handler, ctxPtr, nil, 0, nil) else {
                throw XMLParsingError.parseFailed(
                    message: "[STREAM_IO_001] Failed to create libxml2 push parser context."
                )
            }
            defer { xmlFreeParserCtxt(pushCtxt) }

            let chunkSize = 65_536
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { buffer.deallocate() }

            var totalBytesRead = 0

            while true {
                let bytesRead = stream.read(buffer, maxLength: chunkSize)

                if bytesRead < 0 {
                    let detail = stream.streamError?.localizedDescription ?? "unknown"
                    throw XMLParsingError.parseFailed(
                        message: "[STREAM_IO_002] InputStream read error: \(detail)."
                    )
                }

                totalBytesRead += bytesRead
                if let maxBytes = configuration.limits.maxInputBytes, totalBytesRead > maxBytes {
                    throw XMLParsingError.parseFailed(
                        message: "[XML6_2H_MAX_INPUT_BYTES] Input byte limit \(maxBytes) exceeded."
                    )
                }

                let isLast = bytesRead == 0
                let parseResult: Int32
                if isLast {
                    parseResult = xmlParseChunk(pushCtxt, nil, 0, 1)
                } else {
                    parseResult = buffer.withMemoryRebound(to: CChar.self, capacity: chunkSize) { charPtr in
                        xmlParseChunk(pushCtxt, charPtr, Int32(bytesRead), 0)
                    }
                }

                if let error = ctx.error { throw error }
                if parseResult != 0 {
                    let message: String?
                    if let errPtr = xmlGetLastError(), let msgPtr = errPtr.pointee.message {
                        message = String(cString: msgPtr).trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        message = nil
                    }
                    throw XMLParsingError.parseFailed(
                        message: message ?? "libxml2 push parse returned error code \(parseResult)."
                    )
                }

                if isLast { break }
            }
        }
    }
}
