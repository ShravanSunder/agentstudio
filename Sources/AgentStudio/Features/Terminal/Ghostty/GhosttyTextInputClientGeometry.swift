import AppKit

struct GhosttyIMEPointAndSize: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

func ghosttyTextInputSelectionRange(offsetStart: Int, offsetLength: Int) -> NSRange {
    NSRange(location: offsetStart, length: offsetLength)
}

func ghosttyTextInputMarkedRange(length: Int) -> NSRange {
    guard length > 0 else { return NSRange() }
    return NSRange(0...(length - 1))
}

func ghosttyTextInputViewRect(
    pointAndSize: GhosttyIMEPointAndSize,
    characterRange: NSRange,
    cellSize: NSSize,
    viewHeight: CGFloat
) -> NSRect {
    var x = pointAndSize.x
    var width = pointAndSize.width

    if characterRange.length == 0, width > 0 {
        // Dictation's microphone indicator uses a caret point, not a text-cell width.
        width = 0
        x += Double(cellSize.width) * Double(characterRange.location + characterRange.length)
    }

    // Ghostty reports top-left coordinates; AppKit positions views from the bottom-left.
    return NSRect(
        x: x,
        y: Double(viewHeight) - pointAndSize.y,
        width: width,
        height: max(pointAndSize.height, Double(cellSize.height))
    )
}
