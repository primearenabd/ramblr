import Foundation

/// Decides where to cut a live recording into chunks that can be transcribed
/// while the user is still talking.
///
/// Feed it one measurement per audio buffer. It asks for a cut once the current
/// chunk is long enough *and* the speaker has just paused, so chunks end between
/// words instead of in the middle of one. If the speaker never pauses, a hard
/// limit forces a cut anyway.
///
/// This is pure logic (no audio APIs), so it is easy to unit test.
public struct ChunkPlanner: Sendable {

    public struct Configuration: Sendable {
        /// Don't cut before the chunk is at least this long (seconds).
        public var minChunkDuration: TimeInterval = 12
        /// Silence needed to cut once past `minChunkDuration` (seconds).
        public var silenceToCut: TimeInterval = 0.4
        /// After this length, a shorter silence is accepted (seconds).
        public var relaxedChunkDuration: TimeInterval = 20
        /// Silence needed to cut once past `relaxedChunkDuration` (seconds).
        public var relaxedSilenceToCut: TimeInterval = 0.15
        /// Always cut at this length, even mid-speech (seconds).
        public var maxChunkDuration: TimeInterval = 28
        /// RMS level below which a buffer counts as silence.
        public var silenceRMS: Float = 0.006
        /// A chunk whose loudest buffer never reaches this is treated as pure
        /// silence and not transcribed (avoids Whisper hallucinating on silence).
        /// Deliberately equal to `silenceRMS`: only drop chunks where every
        /// buffer was silent, never risk discarding quiet speech.
        public var speechRMS: Float = 0.006

        public init() {}
    }

    /// What was recorded in a finished chunk.
    public struct ChunkSummary: Equatable, Sendable {
        public var duration: TimeInterval
        public var peakRMS: Float

        public init(duration: TimeInterval, peakRMS: Float) {
            self.duration = duration
            self.peakRMS = peakRMS
        }
    }

    public let configuration: Configuration

    private var chunkDuration: TimeInterval = 0
    private var trailingSilence: TimeInterval = 0
    private var peakRMS: Float = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Duration of the chunk currently being recorded.
    public var currentDuration: TimeInterval { chunkDuration }

    /// Record one audio buffer. Returns `true` if the chunk should be cut
    /// *after* this buffer; call ``finishChunk()`` when you do.
    public mutating func ingest(duration: TimeInterval, rms: Float) -> Bool {
        chunkDuration += duration
        peakRMS = max(peakRMS, rms)
        if rms < configuration.silenceRMS {
            trailingSilence += duration
        } else {
            trailingSilence = 0
        }

        if chunkDuration >= configuration.maxChunkDuration {
            return true
        }
        if chunkDuration >= configuration.relaxedChunkDuration {
            return trailingSilence >= configuration.relaxedSilenceToCut
        }
        if chunkDuration >= configuration.minChunkDuration {
            return trailingSilence >= configuration.silenceToCut
        }
        return false
    }

    /// Close the current chunk and start a new one.
    @discardableResult
    public mutating func finishChunk() -> ChunkSummary {
        let summary = ChunkSummary(duration: chunkDuration, peakRMS: peakRMS)
        chunkDuration = 0
        trailingSilence = 0
        peakRMS = 0
        return summary
    }

    /// Whether a finished chunk contains anything worth sending to Whisper.
    public func isWorthTranscribing(_ summary: ChunkSummary) -> Bool {
        summary.duration >= 0.3 && summary.peakRMS >= configuration.speechRMS
    }
}
