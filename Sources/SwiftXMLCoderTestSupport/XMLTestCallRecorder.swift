import Foundation

public final class XMLTestCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    public init() {}

    public func record(_ value: String) {
        lock.lock()
        calls.append(value)
        lock.unlock()
    }

    public func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}
