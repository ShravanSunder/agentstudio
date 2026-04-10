import AppKit
import Foundation

@MainActor
protocol TabRenamePrompting {
    func promptToRenameTab(currentName: String, window: NSWindow?) -> String?
}

struct AlertTabRenamePrompter: TabRenamePrompting {
    static func promptTitle(currentName: String) -> String {
        let trimmedName = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Rename Tab" }
        return "Rename \"\(trimmedName)\""
    }

    static func informativeText(currentName: String) -> String {
        let trimmedName = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Enter a new name for this tab." }
        return "Enter a new name for \"\(trimmedName)\"."
    }

    func promptToRenameTab(currentName: String, window _: NSWindow?) -> String? {
        let alert = NSAlert()
        alert.messageText = Self.promptTitle(currentName: currentName)
        alert.informativeText = Self.informativeText(currentName: currentName)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: currentName)
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return textField.stringValue
    }
}
