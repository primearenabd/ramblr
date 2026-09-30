import XCTest
@testable import RamblrKit

final class SpeedGuardTests: XCTestCase {

    func testDeadlineReturnsResultWhenFast() async {
        let value = await Deadline.run(seconds: 1) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testDeadlineGivesUpOnSlowWork() async {
        let started = Date()
        let value: Int? = await Deadline.run(seconds: 0.1) {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            return 42
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0, "must not wait for the slow work")
    }

    func testDeadlineGivesUpEvenIfWorkIgnoresCancellation() async {
        let started = Date()
        let value: Int? = await Deadline.run(seconds: 0.1) {
            // Uninterruptible wait, like awaiting another Task's value.
            await Task<Int, Never> { try? await Task.sleep(nanoseconds: 2_000_000_000); return 7 }.value
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testTidyRemovesFillersAndStutters() {
        XCTAssertEqual(LocalTextTidy.tidy("So um, I I think we should we should go"), "So I think we should go")
        XCTAssertEqual(LocalTextTidy.tidy("let me let me look at the other file"), "Let me look at the other file")
        XCTAssertEqual(LocalTextTidy.tidy("Uh okay"), "Okay")
    }

    func testTidyLeavesLegitimateRepeatsAlone() {
        XCTAssertEqual(LocalTextTidy.tidy("That was very very good."), "That was very very good.")
        XCTAssertEqual(LocalTextTidy.tidy("He said he had had enough."), "He said he had had enough.")
    }

    func testTidyKeepsTrailingPunctuationOfRepeat() {
        XCTAssertEqual(LocalTextTidy.tidy("I think I think, it works."), "I think, it works.")
    }

    func testTidyOnCleanTextIsIdentity() {
        let text = "Open the file called audio manager and find the function."
        XCTAssertEqual(LocalTextTidy.tidy(text), text)
    }
}
