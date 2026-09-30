import Foundation

/// Transcribes a recording in pieces *while it is still being recorded*.
///
/// Call ``submit(chunkURL:)`` each time a chunk of audio is finished; it starts
/// uploading immediately. When the recording stops, submit the final chunk and
/// call ``finish()``, which only has to wait for whatever is still in flight
/// (usually just the last few seconds of audio) rather than the whole recording.
///
/// If any chunk fails after its retries, ``finish()`` returns `nil` so the
/// caller can fall back to transcribing the complete recording file.
public final class ChunkedTranscriptionSession: @unchecked Sendable {

    private let service: TranscriptionService
    private let model: TranscriptionModel
    private let apiKey: String

    private let lock = NSLock()
    private var tasks: [Task<String, Error>] = []
    private var isCancelled = false

    public init(service: TranscriptionService, model: TranscriptionModel, apiKey: String) {
        self.service = service
        self.model = model
        self.apiKey = apiKey
    }

    /// Number of chunks submitted so far.
    public var chunkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tasks.count
    }

    /// Start transcribing a finished chunk right away. The session owns the
    /// file from here on and deletes it once the upload has completed.
    public func submit(chunkURL: URL) {
        lock.lock()
        defer { lock.unlock() }

        guard !isCancelled else {
            try? FileManager.default.removeItem(at: chunkURL)
            return
        }

        let service = self.service
        let model = self.model
        let apiKey = self.apiKey
        tasks.append(Task<String, Error> {
            defer { try? FileManager.default.removeItem(at: chunkURL) }
            return try await service.transcribeWithRetry(audioURL: chunkURL, model: model, apiKey: apiKey)
        })
    }

    /// Wait for every submitted chunk and join the results in recording order.
    /// Returns `nil` if any chunk failed, so the caller can fall back.
    public func finish() async -> String? {
        lock.lock()
        let pending = tasks
        lock.unlock()

        var parts: [String] = []
        for task in pending {
            do {
                parts.append(try await task.value)
            } catch {
                cancel()
                return nil
            }
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Abandon the session (recording cancelled, or falling back to the full file).
    public func cancel() {
        lock.lock()
        isCancelled = true
        let pending = tasks
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
