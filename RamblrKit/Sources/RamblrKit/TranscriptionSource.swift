import Foundation

/// Identifies which capture path produced a transcription that gets saved to
/// disk under the user's configured save-folder tree.
///
/// Ramblr has two very different sources feeding the same save folder:
/// - `.voiceMemo`: iPhone Voice Memos, auto-imported by the Voice Memos
///   folder watcher. These are typically fired from the phone's Action
///   Button as ideas occur, and downstream automation treats them as
///   actionable captures that it acts on.
/// - `.hotkey`: Mac hotkey recordings — dictated at the desk, intended to be
///   pasted somewhere by hand. These must never be picked up by that
///   automation.
///
/// Each source is filed into its own subdirectory (see
/// ``subdirectoryName``) underneath the date-based subdirectory, so a
/// consumer walking the save folder can tell them apart from the path alone.
/// Transcripts written before this distinction existed have no such
/// subdirectory at all — a consumer should treat that absence as
/// legacy/unknown, never assume it means one source or the other.
public enum TranscriptionSource: String, Sendable, CaseIterable {
    case voiceMemo = "voicememo"
    case hotkey = "hotkey"

    /// The subdirectory name transcripts from this source are filed under,
    /// e.g. `.../2026/08/03/voicememo/2026-08-03_13-03-58_hello.txt`.
    public var subdirectoryName: String { rawValue }
}
