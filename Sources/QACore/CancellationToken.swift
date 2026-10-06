import Foundation

// Why: a live-watch loop needs to be stopped from outside while it's sleeping between polls, not just mid
// shell-call — checking a MainActor-isolated @Published property directly from the background thread the
// loop runs on isn't safe, so this is a plain lock-protected flag that works from either side.
public final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
