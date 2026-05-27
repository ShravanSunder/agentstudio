import Foundation

extension CommandBarDataSource {
    static func paneNoteSecondaryLine(_ pane: Pane) -> CommandBarItemSecondaryLine? {
        guard let note = pane.metadata.note?.trimmingCharacters(in: .whitespacesAndNewlines),
            !note.isEmpty
        else {
            return nil
        }

        return CommandBarItemSecondaryLine(
            text: note,
            icon: .system(.longTextPageAndPencil)
        )
    }
}
