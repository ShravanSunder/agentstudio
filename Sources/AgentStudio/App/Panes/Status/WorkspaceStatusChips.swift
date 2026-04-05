import SwiftUI

struct WorkspaceStatusChipsModel: Equatable {
    let branchStatus: GitBranchStatus
    let notificationCount: Int
}

struct WorkspaceStatusChipRow: View {
    let model: WorkspaceStatusChipsModel
    let accentColor: Color

    private var syncCounts: (ahead: String, behind: String) {
        switch model.branchStatus.syncState {
        case .synced:
            return ("0", "0")
        case .ahead(let count):
            return ("\(count)", "0")
        case .behind(let count):
            return ("0", "\(count)")
        case .diverged(let ahead, let behind):
            return ("\(ahead)", "\(behind)")
        case .noUpstream:
            return ("-", "-")
        case .unknown:
            return ("?", "?")
        }
    }

    private var hasSyncSignal: Bool {
        switch model.branchStatus.syncState {
        case .ahead(let count):
            return count > 0
        case .behind(let count):
            return count > 0
        case .diverged(let ahead, let behind):
            return ahead > 0 || behind > 0
        case .synced, .noUpstream, .unknown:
            return false
        }
    }

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipRowSpacing) {
            SidebarDiffChip(
                linesAdded: model.branchStatus.linesAdded,
                linesDeleted: model.branchStatus.linesDeleted,
                showsDirtyIndicator: model.branchStatus.isDirty,
                isMuted: model.branchStatus.linesAdded == 0 && model.branchStatus.linesDeleted == 0
            )

            SidebarStatusSyncChip(
                aheadText: syncCounts.ahead,
                behindText: syncCounts.behind,
                hasSyncSignal: hasSyncSignal
            )

            SidebarChip(
                iconAsset: "octicon-git-pull-request",
                text: "\(model.branchStatus.prCount ?? 0)",
                style: (model.branchStatus.prCount ?? 0) > 0 ? .accent(accentColor) : .neutral
            )

            SidebarChip(
                iconAsset: "octicon-bell",
                text: "\(model.notificationCount)",
                style: model.notificationCount > 0 ? .accent(accentColor) : .neutral
            )
        }
    }
}
