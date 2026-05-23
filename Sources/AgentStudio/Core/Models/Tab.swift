import Foundation

/// A tab in the workspace. Contains panes organized into arrangements.
/// Order is implicit — determined by array position in the workspace's tabs array.
struct Tab: Codable, Identifiable, Hashable {
    // Memberwise equality so PaneTabViewController detects layout/focus/arrangement changes.
    // Hash by id only (Hashable contract: equal objects must have equal hashes,
    // but equal hashes need not imply equal objects).
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    /// Display name for this tab.
    var name: String
    /// All pane IDs owned by this tab.
    var allPaneIds: [UUID]
    /// Layout arrangements for this tab. Always has at least one default arrangement.
    var arrangements: [PaneArrangement]
    /// The currently active arrangement ID.
    var activeArrangementId: UUID
    /// Display-only zoom state — NOT persisted. When set, the zoomed pane fills the tab.
    var zoomedPaneId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case allPaneIds = "panes"
        case arrangements
        case activeArrangementId
        // zoomedPaneId excluded — transient, not persisted
    }

    /// Create a tab with a single pane.
    init(id: UUID = UUID(), paneId: UUID, name: String = "Tab") {
        self.id = id
        self.name = name
        self.allPaneIds = [paneId]
        let layout = Layout(paneId: paneId)
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            activePaneId: MainPaneId(paneId)
        )
        self.arrangements = [defaultArrangement]
        self.activeArrangementId = defaultArrangement.id
        self.zoomedPaneId = nil
    }

    /// Create a tab with an existing layout and arrangements.
    /// Precondition: `arrangements` must contain exactly one with `isDefault == true`.
    init(
        id: UUID = UUID(),
        name: String = "Tab",
        allPaneIds: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        zoomedPaneId: UUID? = nil
    ) {
        precondition(!arrangements.isEmpty, "Tab must have at least one arrangement")
        precondition(arrangements.filter(\.isDefault).count == 1, "Tab must have exactly one default arrangement")
        self.id = id
        self.name = name
        self.allPaneIds = allPaneIds
        self.arrangements = arrangements
        self.activeArrangementId = activeArrangementId
        self.zoomedPaneId = zoomedPaneId
    }

    init(
        id: UUID = UUID(),
        name: String = "Tab",
        panes: [UUID],
        arrangements: [PaneArrangement],
        activeArrangementId: UUID,
        zoomedPaneId: UUID? = nil
    ) {
        self.init(
            id: id,
            name: name,
            allPaneIds: panes,
            arrangements: arrangements,
            activeArrangementId: activeArrangementId,
            zoomedPaneId: zoomedPaneId
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let allPaneIds = try container.decode([UUID].self, forKey: .allPaneIds)
        let arrangements = try container.decode([PaneArrangement].self, forKey: .arrangements)
        let activeArrangementId = try container.decode(UUID.self, forKey: .activeArrangementId)

        guard !arrangements.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .arrangements,
                in: container,
                debugDescription: "Tab must have at least one arrangement"
            )
        }
        guard arrangements.filter(\.isDefault).count == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .arrangements,
                in: container,
                debugDescription: "Tab must have exactly one default arrangement"
            )
        }
        guard arrangements.contains(where: { $0.id == activeArrangementId }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .activeArrangementId,
                in: container,
                debugDescription: "Tab activeArrangementId must resolve to an arrangement"
            )
        }

        self.init(
            id: id,
            name: name,
            allPaneIds: allPaneIds,
            arrangements: arrangements,
            activeArrangementId: activeArrangementId,
            zoomedPaneId: nil
        )
    }

    // MARK: - Derived

    /// The default arrangement. Falls back to the first arrangement if no default is marked.
    /// Invariant: every tab must have at least one arrangement with `isDefault == true`.
    var defaultArrangement: PaneArrangement {
        guard let arr = arrangements.first(where: \.isDefault) ?? arrangements.first else {
            preconditionFailure("Tab \(id) has no arrangements — invariant violated")
        }
        return arr
    }

    /// The currently active arrangement.
    var activeArrangement: PaneArrangement {
        arrangements.first { $0.id == activeArrangementId } ?? defaultArrangement
    }

    /// Pane IDs in the active arrangement's layout (left-to-right traversal).
    var activePaneIds: [UUID] { activeArrangement.layout.paneIds }

    /// Pane IDs minimized in the active arrangement.
    var activeMinimizedPaneIds: Set<UUID> { activeArrangement.minimizedPaneIds.rawUUIDs }

    /// The focused pane within the active arrangement. Nil only when no pane can receive focus.
    var activePaneId: UUID? { activeArrangement.activePaneId?.rawValue }

    /// Whether the active arrangement has a split layout (more than one pane).
    var isSplit: Bool { activeArrangement.layout.isSplit }

    /// The layout of the active arrangement (convenience accessor).
    var layout: Layout { activeArrangement.layout }

    // Transitional compatibility aliases while the naming cut propagates.
    var panes: [UUID] {
        get { allPaneIds }
        set { allPaneIds = newValue }
    }

    var paneIds: [UUID] {
        activePaneIds
    }

    // MARK: - Arrangement Mutation Helpers

    /// Index of the default arrangement. Falls back to index 0 if no default marked.
    var defaultArrangementIndex: Int {
        guard let idx = arrangements.firstIndex(where: \.isDefault) else {
            preconditionFailure("Tab \(id) has no default arrangement — invariant violated")
        }
        return idx
    }

    /// Index of the active arrangement.
    var activeArrangementIndex: Int {
        arrangements.firstIndex { $0.id == activeArrangementId } ?? defaultArrangementIndex
    }

    static func normalizedName(_ rawName: String) -> String {
        rawName
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
