import SwiftUI

// MARK: - TrapezoidConnector

/// Rectangle bridge that visually connects a pane to its drawer icon bar.
/// Full pane width — the panel-to-pane taper is handled by DrawerOverlayTrapezoid
/// at the tab level, so this connector stays at pane width to match pane borders.
struct TrapezoidConnector: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect)
    }
}

private enum DrawerTooltipTarget: Hashable {
    case toggle
    case add
    case finder
    case copyPath
    case chooser
    case inbox
    case emptyAdd
    case paneSurfaceAction(String)
}

// MARK: - DrawerIconBar

enum DrawerIconBarLeadingControls {
    case drawer(
        isExpanded: Bool,
        onAdd: @MainActor @Sendable () -> Void,
        onToggleExpand: @MainActor @Sendable () -> Void
    )
    case hidden
}

/// Icon bar at the bottom of a pane showing drawer controls.
/// Layout: [toggle] | [+]
///
/// Toggle uses `sidebar.bottom` (macOS convention for bottom panel toggle).
/// Follows the same callback-driven pattern as `ArrangementBar`.
struct DrawerIconBar: View {
    let leadingControls: DrawerIconBarLeadingControls
    let trailingActions: DrawerOverlay.TrailingActions?
    let paneSurfaceActions: [PaneSurfaceToolbarAction]
    let paneContextActions: [PaneSurfaceToolbarAction]

    @State private var isAddHovered = false
    @State private var isToggleHovered = false
    @State private var isFinderHovered = false
    @State private var isCopyPathHovered = false
    @State private var isChooserHovered = false
    @State private var isInboxHovered = false
    @State private var hoveredPaneSurfaceActionId: String?
    @State private var tooltipFrames: [DrawerTooltipTarget: CGRect] = [:]

    init(
        isExpanded: Bool,
        onAdd: @escaping @MainActor @Sendable () -> Void,
        onToggleExpand: @escaping @MainActor @Sendable () -> Void,
        trailingActions: DrawerOverlay.TrailingActions?,
        paneSurfaceActions: [PaneSurfaceToolbarAction] = [],
        paneContextActions: [PaneSurfaceToolbarAction] = []
    ) {
        leadingControls = .drawer(
            isExpanded: isExpanded,
            onAdd: onAdd,
            onToggleExpand: onToggleExpand
        )
        self.trailingActions = trailingActions
        self.paneSurfaceActions = paneSurfaceActions
        self.paneContextActions = paneContextActions
    }

    init(
        leadingControls: DrawerIconBarLeadingControls,
        trailingActions: DrawerOverlay.TrailingActions?,
        paneSurfaceActions: [PaneSurfaceToolbarAction] = [],
        paneContextActions: [PaneSurfaceToolbarAction] = []
    ) {
        self.leadingControls = leadingControls
        self.trailingActions = trailingActions
        self.paneSurfaceActions = paneSurfaceActions
        self.paneContextActions = paneContextActions
    }

    private enum TrailingActionIcon {
        case system(name: String)
        case octicon(name: String)
    }

    private static let tooltipCoordinateSpaceName = "drawerTooltipBar"

    private var isExpanded: Bool {
        guard case .drawer(let isExpanded, _, _) = leadingControls else {
            return false
        }
        return isExpanded
    }

    private var toggleToolTip: ControlTooltipRenderValue {
        AppCommand.toggleDrawer.definition.controlTooltipRenderValue(
            textOverride: isExpanded ? "Collapse Drawer" : "Expand Drawer"
        )
    }

    private var addToolTip: ControlTooltipRenderValue {
        AppCommand.addDrawerPane.definition.controlTooltipRenderValue()
    }

    private var finderToolTip: ControlTooltipRenderValue {
        AppCommand.openPaneLocationInFinder.definition.controlTooltipRenderValue(
            textOverride: "Open in Finder"
        )
    }

    private var copyPathToolTip: ControlTooltipRenderValue {
        AppCommand.copyCurrentPanePath.definition.controlTooltipRenderValue(
            textOverride: "Copy Path"
        )
    }

    private var chooserToolTip: ControlTooltipRenderValue {
        AppCommand.openPaneLocationInEditorMenu.definition.controlTooltipRenderValue(
            textOverride: "Open in Editor"
        )
    }

    private var inboxToolTip: ControlTooltipRenderValue {
        AppCommand.showPaneInboxNotifications.definition.controlTooltipRenderValue(
            textOverride: "Open pane inbox"
        )
    }

    var body: some View {
        let finderPresentation = LocalActionSpec.openPaneLocationInFinder.actionSpec
        let copyPathPresentation = LocalActionSpec.copyPath.actionSpec

        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: DrawerLayout.iconBarCornerRadius)
                        .fill(.ultraThinMaterial)

                    HStack(spacing: 0) {
                        if !paneSurfaceActions.isEmpty {
                            HStack(spacing: AppStyles.Shell.DrawerToolbar.trailingClusterSpacing) {
                                ForEach(Array(paneSurfaceActions.enumerated()), id: \.offset) { _, action in
                                    paneSurfaceActionButton(action)
                                }
                            }

                            if case .drawer = leadingControls {
                                drawerToolbarDivider
                            }
                        }

                        if case .drawer(_, let onAdd, let onToggleExpand) = leadingControls {
                            HStack(spacing: AppStyles.Shell.DrawerToolbar.trailingClusterSpacing) {
                                Button(action: onToggleExpand) {
                                    Image(systemName: "rectangle.bottomhalf.filled")
                                        .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                                        .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(isExpanded ? .primary : (isToggleHovered ? .primary : .secondary))
                                .background(
                                    RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                                        .fill(
                                            isExpanded
                                                ? Color.white.opacity(AppStyles.General.Fill.active)
                                                : (isToggleHovered
                                                    ? Color.white.opacity(AppStyles.General.Fill.hover)
                                                    : Color.clear))
                                )
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                        isToggleHovered = hovering
                                    }
                                }
                                .hoverTooltipAnchor(DrawerTooltipTarget.toggle, in: Self.tooltipCoordinateSpaceName)
                                .controlHelp(toggleToolTip)
                                .accessibilityHidden(true)
                                .background {
                                    AccessibilityPressBridge(
                                        identifier: "paneSurfaceToolbar.drawerToggle",
                                        label: isExpanded ? "Collapse Drawer" : "Expand Drawer",
                                        action: onToggleExpand
                                    )
                                }

                                Button(action: onAdd) {
                                    Image(systemName: "plus")
                                        .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                                        .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(isAddHovered ? .primary : .secondary)
                                .background(
                                    RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                                        .fill(
                                            isAddHovered
                                                ? Color.white.opacity(AppStyles.General.Fill.hover)
                                                : Color.clear)
                                )
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                        isAddHovered = hovering
                                    }
                                }
                                .hoverTooltipAnchor(DrawerTooltipTarget.add, in: Self.tooltipCoordinateSpaceName)
                                .controlHelp(addToolTip)
                                .accessibilityHidden(true)
                                .background {
                                    AccessibilityPressBridge(
                                        identifier: "paneSurfaceToolbar.drawerAdd",
                                        label: AppCommand.addDrawerPane.definition.label,
                                        action: onAdd
                                    )
                                }
                            }
                        }

                        Spacer()

                        if let trailingActions {
                            HStack(spacing: 0) {
                                HStack(spacing: AppStyles.Shell.DrawerToolbar.trailingClusterSpacing) {
                                    ForEach(Array(paneContextActions.enumerated()), id: \.offset) { _, action in
                                        paneSurfaceActionButton(action)
                                    }

                                    Button {
                                        trailingActions.editorMenuPresented.wrappedValue.toggle()
                                    } label: {
                                        HStack(spacing: AppStyles.Components.EditorChooser.chooserButtonContentSpacing)
                                        {
                                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                                            if let buttonTitle = trailingActions.buttonTitle {
                                                Text(buttonTitle)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(
                                                    .system(
                                                        size: AppStyles.Components.EditorChooser.chooserChevronFontSize,
                                                        weight: .semibold
                                                    )
                                                )
                                        }
                                        .frame(height: DrawerLayout.iconButtonSize)
                                        .padding(
                                            .horizontal,
                                            AppStyles.Components.EditorChooser.chooserButtonHorizontalPadding
                                        )
                                        .background(
                                            RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                                                .fill(
                                                    isChooserHovered
                                                        ? Color.primary.opacity(AppStyles.General.Fill.hover)
                                                        : Color.clear
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .popover(
                                        isPresented: trailingActions.editorMenuPresented,
                                        arrowEdge: .bottom
                                    ) {
                                        trailingActions.editorMenuContent
                                    }
                                    .disabled(!trailingActions.canOpenTarget)
                                    .controlHelp(chooserToolTip)
                                    .accessibilityHidden(true)
                                    .background {
                                        AccessibilityPressBridge(
                                            identifier: "paneSurfaceToolbar.editor",
                                            label: "Open in Editor",
                                            isEnabled: trailingActions.canOpenTarget
                                        ) {
                                            trailingActions.editorMenuPresented.wrappedValue.toggle()
                                        }
                                    }
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                            isChooserHovered = hovering
                                        }
                                    }
                                    .hoverTooltipAnchor(
                                        DrawerTooltipTarget.chooser, in: Self.tooltipCoordinateSpaceName)
                                }

                                trailingActionDivider

                                HStack(spacing: AppStyles.Shell.DrawerToolbar.trailingClusterSpacing) {
                                    trailingActionButton(
                                        icon: trailingActionIcon(for: finderPresentation.icon),
                                        helpValue: finderToolTip,
                                        isHovered: isFinderHovered,
                                        action: trailingActions.onOpenFinder
                                    )
                                    .disabled(!trailingActions.canOpenTarget)
                                    .accessibilityHidden(true)
                                    .background {
                                        AccessibilityPressBridge(
                                            identifier: "paneSurfaceToolbar.finder",
                                            label: "Open in Finder",
                                            isEnabled: trailingActions.canOpenTarget
                                        ) {
                                            trailingActions.onOpenFinder()
                                        }
                                    }
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                            isFinderHovered = hovering
                                        }
                                    }
                                    .hoverTooltipAnchor(DrawerTooltipTarget.finder, in: Self.tooltipCoordinateSpaceName)

                                    trailingActionButton(
                                        icon: trailingActionIcon(for: copyPathPresentation.icon),
                                        helpValue: copyPathToolTip,
                                        isHovered: isCopyPathHovered,
                                        action: trailingActions.onCopyPath
                                    )
                                    .disabled(!trailingActions.canOpenTarget)
                                    .accessibilityHidden(true)
                                    .background {
                                        AccessibilityPressBridge(
                                            identifier: "paneSurfaceToolbar.copyPath",
                                            label: "Copy Path",
                                            isEnabled: trailingActions.canOpenTarget
                                        ) {
                                            trailingActions.onCopyPath()
                                        }
                                    }
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                            isCopyPathHovered = hovering
                                        }
                                    }
                                    .hoverTooltipAnchor(
                                        DrawerTooltipTarget.copyPath,
                                        in: Self.tooltipCoordinateSpaceName
                                    )
                                }

                                if let onOpenInbox = trailingActions.onOpenInbox {
                                    trailingActionDivider

                                    trailingActionButton(
                                        icon: .system(name: "bell.fill"),
                                        helpValue: inboxToolTip,
                                        isHovered: isInboxHovered,
                                        action: onOpenInbox
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if let inboxUnreadBadge = trailingActions.inboxUnreadBadge {
                                            UnreadCountBadge(text: inboxUnreadBadge.text)
                                                .offset(
                                                    x: AppStyles.Components.NotificationBadge.offset,
                                                    y: -AppStyles.Components.NotificationBadge.offset
                                                )
                                        }
                                    }
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                            isInboxHovered = hovering
                                        }
                                    }
                                    .hoverTooltipAnchor(DrawerTooltipTarget.inbox, in: Self.tooltipCoordinateSpaceName)
                                    .popover(
                                        isPresented: trailingActions.inboxPopoverPresented,
                                        arrowEdge: .bottom
                                    ) {
                                        trailingActions.inboxPopoverContent
                                    }
                                    .accessibilityHidden(true)
                                    .background {
                                        AccessibilityPressBridge(
                                            identifier: "paneSurfaceToolbar.inbox",
                                            label: "Open pane inbox"
                                        ) {
                                            onOpenInbox()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(DrawerLayout.iconBarVerticalPadding)

                    FloatingHoverTooltipPresenter(
                        activeTarget: activeTooltipTarget,
                        anchorFrames: tooltipFrames,
                        availableWidth: geo.size.width,
                        tooltipValue: tooltipValue(for:)
                    )
                }
                .coordinateSpace(name: Self.tooltipCoordinateSpaceName)
                .onPreferenceChange(HoverTooltipAnchorPreferenceKey<DrawerTooltipTarget>.self) { tooltipFrames = $0 }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DrawerIconBarFrameKey.self,
                        value: geo.frame(in: .named("tabContainer"))
                    )
                }
            )
            .frame(height: DrawerLayout.iconButtonSize + (DrawerLayout.iconBarVerticalPadding * 2))
        }
    }

    private var trailingActionDivider: some View {
        drawerToolbarDivider
    }

    private var drawerToolbarDivider: some View {
        Divider()
            .frame(height: AppStyles.Shell.DrawerToolbar.dividerHeight)
            .padding(.horizontal, AppStyles.Shell.DrawerToolbar.dividerHorizontalPadding)
    }

    private var activeTooltipTarget: DrawerTooltipTarget? {
        if trailingActions?.editorMenuPresented.wrappedValue == true { return nil }
        if isToggleHovered { return .toggle }
        if isAddHovered { return .add }
        if isChooserHovered { return .chooser }
        if isFinderHovered { return .finder }
        if isCopyPathHovered { return .copyPath }
        if isInboxHovered { return .inbox }
        if let hoveredPaneSurfaceActionId {
            return .paneSurfaceAction(hoveredPaneSurfaceActionId)
        }
        return nil
    }

    private func tooltipValue(for target: DrawerTooltipTarget) -> ControlTooltipRenderValue? {
        switch target {
        case .toggle:
            return toggleToolTip
        case .add:
            return addToolTip
        case .finder:
            return finderToolTip
        case .copyPath:
            return copyPathToolTip
        case .chooser:
            return chooserToolTip
        case .inbox:
            return inboxToolTip
        case .emptyAdd:
            return nil
        case .paneSurfaceAction(let accessibilityIdentifier):
            return (paneSurfaceActions + paneContextActions).first {
                $0.state.accessibilityIdentifier == accessibilityIdentifier
            }?.state.tooltip
        }
    }

    private func trailingActionIcon(for descriptor: CommandIcon) -> TrailingActionIcon {
        switch descriptor {
        case .system(let name):
            return .system(name: name.rawValue)
        case .octicon(let name):
            return .octicon(name: name.rawValue)
        }
    }

    private func trailingActionButton(
        icon: TrailingActionIcon,
        helpValue: ControlTooltipRenderValue,
        isHovered: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                switch icon {
                case .system(let systemName):
                    Image(systemName: systemName)
                        .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                case .octicon(let octiconName):
                    OcticonImage(name: octiconName, size: AppStyles.General.Icon.compact)
                }
            }
            .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .background(
            RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                .fill(isHovered ? Color.white.opacity(AppStyles.General.Fill.hover) : Color.clear)
        )
        .controlHelp(helpValue)
    }

    private func paneSurfaceActionButton(_ action: PaneSurfaceToolbarAction) -> some View {
        let isHovered = hoveredPaneSurfaceActionId == action.state.accessibilityIdentifier

        return Button(action: action.perform) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                paneSurfaceActionIcon(action.state.icon)
                    .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)

                if let visibleLabel = action.state.visibleLabel {
                    Text(visibleLabel)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                        .lineLimit(1)
                }
            }
            .frame(height: DrawerLayout.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(action.state.isSelected || isHovered ? .primary : .secondary)
        .background(
            RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                .fill(
                    action.state.isSelected
                        ? Color.white.opacity(AppStyles.General.Fill.active)
                        : (isHovered
                            ? Color.white.opacity(AppStyles.General.Fill.hover)
                            : Color.clear)
                )
        )
        .disabled(!action.state.isEnabled)
        .hoverTooltipAnchor(
            DrawerTooltipTarget.paneSurfaceAction(action.state.accessibilityIdentifier),
            in: Self.tooltipCoordinateSpaceName
        )
        .controlHelp(action.state.tooltip)
        .accessibilityHidden(true)
        .background {
            AccessibilityPressBridge(
                identifier: action.state.accessibilityIdentifier,
                label: action.state.label,
                isEnabled: action.state.isEnabled,
                action: action.perform
            )
        }
        .onHover { hovering in
            hoveredPaneSurfaceActionId = hovering ? action.state.accessibilityIdentifier : nil
        }
    }

    @ViewBuilder
    private func paneSurfaceActionIcon(_ icon: CommandIcon) -> some View {
        switch icon {
        case .system(let symbol):
            Image(systemName: symbol.rawValue)
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
        case .octicon(let symbol):
            OcticonImage(name: symbol.rawValue, size: AppStyles.General.Icon.compact)
        }
    }
}

// MARK: - EmptyDrawerBar

/// Slim bar shown when a pane has no drawer panes yet.
/// Displays a single [+] button to add the first drawer pane.
struct EmptyDrawerBar: View {
    let onAdd: () -> Void

    @State private var isHovered = false
    @State private var tooltipFrames: [DrawerTooltipTarget: CGRect] = [:]

    private static let tooltipCoordinateSpaceName = "emptyDrawerTooltipBar"

    private var addToolTip: ControlTooltipRenderValue {
        Self.addTooltipValue()
    }

    static func addTooltipValue() -> ControlTooltipRenderValue {
        AppCommand.addDrawerPane.definition.controlTooltipRenderValue(
            shortcutTextOverride: AppShortcut.addDrawerPane.displayKeyBinding(in: .emptyDrawer)?.displayText
        )
    }

    var body: some View {
        HStack {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: DrawerLayout.iconBarCornerRadius)
                        .fill(.ultraThinMaterial)

                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                            .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                            .fill(isHovered ? Color.white.opacity(AppStyles.General.Fill.hover) : Color.clear)
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                            isHovered = hovering
                        }
                    }
                    .hoverTooltipAnchor(DrawerTooltipTarget.emptyAdd, in: Self.tooltipCoordinateSpaceName)
                    .controlHelp(addToolTip)
                    .padding(.vertical, DrawerLayout.iconBarVerticalPadding)

                    FloatingHoverTooltipPresenter(
                        activeTarget: isHovered ? .emptyAdd : nil,
                        anchorFrames: tooltipFrames,
                        availableWidth: geo.size.width
                    ) { target in
                        switch target {
                        case .emptyAdd:
                            return addToolTip
                        default:
                            return nil
                        }
                    }
                }
                .coordinateSpace(name: Self.tooltipCoordinateSpaceName)
                .onPreferenceChange(HoverTooltipAnchorPreferenceKey<DrawerTooltipTarget>.self) { tooltipFrames = $0 }
            }
            Spacer()
        }
        .frame(height: DrawerLayout.iconButtonSize + (DrawerLayout.iconBarVerticalPadding * 2))
    }
}

// MARK: - Preview

#if DEBUG
    struct DrawerIconBar_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                Spacer()
                DrawerIconBar(
                    isExpanded: true,
                    onAdd: {},
                    onToggleExpand: {},
                    trailingActions: nil
                )
                Spacer()
            }
            .frame(width: 400, height: 200)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
