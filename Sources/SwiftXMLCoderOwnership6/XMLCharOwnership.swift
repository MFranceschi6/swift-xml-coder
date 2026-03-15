import XMLCoderCompatibility
import SwiftXMLCoderCShim

public struct OwnedXMLCharPointer: ~Copyable {
    private let pointer: UnsafeMutablePointer<xmlChar>?

    public init(_ pointer: UnsafeMutablePointer<xmlChar>?) {
        self.pointer = pointer
    }

    public borrowing func withBorrowedPointer<Result>(
        _ body: (UnsafeMutablePointer<xmlChar>) throws -> Result
    ) rethrows -> Result? {
        guard let pointer else {
            return nil
        }

        return try body(pointer)
    }

    public consuming func withConsumedPointer<Result>(
        _ body: (UnsafeMutablePointer<xmlChar>) throws -> Result
    ) rethrows -> Result? {
        try withBorrowedPointer(body)
    }

    deinit {
        if let pointer {
            swiftxmlcoder_xml_free_xml_char(pointer)
        }
    }
}

public func withOwnedXMLCharPointer<Result>(
    _ pointer: UnsafeMutablePointer<xmlChar>?,
    _ body: (UnsafeMutablePointer<xmlChar>) throws -> Result
) rethrows -> Result? {
    let ownedPointer = OwnedXMLCharPointer(pointer)
    return try ownedPointer.withConsumedPointer(body)
}

public struct OwnedXPathContextPointer: ~Copyable {
    private let pointer: xmlXPathContextPtr?

    public init(documentPointer: xmlDocPtr) {
        self.pointer = xmlXPathNewContext(documentPointer)
    }

    public borrowing func withBorrowedPointer<Result>(
        _ body: (xmlXPathContextPtr) throws -> Result
    ) rethrows -> Result? {
        guard let pointer else {
            return nil
        }

        return try body(pointer)
    }

    public consuming func withConsumedPointer<Result>(
        _ body: (xmlXPathContextPtr) throws -> Result
    ) rethrows -> Result? {
        try withBorrowedPointer(body)
    }

    deinit {
        if let pointer {
            xmlXPathFreeContext(pointer)
        }
    }
}

public func withOwnedXPathContextPointer<Result>(
    documentPointer: xmlDocPtr,
    _ body: (xmlXPathContextPtr) throws -> Result
) rethrows -> Result? {
    let ownedPointer = OwnedXPathContextPointer(documentPointer: documentPointer)
    return try ownedPointer.withConsumedPointer(body)
}

public struct OwnedXPathObjectPointer: ~Copyable {
    private let pointer: xmlXPathObjectPtr?

    public init(_ pointer: xmlXPathObjectPtr?) {
        self.pointer = pointer
    }

    public borrowing func withBorrowedPointer<Result>(
        _ body: (xmlXPathObjectPtr) throws -> Result
    ) rethrows -> Result? {
        guard let pointer else {
            return nil
        }

        return try body(pointer)
    }

    public consuming func withConsumedPointer<Result>(
        _ body: (xmlXPathObjectPtr) throws -> Result
    ) rethrows -> Result? {
        try withBorrowedPointer(body)
    }

    deinit {
        if let pointer {
            xmlXPathFreeObject(pointer)
        }
    }
}

public func withOwnedXPathObjectPointer<Result>(
    _ pointer: xmlXPathObjectPtr?,
    _ body: (xmlXPathObjectPtr) throws -> Result
) rethrows -> Result? {
    let ownedPointer = OwnedXPathObjectPointer(pointer)
    return try ownedPointer.withConsumedPointer(body)
}
