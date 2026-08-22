import AgentStudioCore
import AgentStudioInfrastructure
import SwiftUI

struct WorkspaceStatusChipRow: View {
    let octiconLoader: OcticonLoader
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
        HStack(spacing: AppStyles.Shell.Sidebar.chipRowSpacing) {
            if let diffChipDetail = SidebarDiffChip.workingTreeDetail(
                isDirty: model.branchStatus.isDirty,
                linesAdded: model.branchStatus.linesAdded,
                linesDeleted: model.branchStatus.linesDeleted,
                untrackedFileCount: model.branchStatus.untrackedFileCount
            ) {
                SidebarDiffChip(octiconLoader: octiconLoader, detail: diffChipDetail)
            }

            SidebarStatusSyncChip(
                octiconLoader: octiconLoader,
                aheadText: syncCounts.ahead,
                behindText: syncCounts.behind,
                hasSyncSignal: hasSyncSignal
            )

            SidebarChip(
                icon: model.branchStatus.prCount == nil
                    ? .system(.circle)
                    : .octicon("octicon-git-pull-request"),
                octiconLoader: octiconLoader,
                text: model.branchStatus.prCount.map(String.init),
                style: (model.branchStatus.prCount ?? 0) > 0 ? .accent(accentColor) : .neutral
            )
        }
    }
}
