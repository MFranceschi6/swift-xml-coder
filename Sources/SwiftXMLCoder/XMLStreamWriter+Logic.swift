import Foundation
import CLibXML2

// MARK: - XMLStreamWriter internal implementation
//
// writeImpl delegates to XMLStreamWriterSink, accumulating all output chunks into a
// single Data. The per-event libxml2 dispatch lives in XMLStreamWriterSink.

extension XMLStreamWriter {

    // MARK: - WriteState

    struct WriteState {
        var depth: Int = 0
        var nodeCount: Int = 0
        // Stack tracking whether each open element has received content.
        // Used to implement expandEmptyElements.
        var elementHasContent: [Bool] = []
    }

    // MARK: - writeImpl

    func writeImpl<S: Sequence>(_ events: S) throws -> Data where S.Element == XMLStreamEvent {
        var chunks: [Data] = []
        // Use Int.max threshold so the sink never auto-flushes — we drain once at finish().
        let sink = try XMLStreamWriterSink(
            configuration: configuration,
            flushThreshold: Int.max
        ) { chunk in
            chunks.append(chunk)
        }

        for event in events {
            try sink.write(event)
        }
        try sink.finish()

        let totalBytes = chunks.reduce(0) { $0 + $1.count }
        if let maxBytes = configuration.limits.maxOutputBytes, totalBytes > maxBytes {
            throw XMLParsingError.parseFailed(
                message: "[XML6_2H_MAX_OUTPUT_BYTES] Output size \(totalBytes) bytes exceeds limit \(maxBytes) bytes."
            )
        }

        if chunks.count == 1 {
            return chunks[0]
        }
        return chunks.reduce(into: Data()) { $0.append($1) }
    }
}

// MARK: - String → xmlChar* bridging helpers

extension String {
    /// Calls `body` with a temporary `UnsafePointer<xmlChar>` to the UTF-8 bytes.
    /// The pointer is only valid for the duration of `body`.
    func withXMLChar<R>(_ body: (UnsafePointer<xmlChar>) -> R) -> R {
        withCString { cStr in
            body(UnsafePointer<xmlChar>(OpaquePointer(cStr)))
        }
    }
}

extension Optional where Wrapped == String {
    /// Calls `body` with either a valid `UnsafePointer<xmlChar>` or `nil`.
    func withOptionalXMLChar<R>(_ body: (UnsafePointer<xmlChar>?) -> R) -> R {
        if let str = self {
            return str.withXMLChar { body($0) }
        } else {
            return body(nil)
        }
    }
}
