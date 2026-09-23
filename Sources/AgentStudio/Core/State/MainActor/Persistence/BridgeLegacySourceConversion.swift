import Foundation

/// Conversion DTO for the retired `BridgePaneState.source` field.
///
/// Live pane state no longer carries a source; this type exists only so the
/// ordered one-time import can read legacy core payloads. It is never written.
package enum LegacyBridgePaneSourceDTO: Decodable, Hashable, Sendable {
    case commit(sha: String)
    case branchDiff(head: String, base: String)
    case workspace(rootPath: String, baseline: WorkspaceBaseline?)
    case agentSnapshot(taskId: UUID, timestamp: Date)

    private enum CodingKeys: String, CodingKey {
        case commit
        case branchDiff
        case workspace
        case agentSnapshot
    }

    private enum CommitCodingKeys: String, CodingKey {
        case sha
    }

    private enum BranchDiffCodingKeys: String, CodingKey {
        case head
        case base
    }

    private enum WorkspaceCodingKeys: String, CodingKey {
        case rootPath
        case baseline
        case comparisonTarget
    }

    private enum AgentSnapshotCodingKeys: String, CodingKey {
        case taskId
        case timestamp
    }

    package var importedVariant: BridgeImportedReviewQuery.Variant {
        switch self {
        case .commit: .commit
        case .branchDiff: .branchDiff
        case .workspace: .workspace
        case .agentSnapshot: .agentSnapshot
        }
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.allKeys.count == 1, let sourceKey = container.allKeys.first else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Bridge pane source must contain exactly one recognized case"
                )
            )
        }

        switch sourceKey {
        case .commit:
            let commit = try container.nestedContainer(keyedBy: CommitCodingKeys.self, forKey: .commit)
            self = .commit(sha: try commit.decode(String.self, forKey: .sha))
        case .branchDiff:
            let branchDiff = try container.nestedContainer(keyedBy: BranchDiffCodingKeys.self, forKey: .branchDiff)
            self = .branchDiff(
                head: try branchDiff.decode(String.self, forKey: .head),
                base: try branchDiff.decode(String.self, forKey: .base)
            )
        case .workspace:
            let workspace = try container.nestedContainer(keyedBy: WorkspaceCodingKeys.self, forKey: .workspace)
            let baseline: WorkspaceBaseline?
            if workspace.contains(.comparisonTarget) {
                baseline = WorkspaceBaseline(
                    contributionTarget: try workspace.decode(
                        WorkspaceReviewContributionTarget.self,
                        forKey: .comparisonTarget
                    )
                )
            } else if let legacyBaseline = try workspace.decodeIfPresent(WorkspaceBaseline.self, forKey: .baseline) {
                baseline = Self.canonicalBaseline(fromLegacy: legacyBaseline)
            } else {
                baseline = nil
            }
            self = .workspace(
                rootPath: try workspace.decode(String.self, forKey: .rootPath),
                baseline: baseline
            )
        case .agentSnapshot:
            let snapshot = try container.nestedContainer(
                keyedBy: AgentSnapshotCodingKeys.self,
                forKey: .agentSnapshot
            )
            self = .agentSnapshot(
                taskId: try snapshot.decode(UUID.self, forKey: .taskId),
                timestamp: try snapshot.decode(Date.self, forKey: .timestamp)
            )
        }
    }

    private static func canonicalBaseline(fromLegacy baseline: WorkspaceBaseline) -> WorkspaceBaseline? {
        switch baseline {
        case .localDefaultBranch:
            nil
        case .ref(let name, _) where name == "HEAD":
            nil
        case .originDefaultBranch, .branch, .commit, .ref, .headMinusOne, .staged, .unstaged:
            baseline
        }
    }
}

/// A core `bridgePanel` payload that still carries the legacy `source` field.
package struct BridgeLegacyPanePayload: Equatable, Sendable {
    package let paneId: UUID
    package let panelKind: BridgePanelKind
    /// The exact stored core payload, preserved byte-for-byte until import is
    /// acknowledged.
    package let originalPayloadJSON: String
    /// The exact JSON of the legacy `source` object, kept for unresolvable
    /// variants so they stay identifiable instead of being discarded.
    package let legacySourceJSON: String
    /// Decoded legacy source, or `nil` when it could not be decoded.
    package let legacySource: LegacyBridgePaneSourceDTO?
    /// The source-free payload written by the core conversion step.
    package let convertedPayloadJSON: String
}

package enum BridgeLegacySourceConversionError: Error, Equatable, Sendable {
    case malformedPayload(paneId: UUID)
}

/// Pure steps of the ordered legacy conversion: detect a legacy payload and
/// build the imported navigation record. The datastore owns the ordered
/// local-commit-then-core-rewrite sequence around these steps.
package enum BridgeLegacySourceConversion {
    /// Returns the legacy payload when the stored bridge payload still has a
    /// `state.source` field, `nil` when it is already source-free.
    package static func legacyPayload(
        paneId: UUID,
        storedPayloadJSON: String
    ) throws -> BridgeLegacyPanePayload? {
        guard
            let root = try? JSONSerialization.jsonObject(with: Data(storedPayloadJSON.utf8)) as? [String: Any],
            let state = root["state"] as? [String: Any]
        else {
            throw BridgeLegacySourceConversionError.malformedPayload(paneId: paneId)
        }
        guard let sourceObject = state["source"], !(sourceObject is NSNull) else {
            return nil
        }
        guard
            let rawPanelKind = state["panelKind"] as? String,
            let panelKind = BridgePanelKind(rawValue: rawPanelKind),
            JSONSerialization.isValidJSONObject(sourceObject),
            let sourceData = try? JSONSerialization.data(withJSONObject: sourceObject, options: [.sortedKeys]),
            let legacySourceJSON = String(data: sourceData, encoding: .utf8)
        else {
            throw BridgeLegacySourceConversionError.malformedPayload(paneId: paneId)
        }
        let converted = try JSONEncoder().encode(PaneContent.bridgePanel(BridgePaneState(panelKind: panelKind)))
        guard let convertedPayloadJSON = String(data: converted, encoding: .utf8) else {
            throw BridgeLegacySourceConversionError.malformedPayload(paneId: paneId)
        }
        return BridgeLegacyPanePayload(
            paneId: paneId,
            panelKind: panelKind,
            originalPayloadJSON: storedPayloadJSON,
            legacySourceJSON: legacySourceJSON,
            legacySource: try? JSONDecoder().decode(LegacyBridgePaneSourceDTO.self, from: sourceData),
            convertedPayloadJSON: convertedPayloadJSON
        )
    }

    /// Build the imported record for a standalone Bridge pane. A workspace
    /// root that exactly matches a known worktree imports as that member with
    /// its comparison; every other variant stays an identifiable unavailable
    /// imported value with its original payload — never a fake worktree.
    package static func importedRecord(
        for payload: BridgeLegacyPanePayload,
        knownWorktreeIdsByCanonicalRootPath: [String: UUID],
        canonicalize: (String) -> String
    ) -> BridgeNavigationRecord {
        let surface: BridgeNavigationSurface = payload.panelKind == .diffViewer ? .review : .files
        if case .workspace(let rootPath, let baseline)? = payload.legacySource,
            let worktreeId = knownWorktreeIdsByCanonicalRootPath[canonicalize(rootPath)]
        {
            return BridgeNavigationRecord(
                memberWorktreeIds: [worktreeId],
                reviewSelection: .member(worktreeId: worktreeId),
                surface: surface,
                reviewComparisonsByWorktreeId: baseline.map { [worktreeId: $0] } ?? [:]
            )
        }
        let variant = payload.legacySource?.importedVariant ?? .workspace
        return BridgeNavigationRecord(
            reviewSelection: .importedUnavailable(
                BridgeImportedReviewQuery(variant: variant, originalPayloadJSON: payload.legacySourceJSON)
            ),
            surface: surface
        )
    }
}
