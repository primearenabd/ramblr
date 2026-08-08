import Foundation

/// Extracts the recording time encoded by Apple Voice Memos in filenames such
/// as `20260803 072717-A88B4EC4.qta`.
///
/// File creation and modification dates are not authoritative for Voice Memos:
/// iCloud may replace them with the date a recording was downloaded to the Mac.
public enum VoiceMemoTimestamp {
    public static func recordingDate(
        fromFilename filename: String,
        calendar: Calendar = .current
    ) -> Date? {
        let prefixLength = 15 // yyyyMMdd HHmmss
        guard filename.count >= prefixLength else { return nil }

        let timestamp = String(filename.prefix(prefixLength))
        let digits = timestamp.enumerated().allSatisfy { offset, character in
            offset == 8 ? character == " " : character.isNumber
        }
        guard digits else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd HHmmss"
        formatter.isLenient = false
        return formatter.date(from: timestamp)
    }
}
