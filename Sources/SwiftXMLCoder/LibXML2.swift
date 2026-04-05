import Foundation
import XMLCoderCompatibility
import SwiftXMLCoderCShim
#if swift(>=6.0)
import SwiftXMLCoderOwnership6
#endif

enum LibXML2 {
    static let initializeOnce: Void = {
        xmlInitParser()
        // Pre-warm the encoding handler table for UTF-8. libxml2's
        // xmlGetCharEncodingHandler lazily initialises a global handler
        // table that is not thread-safe. Resolving it here (under the
        // dispatch_once guarantee of `static let`) prevents a SEGV when
        // multiple threads call xmlTextWriterStartDocument concurrently.
        swiftxmlcoder_warm_encoding_handler("UTF-8")
    }()

    static func ensureInitialized() {
        _ = initializeOnce
    }

    static func withXMLCharPointer<Result>(
        _ string: String,
        _ body: (UnsafePointer<xmlChar>?) throws -> Result
    ) rethrows -> Result {
        var bytes = Array(string.utf8)
        bytes.append(0)
        return try bytes.withUnsafeBufferPointer { buffer in
            try body(buffer.baseAddress)
        }
    }

    static func withOwnedXMLCharPointer<Result>(
        _ pointer: UnsafeMutablePointer<xmlChar>?,
        _ body: (UnsafeMutablePointer<xmlChar>) throws -> Result
    ) rethrows -> Result? {
        #if swift(>=6.0)
        return try SwiftXMLCoderOwnership6.withOwnedXMLCharPointer(pointer, body)
        #else
        guard let pointer = pointer else {
            return nil
        }

        defer {
            swiftxmlcoder_xml_free_xml_char(pointer)
        }
        return try body(pointer)
        #endif
    }
}
