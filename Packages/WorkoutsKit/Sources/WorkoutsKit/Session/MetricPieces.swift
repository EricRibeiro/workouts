import Foundation

/// One styled run of a formatted metric: a number run (or plain text) or a unit run.
public nonisolated struct MetricPiece: Equatable, Sendable {
    public var text: String
    public var isUnit: Bool

    public init(text: String, isUnit: Bool) {
        self.text = text
        self.isUnit = isUnit
    }
}

/// Splits an already formatted metric (`14,569 lb`, `1h 5min`) into number and unit runs so a view can style the units.
public nonisolated enum MetricPieces {
    /// A letter run is a unit only when it directly follows a number run (optionally after one space): `22,318 lb` →
    /// `22,318` + `lb`, the space before a unit dropped; a further word right after a unit joins it with its space
    /// (`10 All Out` → `10` + `All Out`). Letters before the first number, or in a word that starts with
    /// letters (`e1RM`, `Push`), are plain text and keep their spacing; so does the space before a number (`1h 5min` →
    /// `1` `h` ` 5` `min`).
    public static func split(_ text: String) -> [MetricPiece] {
        enum Last { case none, number, unit, text }
        var pieces: [MetricPiece] = []
        var last = Last.none
        for word in text.split(whereSeparator: \.isWhitespace) {
            let isLabel = word.first?.isLetter == true && last != .number && last != .unit
            var space = !pieces.isEmpty
            var index = word.startIndex
            while index < word.endIndex {
                let isLetters = word[index].isLetter
                var end = index
                while end < word.endIndex, word[end].isLetter == isLetters { end = word.index(after: end) }
                let run = String(word[index..<end])
                index = end
                if isLetters, !isLabel, last == .unit, space {
                    pieces[pieces.count - 1].text += " " + run
                } else if isLetters, !isLabel, last == .number {
                    pieces.append(MetricPiece(text: run, isUnit: true))
                    last = .unit
                } else {
                    let lead = space ? " " : ""
                    if let tail = pieces.last, !tail.isUnit {
                        pieces[pieces.count - 1].text += lead + run
                    } else {
                        pieces.append(MetricPiece(text: lead + run, isUnit: false))
                    }
                    last = isLetters ? .text : .number
                }
                space = false
            }
        }
        return pieces
    }
}
