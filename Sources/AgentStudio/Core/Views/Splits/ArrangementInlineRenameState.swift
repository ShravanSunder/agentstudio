import Foundation
import Observation

@MainActor
@Observable
final class ArrangementInlineRenameState {
    struct CommitPayload: Equatable {
        let arrangementId: UUID
        let name: String
    }

    private(set) var editingArrangementId: UUID?
    var draftName: String = ""

    func beginEditing(arrangementId: UUID, currentName: String, isDefault: Bool) {
        guard !isDefault else { return }
        editingArrangementId = arrangementId
        draftName = currentName
    }

    func cancel() {
        editingArrangementId = nil
        draftName = ""
    }

    func commit() -> CommitPayload? {
        guard let arrangementId = editingArrangementId else { return nil }
        let normalizedName = Tab.normalizedName(draftName)
        guard !normalizedName.isEmpty else { return nil }
        let payload = CommitPayload(arrangementId: arrangementId, name: normalizedName)
        cancel()
        return payload
    }
}
