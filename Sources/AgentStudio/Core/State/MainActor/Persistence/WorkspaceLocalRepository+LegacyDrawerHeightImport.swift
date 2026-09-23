import Foundation
import GRDB

/// Inputs captured before the one-time cutover from the retired global drawer
/// height to per-owner preferences.
package struct LegacyDrawerPresentationImport: Equatable, Sendable {
    /// Finite legacy ratio, already clamped into the saved range.
    let normalHeightRatio: Double
    /// Owning layout panes of every persisted workspace at import time.
    let owningPaneIdsByWorkspaceId: [UUID: Set<UUID>]

    package init?(legacyHeightRatio: Double?, owningPaneIdsByWorkspaceId: [UUID: Set<UUID>]) {
        guard let legacyHeightRatio,
            let normalHeightRatio = DrawerPresentationPreference.validatedNormalHeightRatio(legacyHeightRatio)
        else { return nil }
        self.normalHeightRatio = normalHeightRatio
        self.owningPaneIdsByWorkspaceId = owningPaneIdsByWorkspaceId
    }
}

/// Outcome of capturing the legacy import inputs at boot.
package enum LegacyDrawerPresentationImportCapture: Equatable, Sendable {
    /// No finite legacy height exists; nothing to import or clear.
    case noLegacyValue
    case captured(LegacyDrawerPresentationImport)
    /// Owning panes could not be read. Nothing is written and the legacy key
    /// stays as the pending marker for the next boot.
    case ownerEnumerationFailed

    package static func capture(
        source: LegacyDrawerPresentationSource?,
        enumerateOwners: () throws -> [UUID: Set<UUID>]
    ) -> Self {
        guard let legacyHeightRatio = source?.readHeightRatio(),
            DrawerPresentationPreference.validatedNormalHeightRatio(legacyHeightRatio) != nil
        else { return .noLegacyValue }
        guard let owningPaneIdsByWorkspaceId = try? enumerateOwners() else { return .ownerEnumerationFailed }
        guard
            let legacyImport = LegacyDrawerPresentationImport(
                legacyHeightRatio: legacyHeightRatio,
                owningPaneIdsByWorkspaceId: owningPaneIdsByWorkspaceId
            )
        else { return .noLegacyValue }
        return .captured(legacyImport)
    }

    package var importToApply: LegacyDrawerPresentationImport? {
        guard case .captured(let legacyImport) = self else { return nil }
        return legacyImport
    }
}

/// Where the retired global drawer height is read from and cleared after the
/// import commits. Its presence is the import's pending marker. Production
/// uses the app's standard defaults; tests inject their own value so they never
/// touch a developer's defaults domain.
package struct LegacyDrawerPresentationSource: Sendable {
    package static let legacyHeightRatioKey = "drawerHeightRatio"

    let readHeightRatio: @Sendable () -> Double?
    let clear: @Sendable () -> Void

    package init(
        readHeightRatio: @escaping @Sendable () -> Double?,
        clear: @escaping @Sendable () -> Void
    ) {
        self.readHeightRatio = readHeightRatio
        self.clear = clear
    }

    package static let standardUserDefaults = Self(
        readHeightRatio: {
            UserDefaults.standard.object(forKey: legacyHeightRatioKey) as? Double
        },
        clear: {
            UserDefaults.standard.removeObject(forKey: legacyHeightRatioKey)
        }
    )
}

extension WorkspaceLocalRepository {
    /// Writes the legacy height for every captured owning pane in one local
    /// transaction. Rows an ordinary save already wrote are kept.
    func importLegacyDrawerHeight(_ legacyImport: LegacyDrawerPresentationImport) throws {
        let importedAt = Date().timeIntervalSince1970
        try databaseWriter.write { database in
            for (workspaceId, owningPaneIds) in legacyImport.owningPaneIdsByWorkspaceId {
                for ownerPaneId in owningPaneIds {
                    try database.execute(
                        sql: """
                            INSERT OR IGNORE INTO local_drawer_presentation(
                                workspace_id, owner_pane_id, normal_height_ratio, zoom_side, updated_at
                            )
                            VALUES (?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            workspaceId.uuidString,
                            ownerPaneId.uuidString,
                            legacyImport.normalHeightRatio,
                            DrawerZoomSide.terminal.rawValue,
                            importedAt,
                        ]
                    )
                }
            }
        }
    }
}
