import XCTest
@testable import RamblrKit

final class RamblrKitTests: XCTestCase {

    func testModelIdentifierRoundTrip() {
        let groq = TranscriptionModel(identifier: "groq:whisper-large-v3")
        XCTAssertEqual(groq.provider, .groq)
        XCTAssertEqual(groq.modelName, "whisper-large-v3")
        XCTAssertEqual(groq.identifier, "groq:whisper-large-v3")
        XCTAssertEqual(groq.displayName, "Whisper (Groq)")
    }

    func testModelParsingFallsBackToOpenAIWhisper() {
        // Legacy bare value and unknown provider both fall back.
        XCTAssertEqual(TranscriptionModel(identifier: "whisper-1").identifier, "openai:whisper-1")
        XCTAssertEqual(TranscriptionModel(identifier: "bogus:thing").identifier, "openai:whisper-1")
    }

    func testProviderBaseURLs() {
        XCTAssertEqual(TranscriptionModel.Provider.groq.baseURL.absoluteString, "https://api.groq.com/openai")
        XCTAssertEqual(TranscriptionModel.Provider.openai.baseURL.absoluteString, "https://api.openai.com")
    }

    func testMimeTypeMapping() {
        XCTAssertEqual(TranscriptionService.mimeType(for: "WAV"), "audio/wav")
        XCTAssertEqual(TranscriptionService.mimeType(for: "m4a"), "audio/mp4")
        XCTAssertEqual(TranscriptionService.mimeType(for: "xyz"), "application/octet-stream")
    }

    func testUploadFilenameKeepsSupportedExtensions() {
        let m4a = URL(fileURLWithPath: "/tmp/20260803 072717-A88B4EC4.m4a")
        XCTAssertEqual(TranscriptionService.uploadFilename(for: m4a), "20260803 072717-A88B4EC4.m4a")
        let wav = URL(fileURLWithPath: "/tmp/chunk-1.WAV")
        XCTAssertEqual(TranscriptionService.uploadFilename(for: wav), "chunk-1.WAV")
    }

    func testUploadFilenameRemapsUnsupportedExtensions() {
        // Voice Memos .qta files are ISO/QuickTime audio the API can decode,
        // but the extension fails server-side filename validation.
        let qta = URL(fileURLWithPath: "/tmp/20260803 072717-A88B4EC4.qta")
        XCTAssertEqual(TranscriptionService.uploadFilename(for: qta), "20260803 072717-A88B4EC4.m4a")
    }

    func testMultipartBodyContainsFields() {
        let body = TranscriptionService.multipartBody(
            boundary: "BOUND",
            audioData: Data([0x01, 0x02, 0x03]),
            filename: "recording.wav",
            mimeType: "audio/wav",
            model: "whisper-large-v3"
        )
        let string = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(string.contains("--BOUND\r\n"))
        XCTAssertTrue(string.contains("filename=\"recording.wav\""))
        XCTAssertTrue(string.contains("name=\"model\""))
        XCTAssertTrue(string.contains("whisper-large-v3"))
        XCTAssertTrue(string.contains("name=\"temperature\""))
        XCTAssertTrue(string.contains("--BOUND--\r\n"))
    }

    func testTranscriptionSourceSubdirectoryNames() {
        // These raw values are an on-disk contract: downstream automation
        // filters for Voice Memos captures by checking for a "voicememo"
        // path component, so these strings must not change casually.
        XCTAssertEqual(TranscriptionSource.voiceMemo.subdirectoryName, "voicememo")
        XCTAssertEqual(TranscriptionSource.hotkey.subdirectoryName, "hotkey")
    }

    func testErrorRetriability() {
        XCTAssertTrue(TranscriptionError.timeout.isRetriable)
        XCTAssertTrue(TranscriptionError.apiError(429, "rate").isRetriable)
        XCTAssertTrue(TranscriptionError.apiError(503, "down").isRetriable)
        XCTAssertFalse(TranscriptionError.apiError(400, "invalid audio").isRetriable)
        XCTAssertFalse(TranscriptionError.apiError(401, "auth").isRetriable)
        XCTAssertFalse(TranscriptionError.noAPIKey.isRetriable)
    }
}
