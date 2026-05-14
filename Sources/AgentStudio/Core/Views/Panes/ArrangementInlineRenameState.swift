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
    private(set) var draftName: String = ""

    func beginEditing(arrangementId: UUID, currentName: String, isDefault: Bool) {
        guard !isDefault else { return }
        editingArrangementId = arrangementId
        draftName = currentName
    }

    func setDraftName(_ name: String) {
        draftName = name
    }

    func cancel() {
        editingArrangementId = nil
        draftName = ""
    }

    /// Commits the draft name. Empty/whitespace-only draft clears state and returns nil
    /// (treated as cancel rather than a silent stuck edit). Non-empty draft returns a
    /// payload for the caller to dispatch; state is always cleared before returning.
    func commit() -> CommitPayload? {
        guard let arrangementId = editingArrangementId else { return nil }
        let normalizedName = Tab.normalizedName(draftName)
        guard !normalizedName.isEmpty else {
            cancel()
            return nil
        }
        let payload = CommitPayload(arrangementId: arrangementId, name: normalizedName)
        cancel()
        return payload
    }
}
