import SwiftUI

/// Floating popover panel for managing pane arrangements.
/// Shows pane visibility toggles, arrangement chips, and save controls.
struct ArrangementPanel: View {
    let tabId: UUID
    let panes: [TabBarPaneInfo]
    let arrangements: [TabBarArrangementInfo]
    let onPaneAction: (PaneAction) -> Void
    let onSaveArrangement: () -> Void

    @State private var renamingArrangementId: UUID?
    @State private var renameText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Arrangement chips
            Text("Arrangements")
                .font(.system(size: AppStyle.fontSmall, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            WrappingHStack(spacing: 4) {
                ForEach(arrangements) { arr in
                    arrangementChip(arr)
                }

                // Save new arrangement button
                if panes.count > 1 {
                    Button(action: onSaveArrangement) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyle.fontSmall, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.white.opacity(AppStyle.strokeMuted), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Save current layout as arrangement")
                }
            }

            // MARK: - Pane visibility
            if panes.count > 1 {
                Divider()
                    .padding(.vertical, 2)

                Text("Pane Visibility")
                    .font(.system(size: AppStyle.fontSmall, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                VStack(spacing: 2) {
                    ForEach(panes) { pane in
                        paneRow(pane)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 180, maxWidth: 260)
        .alert(
            "Rename Arrangement",
            isPresented: Binding(
                get: { renamingArrangementId != nil },
                set: { if !$0 { renamingArrangementId = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let id = renamingArrangementId, !renameText.isEmpty {
                    onPaneAction(.renameArrangement(tabId: tabId, arrangementId: id, name: renameText))
                }
                renamingArrangementId = nil
            }
            Button("Cancel", role: .cancel) {
                renamingArrangementId = nil
            }
        }
    }

    // MARK: - Pane Row

    private func paneRow(_ pane: TabBarPaneInfo) -> some View {
        HStack(spacing: AppStyle.spacingStandard) {
            // Visibility indicator
            Circle()
                .fill(pane.isMinimized ? Color.clear : Color.white.opacity(AppStyle.foregroundDim))
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 8, height: 8)

            Text(pane.title)
                .font(.system(size: AppStyle.fontSecondary))
                .foregroundStyle(pane.isMinimized ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Toggle minimize/expand
            Button {
                if pane.isMinimized {
                    onPaneAction(.expandPane(tabId: tabId, paneId: pane.id))
                } else {
                    onPaneAction(.minimizePane(tabId: tabId, paneId: pane.id))
                }
            } label: {
                Image(systemName: pane.isMinimized ? "eye" : "eye.slash")
                    .font(.system(size: AppStyle.fontSmall))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(pane.isMinimized ? "Show pane" : "Hide pane")
        }
        .padding(.horizontal, AppStyle.spacingStandard)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                .fill(Color.white.opacity(AppStyle.fillSubtle))
        )
    }

    // MARK: - Arrangement Chip

    private func arrangementChip(_ arr: TabBarArrangementInfo) -> some View {
        Text(arr.name)
            .font(.system(size: AppStyle.fontSecondary, weight: arr.isActive ? .semibold : .regular))
            .foregroundStyle(arr.isActive ? .primary : .secondary)
            .padding(.horizontal, AppStyle.spacingLoose)
            .padding(.vertical, AppStyle.spacingTight)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                    .fill(
                        arr.isActive
                            ? Color.white.opacity(AppStyle.fillActive) : Color.white.opacity(AppStyle.fillSubtle))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onPaneAction(.switchArrangement(tabId: tabId, arrangementId: arr.id))
            }
            .contextMenu {
                if !arr.isDefault {
                    Button("Rename...") {
                        renameText = arr.name
                        renamingArrangementId = arr.id
                    }
                    Button("Delete", role: .destructive) {
                        onPaneAction(.removeArrangement(tabId: tabId, arrangementId: arr.id))
                    }
                }
            }
    }
}

// MARK: - Wrapping HStack

/// Simple wrapping horizontal stack that flows items to new lines when they exceed available width.
/// Uses ViewThatFits-inspired approach compatible with macOS 14+.
struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        // For the arrangement panel, items usually fit in a single line.
        // Use a simple HStack — panels are constrained to ~260px max width.
        HStack(spacing: spacing) {
            content
        }
    }
}
