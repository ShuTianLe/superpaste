import Foundation

enum PreviewTextFormatter {
    static func displayText(
        _ text: String,
        maxCharacters: Int = 600,
        breakEvery runLength: Int = 22
    ) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let clipped: String
        if normalized.count > maxCharacters {
            clipped = String(normalized.prefix(maxCharacters)) + "..."
        } else {
            clipped = normalized
        }

        var result = ""
        var runCount = 0
        for character in clipped {
            if character.isWhitespace || character == "/" || character == "." || character == "-" || character == "_" || character == "=" || character == "&" || character == "?" {
                runCount = 0
                result.append(character)
            } else {
                runCount += 1
                result.append(character)
                if runCount >= runLength {
                    result.append("\u{200B}")
                    runCount = 0
                }
            }
        }
        return result
    }
}
