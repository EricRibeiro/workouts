import XCTest

extension XCTestCase {
    /// `m:ss` (or `h:mm:ss`) to seconds; nil when the text is not a time.
    func seconds(from text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: " ").first.map(String.init)?.split(separator: ":").compactMap { Int($0) }
        guard let parts, !parts.isEmpty else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }

    /// The running ring's label is "Rest timer, 4:57" (the strip drops accessibilityValue): the part after ", ".
    func ringTime(_ ring: XCUIElement) -> String? {
        ring.label.components(separatedBy: ", ").dropFirst().first
    }
}
