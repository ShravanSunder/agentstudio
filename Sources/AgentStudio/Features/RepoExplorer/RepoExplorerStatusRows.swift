import AgentStudioCore
import AgentStudioInfrastructure
import SwiftUI

struct RepoExplorerTopologyFaultRow: View {
    let fault: RepoExplorerTopologyFault

    var body: some View {
        HStack(alignment: .top, spacing: AppStyles.General.Spacing.standard) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: AppStyles.General.Spacing.tight) {
                Text("Repository data unavailable")
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .semibold))
                Text(
                    "Detected \(fault.duplicateIdentityCount) duplicate worktree identity claim(s). Refresh repositories to recover."
                )
                .font(.system(size: AppStyles.General.Typography.textSm))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .allowsHitTesting(false)
    }
}

struct RepoExplorerLoadingSectionHeaderRow: View {
    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: AppStyles.General.Spacing.tight) {
                ProgressView()
                    .controlSize(.small)

                Text("Scanning...")
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, AppStyles.General.Spacing.standard)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RepoExplorerLoadingRepoRow: View {
    let repoName: String

    var body: some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            Text(repoName)
                .font(.system(size: AppStyles.General.Typography.textBase))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.55)
    }
}
