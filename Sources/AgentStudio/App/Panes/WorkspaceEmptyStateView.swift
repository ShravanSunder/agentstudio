import SwiftUI

struct WorkspaceEmptyStateView: View {
    let model: WorkspaceEmptyStateModel
    let onAddFolder: () -> Void
    let onOpenRecent: (RecentWorkspaceTarget) -> Void
    let onOpenAllRecent: () -> Void

    var body: some View {
        switch model.kind {
        case .noFolders:
            noFoldersState
        case .launcher:
            launcherState
        }
    }

    private var noFoldersState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 84, height: 84)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(spacing: 8) {
                Text("Add a folder to scan for repos")
                    .font(.system(size: 22, weight: .semibold))
                Text("Start by selecting a parent folder. AgentStudio will scan it and add any repositories it finds.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button("Add Folder...") {
                onAddFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Add folder to scan for repos")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var launcherState: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 80, height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(spacing: 6) {
                Text("Workspace ready")
                    .font(.system(size: 22, weight: .semibold))
                Text(
                    "Open one of your recent worktrees or CWDs, open all recent targets in tabs, or scan another folder for repos."
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            }

            if model.recentTargets.isEmpty {
                Text("No recent targets yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(model.recentTargets) { target in
                        Button {
                            onOpenRecent(target)
                        } label: {
                            HStack(spacing: 10) {
                                Image(
                                    systemName: target.kind == .worktree
                                        ? "point.3.connected.trianglepath.dotted" : "terminal"
                                )
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.displayTitle)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    Text(target.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 520)
            }

            HStack(spacing: 10) {
                if model.showsOpenAll {
                    Button("Open All in Tabs") {
                        onOpenAllRecent()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button("Add Folder...") {
                    onAddFolder()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("Add folder to scan for repos")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
