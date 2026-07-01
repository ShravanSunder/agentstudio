import AppKit

final class ShellChromeDragRegionView: NSView {
    static let viewIdentifier = NSUserInterfaceItemIdentifier("shellChromeDragRegion")

    var performWindowDrag: ((NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.viewIdentifier
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func mouseDown(with event: NSEvent) {
        if let performWindowDrag {
            performWindowDrag(event)
            return
        }
        window?.performDrag(with: event)
    }
}
