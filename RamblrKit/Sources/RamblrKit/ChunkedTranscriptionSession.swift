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
    private let cleanupBudget: TimeInterval

    private let lock = NSLock()
    /// One entry per submitted chunk: the Whisper text, and (if cleanup is on) the cleaned text.
    private struct Chunk {
        let raw: Task<String, Error>
        let cleaned: Task<String, Never>?
    }
    private var chunks: [Chunk] = []
    private var isCancelled = false

    /// - Parameters:
    ///   - cleaner: If set, each chunk's text is tidied as soon as it is transcribed.
    ///   - vocabulary: Terms passed to Whisper (as a hint) and to the cleaner.
    ///   - cleanupBudget: After the recording stops, the most time (seconds) to wait
    ///     for cleanup still in progress. Past that, quick local tidying is used instead.
    public init(
        service: TranscriptionService,
        model: TranscriptionModel,
        apiKey: String,
        cleaner: TranscriptCleaner? = nil,
        vocabulary: [String] = [],
        cleanupBudget: TimeInterval = 0.35
    ) {
        self.service = service
        self.model = model
        self.apiKey = apiKey
        self.cleaner = cleaner
        self.vocabulary = vocabulary
        self.whisperPrompt = vocabulary.isEmpty ? nil : vocabulary.joined(separator: ", ")
        self.cleanupBudget = cleanupBudget
    }

    /// Whether the text returned by ``finish()`` has already been cleaned.
    public var appliesCleanup: Bool { cleaner != nil }

    /// Number of chunks submitted so far.
    public var chunkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return chunks.count
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
        let previousCleaned = chunks.last?.cleaned

        let raw = Task<String, Error> {
            defer { try? FileManager.default.removeItem(at: chunkURL) }
            return try await service.transcribeWithRetry(
                audioURL: chunkURL, model: model, apiKey: apiKey, prompt: prompt
            )
        }
        var cleaned: Task<String, Never>?
        if let cleaner {
            cleaned = Task<String, Never> {
                guard let text = try? await raw.value else { return "" }
                // Give the cleaner the end of the previous (already cleaned) chunk for context.
                let previousText = await previousCleaned?.value
                return await cleaner.clean(
                    text,
                    precedingText: previousText.map { String($0.suffix(300)) },
                    vocabulary: vocabulary
                )
            }
        }
        chunks.append(Chunk(raw: raw, cleaned: cleaned))
    }

    /// Wait for every submitted chunk and join the results in recording order.
    /// Returns `nil` if any chunk failed, so the caller can fall back.
    ///
    /// Transcription must finish, but cleanup is optional: it gets at most
    /// `cleanupBudget` seconds in total, and anything not ready is replaced by a
    /// quick local tidy, so cleanup never noticeably delays the result.
    public func finish() async -> String? {
        lock.lock()
        let pending = chunks
        lock.unlock()

        var rawParts: [String] = []
        for chunk in pending {
            do {
                rawParts.append(try await chunk.raw.value)
            } catch {
                cancel()
                return nil
            }
        }

        let deadline = Date().addingTimeInterval(cleanupBudget)
        var parts: [String] = []
        for (chunk, raw) in zip(pending, rawParts) {
            guard let cleaned = chunk.cleaned else {
                parts.append(raw)
                continue
            }
            // Small floor so chunks that finished long ago are never lost to a zero-length timer.
            let remaining = max(0.02, deadline.timeIntervalSinceNow)
            if let text = await Deadline.run(seconds: remaining, { await cleaned.value }), !text.isEmpty {
                parts.append(text)
            } else {
                parts.append(LocalTextTidy.tidy(raw))
            }
        }
        cancel() // stop any cleanup still running for chunks we gave up on

        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Abandon the session (recording cancelled, or falling back to the full file).
    public func cancel() {
        lock.lock()
        isCancelled = true
        let pending = chunks
        lock.unlock()
        for chunk in pending {
            chunk.raw.cancel()
            chunk.cleaned?.cancel()
        }
    }
}
