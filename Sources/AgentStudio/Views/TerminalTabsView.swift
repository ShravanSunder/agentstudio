import SwiftUI

struct TerminalTabsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @StateObject private var terminalManager = TerminalManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            TabBarView(
                tabs: sessionManager.openTabs,
                activeTabId: $sessionManager.activeTabId,
                onClose: closeTab
            )

            Divider()

            // Terminal content
            if let activeTabId = sessionManager.activeTabId,
               let tab = sessionManager.openTabs.first(where: { $0.id == activeTabId }),
               let worktree = sessionManager.worktree(for: tab),
               let project = sessionManager.project(for: tab) {
                TerminalView(
                    worktree: worktree,
                    project: project,
                    terminalManager: terminalManager
                )
            } else {
                Text("No terminal selected")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeTabRequested)) { _ in
            if let activeTabId = sessionManager.activeTabId,
               let tab = sessionManager.openTabs.first(where: { $0.id == activeTabId }) {
                closeTab(tab)
            }
        }
    }

    private func closeTab(_ tab: OpenTab) {
        if let worktree = sessionManager.worktree(for: tab) {
            terminalManager.closeTerminal(for: worktree.id)
        }
        sessionManager.closeTab(tab)
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    let tabs: [OpenTab]
    @Binding var activeTabId: UUID?
    let onClose: (OpenTab) -> Void

    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    TabButton(
                        tab: tab,
                        worktree: sessionManager.worktree(for: tab),
                        isActive: tab.id == activeTabId,
                        onSelect: { activeTabId = tab.id },
                        onClose: { onClose(tab) }
                    )
                }

                Button(action: showWorktreePicker) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func showWorktreePicker() {
        NotificationCenter.default.post(name: .newTabRequested, object: nil)
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let tab: OpenTab
    let worktree: Worktree?
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Agent status indicator
            if let worktree, let agent = worktree.agent {
                Circle()
                    .fill(agent.color)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }

            Text(worktree?.name ?? "Unknown")
                .lineLimit(1)
                .font(.system(size: 12))

            // Close button
            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            } else {
                Spacer()
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.15) : (isHovering ? Color.secondary.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
    }
}
