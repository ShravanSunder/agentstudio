import AppKit

final class MainWindowController: NSWindowController {
    func configure(button: NSButton) {
        button.toolTip = "Watch folder"
    }
}
