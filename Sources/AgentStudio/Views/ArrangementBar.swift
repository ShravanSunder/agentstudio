import SwiftUI

/// View-layer data model for a single arrangement chip in the bar.
struct ArrangementBarItem: Identifiable {
    let id: UUID
    let name: String
    let isDefault: Bool
    let paneCount: Int
}

/// Small floating button positioned under the active tab pill.
/// Shows the active arrangement name; click opens the ArrangementPanel popover.
/// Observes TabBarAdapter for reactive positioning and data updates.
struct ArrangementFloatingButton: View {
    @ObservedObject var adapter: TabBarAdapter
    let onPaneAction: (PaneAction) -> Void
    let onSaveArrangement: (UUID) -> Void

    @State private var showPanel = false

    private var activeTab: TabBarItem? {
        guard let activeId = adapter.activeTabId else { return nil }
        return adapter.tabs.first { $0.id == activeId }
    }

    private var activeTabFrame: CGRect? {
        guard let activeId = adapter.activeTabId else { return nil }
        return adapter.tabFrames[activeId]
    }

    private var arrangementName: String {
        activeTab?.activeArrangementName ?? "Default"
    }

    var body: some View {
        GeometryReader { _ in
            if let tab = activeTab, let frame = activeTabFrame {
                Button {
                    showPanel.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 8, weight: .medium))
                        Text(arrangementName)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.black.opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPanel) {
                    ArrangementPanel(
                        tabId: tab.id,
                        panes: tab.panes,
                        arrangements: tab.arrangements,
                        onPaneAction: onPaneAction,
                        onSaveArrangement: { onSaveArrangement(tab.id) }
                    )
                }
                .position(x: frame.midX, y: 10)
            }
        }
        .frame(height: 20)
        .allowsHitTesting(true)
    }
}

/// Individual pill-shaped chip representing a single arrangement.
/// Active state uses a subtle highlight; right-click exposes rename/delete.
struct ArrangementChip: View {
    let name: String
    let isActive: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    let onRename: () -> Void

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.white.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .contextMenu {
                Button("Rename...") { onRename() }
                if let onDelete {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
    }
}
