import XCTest
@testable import RamblrKit

final class TranscriptCleanerTests: XCTestCase {

    func testAcceptsNormalCleanup() {
        let original = "well I think this part is fine but maybe we should rename that variable and actually wait let me let me look at the other file"
        let cleaned = "I think this part is fine, but maybe we should rename that variable. Actually, wait, let me look at the other file."
        XCTAssertTrue(TranscriptCleaner.isAcceptable(original: original, cleaned: cleaned))
    }

    func testRejectsSummaries() {
        let original = String(repeating: "this is a fairly long dictated sentence ", count: 10)
        XCTAssertFalse(TranscriptCleaner.isAcceptable(original: original, cleaned: "A long sentence."))
    }

    func testRejectsInventedText() {
        let original = "open the file called audio manager and find the function"
        let cleaned = original + " Sure! Here is the file. I opened it and found the function you were looking for in line forty two."
        XCTAssertFalse(TranscriptCleaner.isAcceptable(original: original, cleaned: cleaned))
    }

    func testRejectsEmptyReply() {
        XCTAssertFalse(TranscriptCleaner.isAcceptable(original: "some words here", cleaned: ""))
    }

    func testStripsEchoedWrapperTags() {
        XCTAssertEqual(
            TranscriptCleaner.stripWrapper("<transcript>\nHello there.\n</transcript>"),
            "Hello there."
        )
    }

    func testPromptContainsVocabularyAndTranscript() {
        let messages = TranscriptCleaner.messages(
            text: "open the grok file",
            precedingText: "earlier text",
            vocabulary: ["Groq", "Xcode"]
        )
        XCTAssertEqual(messages.count, 2)
        let user = messages[1]["content"] ?? ""
        XCTAssertTrue(user.contains("<vocabulary>Groq, Xcode</vocabulary>"))
        XCTAssertTrue(user.contains("<previous_text>earlier text</previous_text>"))
        XCTAssertTrue(user.contains("<transcript>\nopen the grok file\n</transcript>"))
    }

    func testVeryShortTextIsNotSentForCleaning() async {
        let cleaner = TranscriptCleaner(provider: .groq, apiKey: "key")
        // Fewer than the minimum word count returns immediately without any network call.
        let result = await cleaner.clean("  Yes please  ")
        XCTAssertEqual(result, "Yes please")
    }

    func testMissingKeyReturnsOriginal() async {
        let cleaner = TranscriptCleaner(provider: .groq, apiKey: "   ")
        let text = "this text has more than four words"
        let result = await cleaner.clean(text)
        XCTAssertEqual(result, text)
    }

    func testDetectsVocabularyEcho() {
        let prompt = "Ramblr, Groq, OpenAI, Whisper, Xcode"
        XCTAssertTrue(TranscriptionService.isPromptEcho("Ramblr, Groq, OpenAI.", prompt: prompt))
        XCTAssertFalse(TranscriptionService.isPromptEcho("Open the Groq console please", prompt: prompt))
        XCTAssertFalse(TranscriptionService.isPromptEcho("", prompt: prompt))
    }

    func testMultipartIncludesPromptOnlyWhenGiven() {
        func body(_ prompt: String?) -> String {
            let data = TranscriptionService.multipartBody(
                boundary: "B", audioData: Data([1, 2, 3]), filename: "a.m4a",
                mimeType: "audio/mp4", model: "whisper-large-v3", prompt: prompt
            )
            return String(decoding: data, as: UTF8.self)
        }
        XCTAssertTrue(body("Groq, Xcode").contains("name=\"prompt\"\r\n\r\nGroq, Xcode"))
        XCTAssertFalse(body(nil).contains("name=\"prompt\""))
    }
}
