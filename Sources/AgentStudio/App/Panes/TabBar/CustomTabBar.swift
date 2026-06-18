import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
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
    @Bindable var adapter: TabBarAdapter
    @Bindable var arrangementInlineRenameState: ArrangementInlineRenameState
    var onSelect: (UUID) -> Void
    var onClose: (UUID) -> Void
    var onCommand: ((AppCommand, UUID) -> Void)?
    var onTabFramesChanged: (([UUID: CGRect]) -> Void)?
    var onAdd: (() -> Void)?
    var onOpenGitHub: (() -> Void)?
    var onPaneAction: ((PaneActionCommand) -> Void)?
    var onSaveArrangement: ((UUID) -> Void)?
    var onOpenRepoInTab: (() -> Void)?
    var workspaceWindowId: UUID?

    @State private var scrollOffset: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var scrollAreaWidth: CGFloat = 0

    /// Maximum width a tab can grow to.
    private static let tabMaxWidth: CGFloat = 400

    /// Minimum width before overflow/scroll kicks in.
    private static let tabMinWidth: CGFloat = 220

    /// Spacing between tab pills.
    private static let tabSpacing: CGFloat = AppStyles.General.Spacing.tight

    /// Computed width for each tab pill based on available space.
    private var computedTabWidth: CGFloat {
        let count = CGFloat(max(1, adapter.tabs.count))
        let totalSpacing = (count - 1) * Self.tabSpacing
        let scrollInset = AppStyles.General.Spacing.loose * 2
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
                // MARK: - Left-side controls (management layer, arrangement)
                HStack(spacing: AppStyles.General.Spacing.standard) {
                    TabBarManagementLayerButton()

                    TabBarArrangementButton(
                        adapter: adapter,
                        arrangementInlineRenameState: arrangementInlineRenameState,
                        onPaneAction: onPaneAction,
                        onSaveArrangement: onSaveArrangement,
                        workspaceWindowId: workspaceWindowId
                    )
                }
                .padding(.leading, AppStyles.General.Spacing.loose)

                // MARK: - Scroll area with gradient overlays
                ZStack {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppStyles.General.Spacing.tight) {
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
                                        dwellProgress: adapter.dwellTabId == tab.id ? adapter.dwellProgress : 0,
                                        tabWidth: computedTabWidth,
                                        showInsertBefore: adapter.dropTargetIndex == index
                                            && adapter.draggingTabId != tab.id,
                                        showInsertAfter: index == adapter.tabs.count - 1
                                            && adapter.dropTargetIndex == adapter.tabs.count,
                                        onSelect: { onSelect(tab.id) },
                                        onClose: { onClose(tab.id) },
                                        onCommand: { command in onCommand?(command, tab.id) }
                                    )
                                    .id(tab.id)
                                    .background(frameReporter(for: tab.id))
                                }

                                // Inline + button removed — now in fixed controls zone
                            }
                            .padding(.horizontal, AppStyles.General.Spacing.loose)
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
                            if let newId {
                                withAnimation(.easeInOut(duration: AppStyles.General.Animation.standard)) {
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
                                    Color(nsColor: .windowBackgroundColor).opacity(0),
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
                                    Color(nsColor: .windowBackgroundColor),
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
                                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(
                                    width: AppStyles.General.Button.compact,
                                    height: AppStyles.General.Button.compact
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Right scroll arrow
                        Button {
                            scrollToAdjacentTab(direction: .right)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(
                                    width: AppStyles.General.Button.compact,
                                    height: AppStyles.General.Button.compact
                                )
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
                            HStack(spacing: AppStyles.General.Spacing.tight) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                                Text("\(adapter.tabs.count)")
                                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppStyles.General.Spacing.loose)
                            .padding(.vertical, AppStyles.General.Spacing.tight)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(AppStyles.General.Fill.hover))
                            )
                            .contentShape(Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }

                    if let onOpenGitHub {
                        GitHubTabButton(onOpenGitHub: onOpenGitHub)
                    }

                    // New tab button (always visible)
                    if let onAdd {
                        NewTabButton(onAdd: onAdd, onOpenRepoInTab: onOpenRepoInTab)
                    }
                }
                .padding(.horizontal, AppStyles.General.Spacing.tight)
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppStyles.Shell.TabBar.height)
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
        .frame(height: AppStyles.Shell.TabBar.height)
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
                withAnimation(.easeInOut(duration: AppStyles.General.Animation.standard)) {
                    proxy.scrollTo(target.id, anchor: .trailing)
                }
            }
        case .left:
            // Find the last tab whose left edge is before the visible scroll area
            if let target = tabs.last(where: { tab in
                guard let frame = adapter.tabFrames[tab.id] else { return false }
                return frame.minX < 0
            }) {
                withAnimation(.easeInOut(duration: AppStyles.General.Animation.standard)) {
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
                    Task { @MainActor in
                        self.adapter.tabFrames[tabId] = frame
                    }
                    onTabFramesChanged?([tabId: frame])
                }
                .onChange(of: geo.frame(in: .named("tabBar"))) { _, frame in
                    Task { @MainActor in
                        self.adapter.tabFrames[tabId] = frame
                    }
                    onTabFramesChanged?([tabId: frame])
                }
        }
    }
}

private struct GitHubTabButton: View {
    let onOpenGitHub: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpenGitHub()
        } label: {
            Image(systemName: "globe")
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: AppStyles.General.Button.toolbar, height: AppStyles.General.Button.toolbar)
                .background(
                    Circle()
                        .fill(
                            Color.white.opacity(
                                isHovered
                                    ? AppStyles.General.Fill.pressed
                                    : AppStyles.General.Fill.muted
                            )
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(LocalActionSpec.openGitHubInNewTab.actionSpec.helpText)
    }
}

/// Arrangement button in the tab bar's fixed controls zone.
/// Opens the active tab's arrangement panel popover.
private struct TabBarArrangementButton: View {
    @Bindable var adapter: TabBarAdapter
    @Bindable var arrangementInlineRenameState: ArrangementInlineRenameState
    let onPaneAction: ((PaneActionCommand) -> Void)?
    let onSaveArrangement: ((UUID) -> Void)?
    let workspaceWindowId: UUID?

    @State private var presentationState = ArrangementPanelTabPresentationState()
    @State private var isHovered = false
    @State private var popoverToggleGate = PopoverToggleGate()

    private var activeTab: TabBarItem? {
        guard let activeId = adapter.activeTabId else { return nil }
        return adapter.tabs.first { $0.id == activeId }
    }

    private var hiddenMinimizedCount: Int {
        guard activeTab?.showsMinimizedPanes == false else { return 0 }
        guard !atom(\.managementLayer).isActive else { return 0 }
        return activeTab?.minimizedCount ?? 0
    }

    private var activeArrangementBadgeNumber: Int? {
        activeTab?.activeArrangementBadgeNumber
    }

    private var activeArrangementName: String? {
        activeTab?.activeArrangementName
    }

    private var chipNameMaxWidth: CGFloat {
        TabBarArrangementChip.nameMaxWidth(isManagementLayerActive: atom(\.managementLayer).isActive)
    }

    private var presentationAtom: ArrangementPanelPresentationAtom {
        atom(\.arrangementPanelPresentation)
    }

    var body: some View {
        Button {
            var isPresented = presentationState.isPresented
            popoverToggleGate.toggle(isPresented: &isPresented)
            presentationState.setPresented(isPresented, activeTabId: adapter.activeTabId)
        } label: {
            TabBarArrangementChip(
                index: activeArrangementBadgeNumber,
                name: activeArrangementName,
                isHovered: isHovered,
                isPressed: presentationState.isPresented,
                nameMaxWidth: chipNameMaxWidth
            )
            .overlay(alignment: .topTrailing) {
                if hiddenMinimizedCount > 0 {
                    Text("\(hiddenMinimizedCount)")
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppStyles.General.Spacing.tight)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(AppStyles.General.Fill.hover))
                        )
                        .fixedSize()
                        .offset(x: 10, y: -6)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: hiddenMinimizedCount)
            .animation(.easeOut(duration: AppStyles.General.Animation.fast), value: activeArrangementName)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help(LocalActionSpec.arrangements.actionSpec.helpText)
        .popover(
            isPresented: Binding(
                get: { presentationState.isPresented },
                set: { newValue in
                    if !newValue && presentationState.isPresented {
                        presentationState.setPresented(false, activeTabId: adapter.activeTabId)
                        popoverToggleGate.recordSystemDismissal()
                    } else {
                        presentationState.setPresented(newValue, activeTabId: adapter.activeTabId)
                    }
                }
            ),
            attachmentAnchor: ArrangementPanelPopoverPlacement.tabBar.attachmentAnchor,
            arrowEdge: ArrangementPanelPopoverPlacement.tabBar.arrowEdge
        ) {
            if let tab = activeTab, let onPaneAction, let onSaveArrangement {
                ArrangementPanel(
                    tabId: tab.id,
                    workspaceWindowId: workspaceWindowId,
                    panes: tab.panes,
                    arrangements: tab.arrangements,
                    inlineRenameState: arrangementInlineRenameState,
                    onPaneAction: onPaneAction,
                    onSaveArrangement: { onSaveArrangement(tab.id) },
                    onDismiss: dismissArrangementPopover,
                    showsMinimizedPanesBinding: Binding(
                        get: { tab.showsMinimizedPanes },
                        set: { onPaneAction(.setShowsMinimizedPanes(tabId: tab.id, value: $0)) }
                    )
                )
            }
        }
        .onChange(of: arrangementInlineRenameState.editingArrangementId) { _, _ in
            openPopoverIfRenameTargetsActiveTab()
        }
        .onChange(of: adapter.activeTabId) { _, newTabId in
            presentationState.activeTabDidChange(to: newTabId)
            openPopoverIfRenameTargetsActiveTab()
            openPopoverIfRequested()
        }
        .onChange(of: presentationAtom.pendingRequest?.id) { _, _ in
            openPopoverIfRequested()
        }
    }

    private func dismissArrangementPopover() {
        guard presentationState.isPresented else { return }

        presentationState.setPresented(false, activeTabId: adapter.activeTabId)
        popoverToggleGate.recordSystemDismissal()
    }

    private func openPopoverIfRenameTargetsActiveTab() {
        guard
            ArrangementPopoverAutoOpen.shouldOpen(
                editingArrangementId: arrangementInlineRenameState.editingArrangementId,
                activeTabArrangements: activeTab?.arrangements,
                isPresented: presentationState.isPresented
            ),
            let activeTabId = adapter.activeTabId
        else { return }
        presentationState.present(tabId: activeTabId)
    }

    private func openPopoverIfRequested() {
        guard
            let request = presentationAtom.pendingRequest,
            let activeTabId = adapter.activeTabId,
            let workspaceWindowId,
            request.matches(tabId: activeTabId, workspaceWindowId: workspaceWindowId, placement: .tabBar)
        else { return }

        presentationState.present(tabId: request.tabId)
        presentationAtom.consume(request)
    }
}

/// Management layer toggle in the tab bar. Blue accent when active, standard hover otherwise.
private struct TabBarManagementLayerButton: View {
    private var isManagementLayerActive: Bool {
        atom(\.managementLayer).isActive
    }
    @State private var isHovered = false

    var body: some View {
        Button {
            atom(\.managementLayer).toggle()
        } label: {
            Image(
                systemName: isManagementLayerActive
                    ? "rectangle.split.2x2.fill"
                    : "rectangle.split.2x2"
            )
            .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
            .foregroundStyle(
                isManagementLayerActive
                    ? Color.accentColor
                    : (isHovered ? .primary : .secondary)
            )
            .frame(width: AppStyles.General.Button.toolbar, height: AppStyles.General.Button.toolbar)
            .background(
                Circle()
                    .fill(
                        isManagementLayerActive
                            ? Color.accentColor.opacity(AppStyles.General.Fill.active)
                            : Color.white.opacity(
                                isHovered ? AppStyles.General.Fill.pressed : AppStyles.General.Fill.muted)
                    )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(CommandDispatcher.shared.definition(for: .toggleManagementLayer).controlToolTip)
    }
}

/// Circular "+" button for creating a new tab.
/// Click = empty terminal (existing behavior). Right-click = menu with options.
private struct NewTabButton: View {
    let onAdd: () -> Void
    let onOpenRepoInTab: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button(LocalActionSpec.emptyTerminal.actionSpec.label) { onAdd() }
            Divider()
            if let onOpenRepoInTab {
                Button(LocalActionSpec.openRepoWorktree.actionSpec.label) {
                    onOpenRepoInTab()
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(width: AppStyles.General.Button.toolbar, height: AppStyles.General.Button.toolbar)
                .background(
                    Circle()
                        .fill(
                            Color.white.opacity(
                                isHovered
                                    ? AppStyles.General.Fill.pressed
                                    : AppStyles.General.Fill.muted
                            )
                        )
                )
                .contentShape(Circle())
        } primaryAction: {
            onAdd()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(CommandDispatcher.shared.definition(for: .newTab).controlToolTip)
    }
}

/// Individual pill-shaped tab
struct TabPillView: View {
    let tab: TabBarItem
    let index: Int
    let isActive: Bool
    let isDragging: Bool
    let dwellProgress: CGFloat
    let tabWidth: CGFloat
    let showInsertBefore: Bool
    let showInsertAfter: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCommand: (AppCommand) -> Void
    @State private var isHovering = false

    /// Clear zone in the mask for the close button (button frame + buffer).
    private static let closeButtonClearWidth: CGFloat = 20
    /// Clear zone in the mask for the ⌘N shortcut label.
    private static let shortcutLabelClearWidth: CGFloat = 28

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
                    Button(AppCommand.renameTab.definition.label) { onCommand(.renameTab) }

                    Button(AppCommand.closeTab.definition.label) { onCommand(.closeTab) }
                        .keyboardShortcut("w", modifiers: .command)

                    if tab.isSplit {
                        Button(AppCommand.breakUpTab.definition.label) { onCommand(.breakUpTab) }
                    }

                    Divider()

                    Menu(AppCommand.newTerminalInTab.definition.label) {
                        Button(AppCommand.splitRight.definition.label) { onCommand(.splitRight) }
                        Button(AppCommand.splitLeft.definition.label) { onCommand(.splitLeft) }
                    }

                    Button(AppCommand.newFloatingTerminal.definition.label) { onCommand(.newFloatingTerminal) }

                    Divider()

                    if tab.isSplit {
                        Button(AppCommand.equalizePanes.definition.label) { onCommand(.equalizePanes) }
                    }

                    Divider()

                    // Arrangement commands
                    Menu(LocalActionSpec.arrangements.actionSpec.label) {
                        Button(AppCommand.switchArrangement.definition.label) { onCommand(.switchArrangement) }
                        Button(AppCommand.saveArrangement.definition.label) { onCommand(.saveArrangement) }
                        Button(AppCommand.deleteArrangement.definition.label) { onCommand(.deleteArrangement) }
                        Button(AppCommand.renameArrangement.definition.label) { onCommand(.renameArrangement) }
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
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.pill)
                .fill(Color.accentColor.opacity(0.30 * dwellProgress))

            // Centered title with fade-out mask.
            // Clear zones match the overlay positions so text is fully invisible
            // behind the shortcut label and close button.
            Text(tab.displayTitle)
                .font(.system(size: AppStyles.General.Typography.textBase))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .mask(
                    HStack(spacing: 0) {
                        // Left: clear zone for close button + fade-in gradient
                        if isHovering {
                            Color.clear.frame(width: Self.closeButtonClearWidth)
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: AppStyles.Shell.PaneChrome.maskFadeWidth)
                        } else {
                            LinearGradient(
                                colors: [.clear, .black],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: AppStyles.General.Spacing.loose)
                        }

                        Color.black

                        // Right: fade-out gradient + clear zone for shortcut label
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: AppStyles.Shell.PaneChrome.maskFadeWidth)
                        if index < 9 {
                            Color.clear.frame(width: Self.shortcutLabelClearWidth)
                        }
                    }
                )

            // Close (left) and shortcut (right) overlay
            HStack(spacing: 0) {
                if isHovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(AppStyles.General.Fill.pressed))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }

                Spacer()

                if let notificationDotColor = tab.notificationDotColor {
                    Circle()
                        .fill(notificationDotColor.swiftUIColor)
                        .frame(width: 7, height: 7)
                        .accessibilityLabel(notificationDotColor.accessibilityLabel)
                        .padding(.trailing, AppStyles.General.Spacing.tight)
                }

                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: AppStyles.General.Typography.textSm, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, AppStyles.General.Spacing.standard)
        .padding(.vertical, AppStyles.General.Spacing.standard)
        .frame(width: tabWidth)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.pill)
                .fill(backgroundColor)
        )
        .contentShape(RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.pill))
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundColor: Color {
        if isActive { return Color.white.opacity(AppStyles.General.Fill.active) }
        if isHovering { return Color.white.opacity(AppStyles.General.Fill.hover) }
        return Color.white.opacity(AppStyles.General.Fill.subtle)
    }
}

extension TabNotificationDotColor {
    fileprivate var swiftUIColor: Color {
        switch self {
        case .red:
            .red
        case .amber:
            .orange
        case .yellow:
            .yellow
        }
    }

    fileprivate var accessibilityLabel: String {
        switch self {
        case .red:
            "Tab has action notifications"
        case .amber:
            "Tab has safety notifications"
        case .yellow:
            "Tab has settled agent attention"
        }
    }
}

/// Empty state shown when no tabs are open
struct TabBarEmptyState: View {
    var onAddTab: () -> Void

    var body: some View {
        HStack {
            Text("No terminals open")
                .font(.system(size: AppStyles.General.Typography.textBase))
                .foregroundStyle(.secondary)

            Button(action: onAddTab) {
                HStack(spacing: AppStyles.General.Spacing.tight) {
                    Image(systemName: "plus")
                    Text("New Tab")
                }
                .font(.system(size: AppStyles.General.Typography.textBase))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: AppStyles.Shell.TabBar.height)
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
            let adapter = TabBarAdapter(store: store, repoCache: RepoCacheAtom())

            return VStack(spacing: 0) {
                CustomTabBar(
                    adapter: adapter,
                    arrangementInlineRenameState: ArrangementInlineRenameState(),
                    onSelect: { _ in },
                    onClose: { _ in },
                    onCommand: { _, _ in },
                    onAdd: {},
                    onPaneAction: { _ in },
                    onSaveArrangement: { _ in },
                    workspaceWindowId: nil
                )

                Spacer()
            }
            .frame(width: 600, height: 400)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
