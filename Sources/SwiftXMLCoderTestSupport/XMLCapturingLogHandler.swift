import Foundation
import Logging

// MARK: - XMLLogEntry

/// A single captured log entry.
///
/// `XMLLogEntry` records everything emitted by `XMLCapturingLogHandler`:
/// the log level, message string, metadata dictionary, source label, and
/// source location (file, function, line).
///
/// Use ``XMLCapturingLogHandler/entries`` to retrieve all captured entries
/// after exercising the system under test.
public struct XMLLogEntry: Sendable {
    /// The log level of this entry.
    public let level: Logger.Level
    /// The rendered log message string.
    public let message: String
    /// The structured metadata attached to this log call.
    public let metadata: Logger.Metadata
    /// The logger's label (injected label string, e.g. `"SwiftXMLCoder"`).
    public let label: String
    /// Source file.
    public let file: String
    /// Source function.
    public let function: String
    /// Source line.
    public let line: UInt
}

// MARK: - XMLCapturingLogHandler

/// A `LogHandler` that captures all log entries for assertion in tests.
///
/// Inject an instance into a `Logger` and pass the logger to the system under test.
/// After exercising the component, inspect ``entries`` to verify that the expected
/// log messages were emitted at the correct levels with the correct metadata.
///
/// ```swift
/// let handler = XMLCapturingLogHandler(label: "test")
/// let logger = Logger(label: "test") { _ in handler }
/// let encoder = XMLEncoder(configuration: .init(logger: logger))
/// // … exercise encoder …
/// let warnings = handler.entries(at: .warning)
/// XCTAssertTrue(warnings.contains { $0.message == "XML name sanitized" })
/// ```
///
/// `XMLCapturingLogHandler` is thread-safe: concurrent log emissions from the
/// same logger are serialised through an `NSLock`.
public final class XMLCapturingLogHandler: LogHandler, @unchecked Sendable {

    private let lock = NSLock()
    private var _entries: [XMLLogEntry] = []
    private let _label: String

    // LogHandler requirement
    public var logLevel: Logger.Level = .trace
    public var metadata: Logger.Metadata = [:]

    /// Creates a new capturing handler.
    /// - Parameter label: The logger label (informational only).
    public init(label: String = "XMLCapturingLogHandler") {
        self._label = label
    }

    // MARK: - LogHandler

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let merged = self.metadata.merging(metadata ?? [:]) { _, new in new }
        let entry = XMLLogEntry(
            level: level,
            message: message.description,
            metadata: merged,
            label: _label,
            file: file,
            function: function,
            line: line
        )
        lock.lock()
        _entries.append(entry)
        lock.unlock()
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    // MARK: - Query helpers

    /// All captured entries in emission order.
    public var entries: [XMLLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    /// All entries at the specified level.
    public func entries(at level: Logger.Level) -> [XMLLogEntry] {
        entries.filter { $0.level == level }
    }

    /// All entries whose message contains `substring`.
    public func entries(containing substring: String) -> [XMLLogEntry] {
        entries.filter { $0.message.contains(substring) }
    }

    /// Returns `true` if at least one entry at `level` contains `substring` in its message.
    public func hasEntry(at level: Logger.Level, containing substring: String) -> Bool {
        entries(at: level).contains { $0.message.contains(substring) }
    }

    /// Returns `true` if at least one entry at `level` has the given metadata key present.
    public func hasEntry(at level: Logger.Level, withMetadataKey key: String) -> Bool {
        entries(at: level).contains { $0.metadata[key] != nil }
    }

    /// Removes all captured entries. Useful for test setup.
    public func reset() {
        lock.lock()
        _entries.removeAll()
        lock.unlock()
    }
}
