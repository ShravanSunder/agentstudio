import AgentStudioCore
import Foundation

enum RepoExplorerPaneRowLine: Equatable, Sendable {
    case title(String)
    case worktreeBranch(String)
    case note(String)
}

enum RepoExplorerPaneChipKind: Equatable, Sendable {
    case drawer
    case gitPR
    case changes
    case sync
    case notifications
    case clock
    case active
}

struct RepoExplorerPaneRowVariant: Equatable, Sendable {
    let lines: [RepoExplorerPaneRowLine]
    let chips: [RepoExplorerPaneChipKind]
    let fallbackLineCount: Int
}

struct RepoExplorerPaneRowVariants: Equatable, Sendable {
    let compact: RepoExplorerPaneRowVariant
    let expanded: RepoExplorerPaneRowVariant

    static func make(
        title: String,
        branchContext: String?,
        note: String?,
        isDrawer: Bool,
        branchStatus: GitBranchStatus?,
        isActive: Bool
    ) -> Self {
        var lines: [RepoExplorerPaneRowLine] = [.title(title)]
        if let branchContext { lines.append(.worktreeBranch(branchContext)) }
        if let note { lines.append(.note(note)) }

        var compactChips: [RepoExplorerPaneChipKind] = []
        if isDrawer { compactChips.append(.drawer) }
        if let branchStatus,
            SidebarPullRequestChipSpec.presentation(
                branchStatus: branchStatus,
                usesPanesLoadingChip: true
            ) != .hidden
        {
            compactChips.append(.gitPR)
        }
        var expandedChips = compactChips
        if let branchStatus {
            if SidebarGitStatusChips.diffDetail(branchStatus: branchStatus) != nil {
                expandedChips.append(.changes)
            }
            if SidebarGitStatusChips.showsSync(branchStatus: branchStatus) {
                expandedChips.append(.sync)
            }
        }
        compactChips.append(.clock)
        expandedChips.append(.clock)
        if isActive {
            compactChips.append(.active)
            expandedChips.append(.active)
        }
        let lineCount = lines.count + 1  // The clock guarantees one chip line in both variants.
        return Self(
            compact: RepoExplorerPaneRowVariant(
                lines: lines,
                chips: compactChips,
                fallbackLineCount: lineCount
            ),
            expanded: RepoExplorerPaneRowVariant(
                lines: lines,
                chips: expandedChips,
                fallbackLineCount: lineCount
            )
        )
    }
}
