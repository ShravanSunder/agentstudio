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
    var onPaneAction: ((PaneAction) -> Void)?
    var onSaveArrangement: ((UUID) -> Void)?

    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var scrollAreaWidth: CGFloat = 0

    /// Maximum width a tab can grow to.
    private static let tabMaxWidth: CGFloat = 400

    /// Minimum width before overflow/scroll kicks in.
    private static let tabMinWidth: CGFloat = 220

    /// Spacing between tab pills.
    private static let tabSpacing: CGFloat = AppStyle.spacingTight

    /// Computed width for each tab pill based on available space.
    private var computedTabWidth: CGFloat {
        let count = CGFloat(max(1, adapter.tabs.count))
        let totalSpacing = (count - 1) * Self.tabSpacing
        let scrollInset = AppStyle.spacingLoose * 2
        let available = max(0, scrollAreaWidth - totalSpacing - scrollInset)
        let perTab = available / count
        return min(Self.tabMaxWidth, max(Self.tabMinWidth, perTab))
    }

    /// Whether the left gradient fade should be visible (scrolled past the start)
    private var showLeftFade: Bool {
        adapter.isOverflowing && scrollOffset < -5
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // MARK: - Arrangement button (left of all tabs)
                TabBarArrangementButton(
                    adapter: adapter,
                    onPaneAction: onPaneAction,
                    onSaveArrangement: onSaveArrangement
                )
                .padding(.leading, AppStyle.spacingLoose)

                // MARK: - Scroll area with gradient overlays
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppStyle.spacingTight) {
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
                                        tabWidth: computedTabWidth,
                                        showInsertBefore: adapter.dropTargetIndex == index && adapter.draggingTabId != tab.id,
                                        showInsertAfter: index == adapter.tabs.count - 1 && adapter.dropTargetIndex == adapter.tabs.count,
                                        onSelect: { onSelect(tab.id) },
                                        onClose: { onClose(tab.id) },
                                        onCommand: { command in onCommand?(command, tab.id) }
                                    )
                                    .id(tab.id)
                                    .background(frameReporter(for: tab.id))
                                }

                                // Inline + button removed — now in fixed controls zone
                            }
                            .padding(.horizontal, AppStyle.spacingLoose)
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
                                withAnimation(.easeInOut(duration: AppStyle.animationStandard)) {
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

                // MARK: - Fixed controls zone (always visible)
                HStack(spacing: 2) {
                    // Overflow-only controls
                    if adapter.isOverflowing {
                        // Left scroll arrow
                        Button {
                            scrollToAdjacentTab(direction: .left)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Right scroll arrow
                        Button {
                            scrollToAdjacentTab(direction: .right)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
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
                                        Text(tab.displayTitle)
                                        if index < 9 {
                                            Text("  \u{2318}\(index + 1)")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: AppStyle.spacingTight) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: AppStyle.fontSmall, weight: .medium))
                                Text("\(adapter.tabs.count)")
                                    .font(.system(size: AppStyle.fontSmall, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppStyle.spacingLoose)
                            .padding(.vertical, AppStyle.spacingTight)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(AppStyle.fillHover))
                            )
                            .contentShape(Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }

                    // New tab button (always visible)
                    if let onAdd = onAdd {
                        NewTabButton(onAdd: onAdd)
                    }
                }
                .padding(.horizontal, AppStyle.spacingTight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppStyle.tabBarHeight)
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
        .frame(height: AppStyle.tabBarHeight)
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
                withAnimation(.easeInOut(duration: AppStyle.animationStandard)) {
                    proxy.scrollTo(target.id, anchor: .trailing)
                }
            }
        case .left:
            // Find the last tab whose left edge is before the visible scroll area
            if let target = tabs.last(where: { tab in
                guard let frame = adapter.tabFrames[tab.id] else { return false }
                return frame.minX < 0
            }) {
                withAnimation(.easeInOut(duration: AppStyle.animationStandard)) {
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

/// Arrangement button in the tab bar's fixed controls zone.
/// Opens the active tab's arrangement panel popover.
private struct TabBarArrangementButton: View {
    @ObservedObject var adapter: TabBarAdapter
    let onPaneAction: ((PaneAction) -> Void)?
    let onSaveArrangement: ((UUID) -> Void)?

    @State private var showPanel = false
    @State private var isHovered = false

    private var activeTab: TabBarItem? {
        guard let activeId = adapter.activeTabId else { return nil }
        return adapter.tabs.first { $0.id == activeId }
    }

    var body: some View {
        Button {
            showPanel.toggle()
        } label: {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: AppStyle.toolbarButtonSize, height: AppStyle.toolbarButtonSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help("Arrangements")
        .popover(isPresented: $showPanel, arrowEdge: .bottom) {
            if let tab = activeTab, let onPaneAction, let onSaveArrangement {
                ArrangementPanel(
                    tabId: tab.id,
                    panes: tab.panes,
                    arrangements: tab.arrangements,
                    onPaneAction: onPaneAction,
                    onSaveArrangement: { onSaveArrangement(tab.id) }
                )
            }
        }
    }
}

/// Circular "+" button for creating a new tab.
private struct NewTabButton: View {
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: AppStyle.toolbarButtonSize, height: AppStyle.toolbarButtonSize)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help("New Tab")
    }
}

/// Individual pill-shaped tab
struct TabPillView: View {
    let tab: TabBarItem
    let index: Int
    let isActive: Bool
    let isDragging: Bool
    let tabWidth: CGFloat
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
                        Button("Split Left") { onCommand(.splitLeft) }
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
        ZStack {
            // Centered title with fade-out mask.
            // Clear zones match the overlay positions so text is fully invisible
            // behind the shortcut label and close button.
            Text(tab.displayTitle)
                .font(.system(size: AppStyle.fontBody))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .mask(
                    HStack(spacing: 0) {
                        // Left: clear zone for close button + fade-in gradient
                        if isHovering {
                            Color.clear.frame(width: 20)
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 14)
                        } else {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 8)
                        }

                        Color.black

                        // Right: fade-out gradient + clear zone for shortcut label
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 14)
                        if index < 9 {
                            Color.clear.frame(width: 28)
                        }
                    }
                )

            // Close (left) and shortcut (right) overlay
            HStack(spacing: 0) {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AppStyle.fontCaption, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(AppStyle.fillPressed))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                Spacer()

                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: AppStyle.fontSmall, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, AppStyle.spacingStandard)
        .padding(.vertical, AppStyle.spacingStandard)
        .frame(width: tabWidth)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.pillCornerRadius)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppStyle.pillCornerRadius))
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isActive { return Color.white.opacity(AppStyle.fillActive) }
        if isHovering { return Color.white.opacity(AppStyle.fillHover) }
        return Color.white.opacity(AppStyle.fillSubtle)
    }
}

/// Empty state shown when no tabs are open
struct TabBarEmptyState: View {
    var onAddTab: () -> Void

    var body: some View {
        HStack {
            Text("No terminals open")
                .font(.system(size: AppStyle.fontBody))
                .foregroundStyle(.secondary)

            Button(action: onAddTab) {
                HStack(spacing: AppStyle.spacingTight) {
                    Image(systemName: "plus")
                    Text("New Tab")
                }
                .font(.system(size: AppStyle.fontBody))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: AppStyle.tabBarHeight)
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
                onAdd: {},
                onPaneAction: { _ in },
                onSaveArrangement: { _ in }
            )

            Spacer()
        }
        .frame(width: 600, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
