import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Metrics extracted from onScrollGeometryChange (macOS 15+)
private struct ScrollOverflowMetrics: Equatable {
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
}

/// Applies onScrollGeometryChange on macOS 15+, falls back to GeometryReader on macOS 14.
private struct ScrollOverflowDetector: ViewModifier {
    let adapter: TabBarAdapter

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: ScrollOverflowMetrics.self) { geo in
                    ScrollOverflowMetrics(
                        contentWidth: geo.contentSize.width,
                        viewportWidth: geo.containerSize.width
                    )
                } action: { _, metrics in
                    adapter.contentWidth = metrics.contentWidth
                    adapter.viewportWidth = metrics.viewportWidth
                }
        } else {
            // macOS 14 fallback: measure viewport width on the ScrollView itself
            content
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { adapter.viewportWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in adapter.viewportWidth = w }
                    }
                )
        }
    }
}

/// Custom Ghostty-style tab bar with pill-shaped tabs
struct CustomTabBar: View {
    @ObservedObject var adapter: TabBarAdapter
    var onSelect: (UUID) -> Void
    var onClose: (UUID) -> Void
    var onCommand: ((AppCommand, UUID) -> Void)?
    var onTabFramesChanged: (([UUID: CGRect]) -> Void)?
    var onAdd: (() -> Void)?

    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var scrollAreaWidth: CGFloat = 0

    /// Whether the left gradient fade should be visible (scrolled past the start)
    private var showLeftFade: Bool {
        adapter.isOverflowing && scrollOffset < -5
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // MARK: - Scroll area with gradient overlays
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                // Hidden anchor for scroll offset tracking
                                GeometryReader { innerGeo in
                                    Color.clear.preference(
                                        key: ScrollOffsetKey.self,
                                        value: innerGeo.frame(in: .named("scroll")).minX
                                    )
                                }
                                .frame(width: 0, height: 0)

                                ForEach(Array(adapter.tabs.enumerated()), id: \.element.id) { index, tab in
                                    TabPillView(
                                        tab: tab,
                                        index: index,
                                        isActive: tab.id == adapter.activeTabId,
                                        isDragging: adapter.draggingTabId == tab.id,
                                        showInsertBefore: adapter.dropTargetIndex == index && adapter.draggingTabId != tab.id,
                                        showInsertAfter: index == adapter.tabs.count - 1 && adapter.dropTargetIndex == adapter.tabs.count,
                                        onSelect: { onSelect(tab.id) },
                                        onClose: { onClose(tab.id) },
                                        onCommand: { command in onCommand?(command, tab.id) }
                                    )
                                    .id(tab.id)
                                    .background(frameReporter(for: tab.id))
                                }

                                // Show + button only when NOT overflowing
                                if !adapter.isOverflowing, let onAdd = onAdd {
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
                            }
                            .padding(.horizontal, 8)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ContentWidthKey.self,
                                        value: geo.size.width
                                    )
                                }
                            )
                        }
                        .coordinateSpace(name: "scroll")
                        .modifier(ScrollOverflowDetector(adapter: adapter))
                        .onPreferenceChange(ScrollOffsetKey.self) { offset in
                            scrollOffset = offset
                        }
                        .onPreferenceChange(ContentWidthKey.self) { width in
                            // macOS 14 fallback: onScrollGeometryChange sets this on macOS 15+
                            if adapter.viewportWidth == 0 || adapter.contentWidth == 0 {
                                adapter.contentWidth = width
                            }
                        }
                        .onChange(of: adapter.activeTabId) { _, newId in
                            if let newId = newId {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(newId, anchor: .center)
                                }
                            }
                        }
                        .onAppear {
                            scrollProxy = proxy
                        }
                    }

                    // Left gradient fade
                    if showLeftFade {
                        HStack(spacing: 0) {
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .windowBackgroundColor),
                                    Color(nsColor: .windowBackgroundColor).opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 30)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                    }

                    // Right gradient fade (always visible when overflowing)
                    if adapter.isOverflowing {
                        HStack(spacing: 0) {
                            Spacer()
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .windowBackgroundColor).opacity(0),
                                    Color(nsColor: .windowBackgroundColor)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 30)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { scrollAreaWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in scrollAreaWidth = w }
                    }
                )

                // MARK: - Fixed controls zone (arrows + dropdown)
                if adapter.isOverflowing {
                    HStack(spacing: 2) {
                        // Left scroll arrow
                        Button {
                            scrollToAdjacentTab(direction: .left)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Right scroll arrow
                        Button {
                            scrollToAdjacentTab(direction: .right)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Dropdown with count badge
                        Menu {
                            ForEach(Array(adapter.tabs.enumerated()), id: \.element.id) { index, tab in
                                Button {
                                    onSelect(tab.id)
                                } label: {
                                    HStack {
                                        if tab.id == adapter.activeTabId {
                                            Image(systemName: "checkmark")
                                        }
                                        Image(systemName: tab.isSplit ? "square.split.2x1" : "terminal")
                                        Text(tab.displayTitle)
                                        if index < 9 {
                                            Text("  \u{2318}\(index + 1)")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 10, weight: .medium))
                                Text("\(adapter.tabs.count)")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )
                            .contentShape(Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Color.clear)
            .coordinateSpace(name: "tabBar")
            .ignoresSafeArea()
            .onAppear {
                adapter.availableWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                adapter.availableWidth = newWidth
            }
        }
        .frame(height: 36)
    }

    // MARK: - Scroll Navigation

    private enum ScrollDirection {
        case left, right
    }

    /// Scrolls to the next partially-hidden tab in the given direction.
    /// Uses actual tab frames from the adapter for accurate targeting.
    private func scrollToAdjacentTab(direction: ScrollDirection) {
        guard let proxy = scrollProxy else { return }
        let tabs = adapter.tabs
        guard !tabs.isEmpty else { return }

        switch direction {
        case .right:
            // Find the first tab whose right edge extends beyond the visible scroll area
            if let target = tabs.first(where: { tab in
                guard let frame = adapter.tabFrames[tab.id] else { return false }
                return frame.maxX > scrollAreaWidth
            }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target.id, anchor: .trailing)
                }
            }
        case .left:
            // Find the last tab whose left edge is before the visible scroll area
            if let target = tabs.last(where: { tab in
                guard let frame = adapter.tabFrames[tab.id] else { return false }
                return frame.minX < 0
            }) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(target.id, anchor: .leading)
                }
            }
        }
    }

    // MARK: - Frame Reporter

    private func frameReporter(for tabId: UUID) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    let frame = geo.frame(in: .named("tabBar"))
                    // Update TabBarAdapter directly - more reliable than callback which may have timing issues
                    DispatchQueue.main.async {
                        self.adapter.tabFrames[tabId] = frame
                    }
                    onTabFramesChanged?([tabId: frame])
                }
                .onChange(of: geo.frame(in: .named("tabBar"))) { _, frame in
                    DispatchQueue.main.async {
                        self.adapter.tabFrames[tabId] = frame
                    }
                    onTabFramesChanged?([tabId: frame])
                }
        }
    }
}

/// Individual pill-shaped tab
struct TabPillView: View {
    let tab: TabBarItem
    let index: Int
    let isActive: Bool
    let isDragging: Bool
    let showInsertBefore: Bool
    let showInsertAfter: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCommand: (AppCommand) -> Void

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
                .contextMenu {
                    Button("Close Tab") { onCommand(.closeTab) }
                        .keyboardShortcut("w", modifiers: .command)

                    if tab.isSplit {
                        Button("Break Up Tab") { onCommand(.breakUpTab) }
                    }

                    Divider()

                    Menu("New Terminal in Tab") {
                        Button("Split Right") { onCommand(.splitRight) }
                        Button("Split Below") { onCommand(.splitBelow) }
                        Button("Split Left") { onCommand(.splitLeft) }
                        Button("Split Above") { onCommand(.splitAbove) }
                    }

                    Button("New Floating Terminal") { onCommand(.newFloatingTerminal) }

                    Divider()

                    if tab.isSplit {
                        Button("Equalize Panes") { onCommand(.equalizePanes) }
                    }

                    Divider()

                    // Arrangement commands
                    Menu("Arrangements") {
                        Button("Switch Arrangement...") { onCommand(.switchArrangement) }
                        Button("Save Current As...") { onCommand(.saveArrangement) }
                        Button("Delete Arrangement...") { onCommand(.deleteArrangement) }
                        Button("Rename Arrangement...") { onCommand(.renameArrangement) }
                    }
                }

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
            Image(systemName: tab.isSplit ? "square.split.2x1" : "terminal")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(tab.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isActive ? .primary : .secondary)

            // Arrangement badge (only when custom arrangement active)
            if let arrangementName = tab.activeArrangementName {
                Text("· \(arrangementName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

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
        .frame(minWidth: 100, maxWidth: 220)
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
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "preview-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let store = WorkspaceStore(persistor: persistor)
        store.restore()
        let adapter = TabBarAdapter(store: store)

        return VStack(spacing: 0) {
            CustomTabBar(
                adapter: adapter,
                onSelect: { _ in },
                onClose: { _ in },
                onCommand: { _, _ in },
                onAdd: {}
            )

            Spacer()
        }
        .frame(width: 600, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
