import SwiftUI

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

private let cleanStatus = GitBranchStatus(
    isDirty: false,
    syncState: .synced,
    prCount: 0,
    linesAdded: 0,
    linesDeleted: 0
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

private func paletteColor(at index: Int) -> Color {
    Color(nsColor: NSColor(hex: AppStyle.accentPaletteHexes[index]) ?? .controlAccentColor)
}

private let ghosttyColor = paletteColor(at: 0)
private let uvColor = paletteColor(at: 3)

// MARK: - Public View

struct WelcomeSidebarIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.spacingLoose) {
            ghosttyGroup
            uvGroup
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(AppStyle.fillMuted))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(AppStyle.fillActive), lineWidth: 1)
        )
        .allowsHitTesting(false)
    }

    // MARK: - Ghostty Group

    private var ghosttyGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarResolvedGroupHeaderRow(
                isExpanded: true,
                repoTitle: "ghostty",
                organizationName: "ghostty-org"
            )

            VStack(alignment: .leading, spacing: 0) {
                SidebarWorktreeRow(
                    worktree: ghosttyMainWorktree,
                    checkoutTitle: "ghostty",
                    branchName: "main",
                    checkoutIconKind: .mainCheckout,
                    iconColor: ghosttyColor,
                    branchStatus: cleanStatus,
                    notificationCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyle.sidebarGroupChildRowLeadingInset)

                SidebarWorktreeRow(
                    worktree: ghosttyGpuRendererWorktree,
                    checkoutTitle: "ghostty.gpu-renderer",
                    branchName: "feature/gpu-renderer",
                    checkoutIconKind: .gitWorktree,
                    iconColor: ghosttyColor,
                    branchStatus: gpuRendererStatus,
                    notificationCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyle.sidebarGroupChildRowLeadingInset)

                SidebarWorktreeRow(
                    worktree: ghosttyFixKeybindsWorktree,
                    checkoutTitle: "ghostty.fix-keybinds",
                    branchName: "fix/keybind-passthrough",
                    checkoutIconKind: .gitWorktree,
                    iconColor: ghosttyColor,
                    branchStatus: fixKeybindsStatus,
                    notificationCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyle.sidebarGroupChildRowLeadingInset)
            }
        }
    }

    // MARK: - UV Group

    private var uvGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarResolvedGroupHeaderRow(
                isExpanded: true,
                repoTitle: "uv",
                organizationName: "astral-sh"
            )

            VStack(alignment: .leading, spacing: 0) {
                SidebarWorktreeRow(
                    worktree: uvMainWorktree,
                    checkoutTitle: "uv",
                    branchName: "main",
                    checkoutIconKind: .mainCheckout,
                    iconColor: uvColor,
                    branchStatus: cleanStatus,
                    notificationCount: 0,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyle.sidebarGroupChildRowLeadingInset)

                SidebarWorktreeRow(
                    worktree: uvFixResolverWorktree,
                    checkoutTitle: "uv.fix-resolver",
                    branchName: "fix/resolver-perf",
                    checkoutIconKind: .gitWorktree,
                    iconColor: uvColor,
                    branchStatus: fixResolverStatus,
                    notificationCount: 2,
                    onOpen: {},
                    onOpenNew: {},
                    onOpenInPane: {},
                    onSetIconColor: { _ in }
                )
                .padding(.leading, AppStyle.sidebarGroupChildRowLeadingInset)
            }
        }
    }
}
