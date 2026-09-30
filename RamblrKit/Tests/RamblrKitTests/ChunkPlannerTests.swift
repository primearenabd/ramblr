import XCTest
@testable import RamblrKit

final class ChunkPlannerTests: XCTestCase {

    private let loud: Float = 0.1
    private let quiet: Float = 0.001

    /// Feed `seconds` of audio in 0.1s buffers; returns the time of the first cut request, if any.
    private func feed(_ planner: inout ChunkPlanner, seconds: Double, rms: Float) -> Double? {
        var elapsed = 0.0
        while elapsed < seconds - 0.0001 {
            elapsed += 0.1
            if planner.ingest(duration: 0.1, rms: rms) { return elapsed }
        }
        return nil
    }

    func testNeverCutsBeforeMinimumDuration() {
        var planner = ChunkPlanner()
        XCTAssertNil(feed(&planner, seconds: 11, rms: quiet))
    }

    func testCutsAtPauseOnceMinimumDurationReached() {
        var planner = ChunkPlanner()
        XCTAssertNil(feed(&planner, seconds: 13, rms: loud))
        // Speech ran past the 12s minimum; a 0.4s pause should now trigger a cut.
        let cut = feed(&planner, seconds: 1, rms: quiet)
        XCTAssertNotNil(cut)
        XCTAssertEqual(cut ?? 0, 0.4, accuracy: 0.11)
    }

    func testBriefPauseDoesNotCutBeforeRelaxedThreshold() {
        var planner = ChunkPlanner()
        XCTAssertNil(feed(&planner, seconds: 13, rms: loud))
        XCTAssertNil(feed(&planner, seconds: 0.3, rms: quiet))
        XCTAssertNil(feed(&planner, seconds: 1, rms: loud), "speech resumed, silence counter must reset")
    }

    func testRelaxedPauseAcceptedAfterRelaxedDuration() {
        var planner = ChunkPlanner()
        XCTAssertNil(feed(&planner, seconds: 20, rms: loud))
        XCTAssertNotNil(feed(&planner, seconds: 0.3, rms: quiet))
    }

    func testForcesCutAtMaximumDurationEvenMidSpeech() {
        var planner = ChunkPlanner()
        let cut = feed(&planner, seconds: 60, rms: loud)
        XCTAssertEqual(cut ?? 0, 28, accuracy: 0.11)
    }

    func testFinishChunkResetsState() {
        var planner = ChunkPlanner()
        _ = feed(&planner, seconds: 5, rms: loud)
        let summary = planner.finishChunk()
        XCTAssertEqual(summary.duration, 5, accuracy: 0.01)
        XCTAssertEqual(summary.peakRMS, loud, accuracy: 0.0001)
        XCTAssertEqual(planner.currentDuration, 0)
    }

    func testSilentOrTinyChunksAreNotWorthTranscribing() {
        let planner = ChunkPlanner()
        XCTAssertFalse(planner.isWorthTranscribing(.init(duration: 5, peakRMS: 0.002)))
        XCTAssertFalse(planner.isWorthTranscribing(.init(duration: 0.1, peakRMS: 0.2)))
        XCTAssertTrue(planner.isWorthTranscribing(.init(duration: 3, peakRMS: 0.05)))
    }
}
