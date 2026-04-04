import Foundation

/// Event-level transformation hook applied in streaming canonicalization pipelines.
public protocol XMLEventTransform: Sendable {
    /// Processes one input event and returns zero or more output events.
    mutating func process(_ event: XMLStreamEvent) throws -> [XMLStreamEvent]

    /// Flushes any buffered state at the end of the stream.
    mutating func finalize() throws -> [XMLStreamEvent]
}

#if swift(>=6.0)
public typealias XMLEventTransformPipeline = [any XMLEventTransform]
#else
public typealias XMLEventTransformPipeline = [XMLEventTransform]
#endif
