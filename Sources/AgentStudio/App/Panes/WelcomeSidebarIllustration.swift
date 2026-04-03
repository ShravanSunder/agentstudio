import SwiftUI

// MARK: - Illustration Data Types

private struct IllustrationWorktree {
    let checkoutTitle: String
    let branchName: String
    let isMainWorktree: Bool
    let chips: IllustrationChips?
}

private struct IllustrationChips {
    let branchStatus: GitBranchStatus
    let notificationCount: Int
}

private struct IllustrationGroup {
    let repoTitle: String
    let organizationName: String
    let accentColor: Color
    let isExpanded: Bool
    let worktrees: [IllustrationWorktree]
}

// MARK: - Sample Data

private let illustrationGroups: [IllustrationGroup] = [
    IllustrationGroup(
        repoTitle: "react",
        organizationName: "facebook",
        accentColor: Color(red: 0.49, green: 0.54, blue: 0.97),
        isExpanded: true,
        worktrees: [
            IllustrationWorktree(
                checkoutTitle: "react",
                branchName: "main",
                isMainWorktree: true,
                chips: nil
            ),
            IllustrationWorktree(
                checkoutTitle: "react.concurrent-mode",
                branchName: "feature/concurrent-mode",
                isMainWorktree: false,
                chips: IllustrationChips(
                    branchStatus: GitBranchStatus(
                        isDirty: true,
                        syncState: .diverged(ahead: 2, behind: 1),
                        prCount: 1,
                        linesAdded: 42,
                        linesDeleted: 8
                    ),
                    notificationCount: 0
                )
            ),
        ]
    ),
    IllustrationGroup(
        repoTitle: "uv",
        organizationName: "astral-sh",
        accentColor: Color(red: 0.35, green: 0.79, blue: 0.56),
        isExpanded: true,
        worktrees: [
            IllustrationWorktree(
                checkoutTitle: "uv",
                branchName: "main",
                isMainWorktree: true,
                chips: nil
            ),
            IllustrationWorktree(
                checkoutTitle: "uv.fix-resolver",
                branchName: "fix/resolver-perf",
                isMainWorktree: false,
                chips: IllustrationChips(
                    branchStatus: GitBranchStatus(
                        isDirty: false,
                        syncState: .ahead(1),
                        prCount: 1,
                        linesAdded: 12,
                        linesDeleted: 3
                    ),
                    notificationCount: 2
                )
            ),
        ]
    ),
    IllustrationGroup(
        repoTitle: "ghostty",
        organizationName: "ghostty-org",
        accentColor: Color.secondary,
        isExpanded: false,
        worktrees: []
    ),
]

// MARK: - Public View

struct WelcomeSidebarIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.spacingLoose) {
            ForEach(Array(illustrationGroups.enumerated()), id: \.offset) { _, group in
                IllustrationGroupView(group: group)
            }
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
    }
}

// MARK: - Group View

private struct IllustrationGroupView: View {
    let group: IllustrationGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader

            if group.isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.worktrees.enumerated()), id: \.offset) { _, worktree in
                        IllustrationWorktreeRow(worktree: worktree, accentColor: group.accentColor)
                            .padding(.leading, AppStyle.sidebarGroupChildRowLeadingInset)
                    }
                }
            }
        }
    }

    private var groupHeader: some View {
        HStack(spacing: AppStyle.spacingTight) {
            Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: AppStyle.textXs, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: AppStyle.textBase, alignment: .center)

            HStack(spacing: AppStyle.spacingStandard) {
                WorkspaceOcticonImage(name: "octicon-repo", size: AppStyle.sidebarGroupIconSize)
                    .foregroundStyle(.secondary)

                HStack(spacing: AppStyle.sidebarGroupTitleSpacing) {
                    Text(group.repoTitle)
                        .font(.system(size: AppStyle.textLg, weight: .semibold))
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: AppStyle.textSm, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(group.organizationName)
                        .font(.system(size: AppStyle.sidebarGroupOrganizationFontSize, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, AppStyle.sidebarGroupRowVerticalPadding)
    }
}

// MARK: - Worktree Row

private struct IllustrationWorktreeRow: View {
    let worktree: IllustrationWorktree
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sidebarRowContentSpacing) {
            // Checkout title row
            HStack(spacing: AppStyle.spacingTight) {
                worktreeIcon
                    .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                Text(worktree.checkoutTitle)
                    .font(.system(size: AppStyle.textBase, weight: worktree.isMainWorktree ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Branch name row
            HStack(spacing: AppStyle.spacingTight) {
                WorkspaceOcticonImage(name: "octicon-git-branch", size: AppStyle.sidebarBranchIconSize)
                    .foregroundStyle(.secondary)
                    .frame(width: AppStyle.sidebarRowLeadingIconColumnWidth, alignment: .leading)

                Text(worktree.branchName)
                    .font(.system(size: AppStyle.sidebarBranchFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Status chips (only for worktrees with interesting status)
            if let chips = worktree.chips {
                WorkspaceStatusChipRow(
                    model: WorkspaceStatusChipsModel(
                        branchStatus: chips.branchStatus,
                        notificationCount: chips.notificationCount
                    ),
                    accentColor: accentColor
                )
                .padding(.leading, AppStyle.sidebarStatusRowLeadingIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, AppStyle.sidebarRowVerticalInset)
    }

    @ViewBuilder
    private var worktreeIcon: some View {
        if worktree.isMainWorktree {
            WorkspaceOcticonImage(name: "octicon-star-fill", size: AppStyle.textBase)
                .foregroundStyle(accentColor)
        } else {
            WorkspaceOcticonImage(name: "octicon-git-worktree", size: AppStyle.textBase)
                .foregroundStyle(accentColor)
                .rotationEffect(.degrees(180))
        }
    }
}
