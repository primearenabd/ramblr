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
    private let cleaner: TranscriptCleaner?
    private let vocabulary: [String]
    private let whisperPrompt: String?

    private let lock = NSLock()
    private var tasks: [Task<String, Error>] = []
    private var isCancelled = false

    /// - Parameters:
    ///   - cleaner: If set, each chunk's text is tidied as soon as it is transcribed.
    ///   - vocabulary: Terms passed to Whisper (as a hint) and to the cleaner.
    public init(
        service: TranscriptionService,
        model: TranscriptionModel,
        apiKey: String,
        cleaner: TranscriptCleaner? = nil,
        vocabulary: [String] = []
    ) {
        self.service = service
        self.model = model
        self.apiKey = apiKey
        self.cleaner = cleaner
        self.vocabulary = vocabulary
        self.whisperPrompt = vocabulary.isEmpty ? nil : vocabulary.joined(separator: ", ")
    }

    /// Whether the text returned by ``finish()`` has already been cleaned.
    public var appliesCleanup: Bool { cleaner != nil }

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
        let cleaner = self.cleaner
        let vocabulary = self.vocabulary
        let prompt = self.whisperPrompt
        let previous = tasks.last
        tasks.append(Task<String, Error> {
            defer { try? FileManager.default.removeItem(at: chunkURL) }
            let raw = try await service.transcribeWithRetry(
                audioURL: chunkURL, model: model, apiKey: apiKey, prompt: prompt
            )
            guard let cleaner else { return raw }
            // Give the cleaner the end of the previous (already cleaned) chunk for context.
            let previousText = try? await previous?.value
            return await cleaner.clean(
                raw,
                precedingText: previousText.map { String($0.suffix(300)) },
                vocabulary: vocabulary
            )
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
