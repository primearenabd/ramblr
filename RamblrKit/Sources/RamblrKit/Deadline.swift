import Foundation

/// Runs async work but stops waiting for it after a time limit.
///
/// Unlike a task group, this really returns at the deadline even if the work
/// ignores cancellation (awaiting `Task.value` cannot be interrupted), which is
/// what we need to guarantee that optional polish never delays the transcript.
enum Deadline {

    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?

        init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }

        /// Resumes the waiter once; returns true if this call was the one that won.
        @discardableResult
        func resume(_ value: T?) -> Bool {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            guard let c else { return false }
            c.resume(returning: value)
            return true
        }
    }

    /// Returns the operation's result, or `nil` if it wasn't ready within `seconds`.
    /// On a timeout the operation's task is cancelled (best effort).
    static func run<T: Sendable>(
        seconds: TimeInterval,
        _ operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = Gate<T>(continuation)
            let work = Task { await operation() }
            Task { gate.resume(await work.value) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if gate.resume(nil) { work.cancel() }
            }
        }
    }
}
