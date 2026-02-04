import SwiftUI
import AppKit

/// Represents a single tab in the tab bar
/// Designed to be extensible for future pane support
struct TabItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var worktreeId: UUID
    // Future: var panes: [PaneItem] for split support
}

/// Observable state for the tab bar
class TabBarState: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var activeTabId: UUID?
    @Published var draggingTabId: UUID?
    @Published var dropTargetIndex: Int?

    /// Tab frames reported from SwiftUI for hit testing in AppKit
    @Published var tabFrames: [UUID: CGRect] = [:]

    func moveTab(fromId: UUID, toIndex: Int) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == fromId }) else { return }
        guard fromIndex != toIndex && toIndex != fromIndex + 1 else { return }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            let tab = tabs.remove(at: fromIndex)
            let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
            tabs.insert(tab, at: max(0, min(adjustedIndex, tabs.count)))
        }
    }
}

/// Custom Ghostty-style tab bar with pill-shaped tabs
struct CustomTabBar: View {
    @ObservedObject var state: TabBarState
    var onSelect: (UUID) -> Void
    var onClose: (UUID) -> Void
    var onTabFramesChanged: (([UUID: CGRect]) -> Void)?
    var onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(state.tabs.enumerated()), id: \.element.id) { index, tab in
                TabPillView(
                    tab: tab,
                    index: index,
                    isActive: tab.id == state.activeTabId,
                    isDragging: state.draggingTabId == tab.id,
                    showInsertBefore: state.dropTargetIndex == index && state.draggingTabId != tab.id,
                    showInsertAfter: index == state.tabs.count - 1 && state.dropTargetIndex == state.tabs.count,
                    onSelect: { onSelect(tab.id) },
                    onClose: { onClose(tab.id) }
                )
                .background(frameReporter(for: tab.id))
            }

            if let onAdd = onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(Color.clear)
        .ignoresSafeArea()
        .coordinateSpace(name: "tabBar")
    }

    private func frameReporter(for tabId: UUID) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    let frame = geo.frame(in: .named("tabBar"))
                    // Update TabBarState directly - more reliable than callback which may have timing issues
                    DispatchQueue.main.async {
                        self.state.tabFrames[tabId] = frame
                    }
                    onTabFramesChanged?([tabId: frame])
                }
                .onChange(of: geo.frame(in: .named("tabBar"))) { _, frame in
                    DispatchQueue.main.async {
                        self.state.tabFrames[tabId] = frame
                    }
                    onTabFramesChanged?([tabId: frame])
                }
        }
    }
}

/// Individual pill-shaped tab
struct TabPillView: View {
    let tab: TabItem
    let index: Int
    let isActive: Bool
    let isDragging: Bool
    let showInsertBefore: Bool
    let showInsertAfter: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            // Insert line BEFORE
            if showInsertBefore {
                insertionLine
            }

            // Tab content
            tabContent
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .opacity(isDragging ? 0.6 : 1.0)

            // Insert line AFTER (only for last tab)
            if showInsertAfter {
                insertionLine
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showInsertBefore)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showInsertAfter)
    }

    private var insertionLine: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 24)
            .padding(.horizontal, 2)
    }

    private var tabContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)

            // Keyboard shortcut hint
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            // Close button on hover
            if isHovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var backgroundColor: Color {
        if isActive { return Color.white.opacity(0.12) }
        if isHovering { return Color.white.opacity(0.06) }
        return Color.clear
    }
}

/// Empty state shown when no tabs are open
struct TabBarEmptyState: View {
    var onAddTab: () -> Void

    var body: some View {
        HStack {
            Text("No terminals open")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button(action: onAddTab) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New Tab")
                }
                .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Preview

#if DEBUG
struct CustomTabBar_Previews: PreviewProvider {
    static var previews: some View {
        let state = TabBarState()
        state.tabs = [
            TabItem(id: UUID(), title: "master", worktreeId: UUID()),
            TabItem(id: UUID(), title: "feature-branch", worktreeId: UUID()),
        ]

        return VStack(spacing: 0) {
            CustomTabBar(
                state: state,
                onSelect: { _ in },
                onClose: { _ in },
                onAdd: {}
            )

            Spacer()
        }
        .frame(width: 600, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
