import SwiftUI

// MARK: - Pinned Constants

enum WelcomeSidebarIllustrationConstants {
    static let frameWidth: CGFloat = 300
    static let ghosttyPaletteIndex: Int = 0
    static let uvPaletteIndex: Int = 3
}

// MARK: - Mock Data

private let ghosttyRepoId = UUID()
private let uvRepoId = UUID()

private let ghosttyMainWorktree = Worktree(
    repoId: ghosttyRepoId,
    name: "ghostty",
    path: URL(fileURLWithPath: "/tmp/mock/ghostty"),
    isMainWorktree: true
)

private let ghosttyGpuRendererWorktree = Worktree(
    repoId: ghosttyRepoId,
    name: "ghostty.gpu-renderer",
    path: URL(fileURLWithPath: "/tmp/mock/ghostty.gpu-renderer"),
    isMainWorktree: false
)

private let ghosttyFixKeybindsWorktree = Worktree(
    repoId: ghosttyRepoId,
    name: "ghostty.fix-keybinds",
    path: URL(fileURLWithPath: "/tmp/mock/ghostty.fix-keybinds"),
    isMainWorktree: false
)

private let uvMainWorktree = Worktree(
    repoId: uvRepoId,
    name: "uv",
    path: URL(fileURLWithPath: "/tmp/mock/uv"),
    isMainWorktree: true
)

private let uvFixResolverWorktree = Worktree(
    repoId: uvRepoId,
    name: "uv.fix-resolver",
    path: URL(fileURLWithPath: "/tmp/mock/uv.fix-resolver"),
    isMainWorktree: false
)

private let ghosttyMainStatus = GitBranchStatus(
    isDirty: false,
    syncState: .synced,
    prCount: 2,
    linesAdded: 0,
    linesDeleted: 0
)

private let uvMainStatus = GitBranchStatus(
    isDirty: true,
    syncState: .behind(3),
    prCount: 0,
    linesAdded: 5,
    linesDeleted: 2
)

private let gpuRendererStatus = GitBranchStatus(
    isDirty: true,
    syncState: .ahead(3),
    prCount: 1,
    linesAdded: 86,
    linesDeleted: 12
)

private let fixKeybindsStatus = GitBranchStatus(
    isDirty: false,
    syncState: .synced,
    prCount: 1,
    linesAdded: 24,
    linesDeleted: 8
)

private let fixResolverStatus = GitBranchStatus(
    isDirty: false,
    syncState: .ahead(1),
    prCount: 1,
    linesAdded: 12,
    linesDeleted: 3
)

// MARK: - Color Helpers

private let ghosttyColor = AppStyles.Shell.Sidebar.paletteColor(
    at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex
)
private let uvColor = AppStyles.Shell.Sidebar.paletteColor(
    at: WelcomeSidebarIllustrationConstants.uvPaletteIndex
)

// MARK: - Public View

struct WelcomeSidebarIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.loose) {
            ghosttyGroup
            uvGroup
        }
        .padding(16)
        .frame(width: WelcomeSidebarIllustrationConstants.frameWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(AppStyles.General.Fill.muted))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(AppStyles.General.Fill.active), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    // MARK: - Ghostty Group

    private var ghosttyGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoExplorerResolvedGroupHeaderRow(
                isExpanded: true,
                repoTitle: "ghostty",
                organizationName: "ghostty-org"
            )

            VStack(alignment: .leading, spacing: 0) {
                RepoExplorerWorktreeRow(
                    worktree: ghosttyMainWorktree,
                    checkoutTitle: "ghostty",
                    branchName: "main",
                    checkoutIconKind: .mainCheckout,
                    iconColor: ghosttyColor,
                    branchStatus: ghosttyMainStatus,
                    unreadCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyles.Shell.Sidebar.groupChildRowLeadingInset)

                RepoExplorerWorktreeRow(
                    worktree: ghosttyGpuRendererWorktree,
                    checkoutTitle: "ghostty.gpu-renderer",
                    branchName: "feature/gpu-renderer",
                    checkoutIconKind: .gitWorktree,
                    iconColor: ghosttyColor,
                    branchStatus: gpuRendererStatus,
                    unreadCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyles.Shell.Sidebar.groupChildRowLeadingInset)

                RepoExplorerWorktreeRow(
                    worktree: ghosttyFixKeybindsWorktree,
                    checkoutTitle: "ghostty.fix-keybinds",
                    branchName: "fix/keybind-passthrough",
                    checkoutIconKind: .gitWorktree,
                    iconColor: ghosttyColor,
                    branchStatus: fixKeybindsStatus,
                    unreadCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyles.Shell.Sidebar.groupChildRowLeadingInset)
            }
        }
    }

    // MARK: - UV Group

    private var uvGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            RepoExplorerResolvedGroupHeaderRow(
                isExpanded: true,
                repoTitle: "uv",
                organizationName: "astral-sh"
            )

            VStack(alignment: .leading, spacing: 0) {
                RepoExplorerWorktreeRow(
                    worktree: uvMainWorktree,
                    checkoutTitle: "uv",
                    branchName: "main",
                    checkoutIconKind: .mainCheckout,
                    iconColor: uvColor,
                    branchStatus: uvMainStatus,
                    unreadCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyles.Shell.Sidebar.groupChildRowLeadingInset)

                RepoExplorerWorktreeRow(
                    worktree: uvFixResolverWorktree,
                    checkoutTitle: "uv.fix-resolver",
                    branchName: "fix/resolver-perf",
                    checkoutIconKind: .gitWorktree,
                    iconColor: uvColor,
                    branchStatus: fixResolverStatus,
                    unreadCount: 2,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyles.Shell.Sidebar.groupChildRowLeadingInset)
            }
        }
    }
}
