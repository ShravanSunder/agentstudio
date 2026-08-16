import AgentStudioInfrastructure
import AgentStudioSharedComponents
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
    case paneSurfaceAction(String)
}

// MARK: - DrawerIconBar

enum DrawerIconBarLeadingControls {
    case drawer(
        isExpanded: Bool,
        addDrawerPaneAction: TargetedCommandControlAction?,
        toggleDrawerAction: TargetedCommandControlAction?
    )
    case hidden
}

/// Icon bar at the bottom of a pane showing drawer controls.
/// Layout: [toggle] | [+]
///
/// Toggle uses `sidebar.bottom` (macOS convention for bottom panel toggle).
/// Follows the same callback-driven pattern as `ArrangementBar`.
struct DrawerIconBar: View {
    let octiconLoader: OcticonLoader
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
        octiconLoader: OcticonLoader,
        leadingControls: DrawerIconBarLeadingControls,
        trailingActions: DrawerOverlay.TrailingActions?,
        paneSurfaceActions: [PaneSurfaceToolbarAction] = [],
        paneContextActions: [PaneSurfaceToolbarAction] = []
    ) {
        self.octiconLoader = octiconLoader
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

    var body: some View {
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

                        if case .drawer(
                            _,
                            let addDrawerPaneAction,
                            let toggleDrawerAction
                        ) = leadingControls,
                            addDrawerPaneAction != nil || toggleDrawerAction != nil
                        {
                            HStack(spacing: AppStyles.Shell.DrawerToolbar.trailingClusterSpacing) {
                                if let toggleDrawerAction {
                                    let toggleToolTip = toggleDrawerAction.commandSpec.controlTooltipRenderValue(
                                        textOverride: isExpanded ? "Collapse Drawer" : "Expand Drawer"
                                    )
                                    Button(action: toggleDrawerAction.perform) {
                                        Image(systemName: "rectangle.bottomhalf.filled")
                                            .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                                            .frame(
                                                width: DrawerLayout.iconButtonSize,
                                                height: DrawerLayout.iconButtonSize
                                            )
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(
                                        isExpanded ? .primary : (isToggleHovered ? .primary : .secondary)
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                                            .fill(
                                                isExpanded
                                                    ? Color.white.opacity(AppStyles.General.Fill.active)
                                                    : (isToggleHovered
                                                        ? Color.white.opacity(AppStyles.General.Fill.hover)
                                                        : Color.clear))
                                    )
                                    .disabled(!toggleDrawerAction.isEnabled)
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                            isToggleHovered = hovering
                                        }
                                    }
                                    .hoverTooltipAnchor(
                                        DrawerTooltipTarget.toggle,
                                        in: Self.tooltipCoordinateSpaceName
                                    )
                                    .controlHelp(toggleToolTip)
                                    .accessibilityHidden(true)
                                    .background {
                                        AccessibilityPressBridge(
                                            identifier: "paneSurfaceToolbar.drawerToggle",
                                            label: toggleDrawerAction.commandSpec.label,
                                            isEnabled: toggleDrawerAction.isEnabled,
                                            action: toggleDrawerAction.perform
                                        )
                                    }
                                }

                                if let addDrawerPaneAction {
                                    let addToolTip = addDrawerPaneAction.commandSpec.controlTooltipRenderValue()
                                    Button(action: addDrawerPaneAction.perform) {
                                        Image(systemName: "plus")
                                            .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                                            .frame(
                                                width: DrawerLayout.iconButtonSize,
                                                height: DrawerLayout.iconButtonSize
                                            )
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
                                    .disabled(!addDrawerPaneAction.isEnabled)
                                    .onHover { hovering in
                                        withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                            isAddHovered = hovering
                                        }
                                    }
                                    .hoverTooltipAnchor(
                                        DrawerTooltipTarget.add,
                                        in: Self.tooltipCoordinateSpaceName
                                    )
                                    .controlHelp(addToolTip)
                                    .accessibilityHidden(true)
                                    .background {
                                        AccessibilityPressBridge(
                                            identifier: "paneSurfaceToolbar.drawerAdd",
                                            label: addDrawerPaneAction.commandSpec.label,
                                            isEnabled: addDrawerPaneAction.isEnabled,
                                            action: addDrawerPaneAction.perform
                                        )
                                    }
                                }
                            }
                        }

                        Spacer()

                        if let trailingActions {
                            HStack(spacing: 0) {
                                HStack(spacing: 0) {
                                    if let openPullRequestAction = trailingActions.openPullRequestAction {
                                        paneSurfaceActionButton(openPullRequestAction)

                                        if !paneContextActions.isEmpty || hasPrimaryTrailingActions(trailingActions)
                                            || trailingActions.showPaneInboxAction != nil
                                        {
                                            trailingActionDivider
                                        }
                                    }

                                    if !paneContextActions.isEmpty {
                                        HStack(spacing: AppStyles.Shell.DrawerToolbar.trailingClusterSpacing) {
                                            ForEach(Array(paneContextActions.enumerated()), id: \.offset) { _, action in
                                                paneSurfaceActionButton(action)
                                            }
                                        }

                                        if hasPrimaryTrailingActions(trailingActions) {
                                            trailingActionDivider
                                        }
                                    }

                                    if let openEditorMenuAction = trailingActions.openEditorMenuAction {
                                        let chooserToolTip =
                                            openEditorMenuAction.commandSpec.controlTooltipRenderValue(
                                                textOverride: "Open in Editor"
                                            )
                                        Button(action: openEditorMenuAction.perform) {
                                            HStack(
                                                spacing: AppStyles.Components.EditorChooser.chooserButtonContentSpacing
                                            ) {
                                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                                    .font(
                                                        .system(
                                                            size: AppStyles.General.Icon.compact,
                                                            weight: .medium
                                                        )
                                                    )
                                                if let buttonTitle = trailingActions.buttonTitle {
                                                    Text(buttonTitle)
                                                        .lineLimit(1)
                                                        .truncationMode(.tail)
                                                }
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(
                                                        .system(
                                                            size: AppStyles.Components.EditorChooser
                                                                .chooserChevronFontSize,
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
                                        .foregroundStyle(isChooserHovered ? .primary : .secondary)
                                        .popover(
                                            isPresented: trailingActions.editorMenuPresented,
                                            arrowEdge: .bottom
                                        ) {
                                            trailingActions.editorMenuContent
                                        }
                                        .disabled(!openEditorMenuAction.isEnabled)
                                        .controlHelp(chooserToolTip)
                                        .accessibilityHidden(true)
                                        .background {
                                            AccessibilityPressBridge(
                                                identifier: "paneSurfaceToolbar.editor",
                                                label: openEditorMenuAction.commandSpec.label,
                                                isEnabled: openEditorMenuAction.isEnabled,
                                                action: openEditorMenuAction.perform
                                            )
                                        }
                                        .onHover { hovering in
                                            withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                                isChooserHovered = hovering
                                            }
                                        }
                                        .hoverTooltipAnchor(
                                            DrawerTooltipTarget.chooser,
                                            in: Self.tooltipCoordinateSpaceName
                                        )
                                    }

                                    if trailingActions.openEditorMenuAction != nil
                                        && hasLocationActions(trailingActions)
                                    {
                                        trailingActionDivider
                                    }

                                    if hasLocationActions(trailingActions) {
                                        HStack(spacing: AppStyles.Shell.DrawerToolbar.trailingClusterSpacing) {
                                            if let openFinderAction = trailingActions.openFinderAction {
                                                let finderToolTip =
                                                    openFinderAction.commandSpec.controlTooltipRenderValue(
                                                        textOverride: "Open in Finder"
                                                    )
                                                trailingActionButton(
                                                    icon: trailingActionIcon(
                                                        for: openFinderAction.commandSpec.icon
                                                    ),
                                                    helpValue: finderToolTip,
                                                    isHovered: isFinderHovered,
                                                    action: openFinderAction.perform
                                                )
                                                .disabled(!openFinderAction.isEnabled)
                                                .accessibilityHidden(true)
                                                .background {
                                                    AccessibilityPressBridge(
                                                        identifier: "paneSurfaceToolbar.finder",
                                                        label: openFinderAction.commandSpec.label,
                                                        isEnabled: openFinderAction.isEnabled,
                                                        action: openFinderAction.perform
                                                    )
                                                }
                                                .onHover { hovering in
                                                    withAnimation(
                                                        .easeInOut(duration: AppStyles.General.Animation.fast)
                                                    ) {
                                                        isFinderHovered = hovering
                                                    }
                                                }
                                                .hoverTooltipAnchor(
                                                    DrawerTooltipTarget.finder,
                                                    in: Self.tooltipCoordinateSpaceName
                                                )
                                            }

                                            if let copyPathAction = trailingActions.copyPathAction {
                                                let copyPathToolTip =
                                                    copyPathAction.commandSpec.controlTooltipRenderValue(
                                                        textOverride: "Copy Path"
                                                    )
                                                trailingActionButton(
                                                    icon: trailingActionIcon(
                                                        for: copyPathAction.commandSpec.icon
                                                    ),
                                                    helpValue: copyPathToolTip,
                                                    isHovered: isCopyPathHovered,
                                                    action: copyPathAction.perform
                                                )
                                                .disabled(!copyPathAction.isEnabled)
                                                .accessibilityHidden(true)
                                                .background {
                                                    AccessibilityPressBridge(
                                                        identifier: "paneSurfaceToolbar.copyPath",
                                                        label: copyPathAction.commandSpec.label,
                                                        isEnabled: copyPathAction.isEnabled,
                                                        action: copyPathAction.perform
                                                    )
                                                }
                                                .onHover { hovering in
                                                    withAnimation(
                                                        .easeInOut(duration: AppStyles.General.Animation.fast)
                                                    ) {
                                                        isCopyPathHovered = hovering
                                                    }
                                                }
                                                .hoverTooltipAnchor(
                                                    DrawerTooltipTarget.copyPath,
                                                    in: Self.tooltipCoordinateSpaceName
                                                )
                                            }
                                        }
                                    }

                                    if let showPaneInboxAction = trailingActions.showPaneInboxAction {
                                        if !paneContextActions.isEmpty
                                            || hasPrimaryTrailingActions(trailingActions)
                                            || trailingActions.openPullRequestAction != nil
                                        {
                                            trailingActionDivider
                                        }
                                        let inboxToolTip =
                                            showPaneInboxAction.commandSpec.controlTooltipRenderValue(
                                                textOverride: "Open pane inbox"
                                            )

                                        trailingActionButton(
                                            icon: .system(name: "bell.fill"),
                                            helpValue: inboxToolTip,
                                            isHovered: isInboxHovered,
                                            action: showPaneInboxAction.perform
                                        )
                                        .disabled(!showPaneInboxAction.isEnabled)
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
                                        .hoverTooltipAnchor(
                                            DrawerTooltipTarget.inbox,
                                            in: Self.tooltipCoordinateSpaceName
                                        )
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
                                                label: showPaneInboxAction.commandSpec.label,
                                                isEnabled: showPaneInboxAction.isEnabled,
                                                action: showPaneInboxAction.perform
                                            )
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

    private func hasPrimaryTrailingActions(
        _ trailingActions: DrawerOverlay.TrailingActions
    ) -> Bool {
        trailingActions.openEditorMenuAction != nil || hasLocationActions(trailingActions)
    }

    private func hasLocationActions(
        _ trailingActions: DrawerOverlay.TrailingActions
    ) -> Bool {
        trailingActions.openFinderAction != nil || trailingActions.copyPathAction != nil
    }

    private func tooltipValue(for target: DrawerTooltipTarget) -> ControlTooltipRenderValue? {
        switch target {
        case .toggle:
            guard
                case .drawer(_, _, let toggleDrawerAction) = leadingControls,
                let toggleDrawerAction
            else {
                return nil
            }
            return toggleDrawerAction.commandSpec.controlTooltipRenderValue(
                textOverride: isExpanded ? "Collapse Drawer" : "Expand Drawer"
            )
        case .add:
            guard
                case .drawer(_, let addDrawerPaneAction, _) = leadingControls,
                let addDrawerPaneAction
            else {
                return nil
            }
            return addDrawerPaneAction.commandSpec.controlTooltipRenderValue()
        case .finder:
            return trailingActions?.openFinderAction?.commandSpec.controlTooltipRenderValue(
                textOverride: "Open in Finder"
            )
        case .copyPath:
            return trailingActions?.copyPathAction?.commandSpec.controlTooltipRenderValue(
                textOverride: "Copy Path"
            )
        case .chooser:
            return trailingActions?.openEditorMenuAction?.commandSpec.controlTooltipRenderValue(
                textOverride: "Open in Editor"
            )
        case .inbox:
            return trailingActions?.showPaneInboxAction?.commandSpec.controlTooltipRenderValue(
                textOverride: "Open pane inbox"
            )
        case .paneSurfaceAction(let accessibilityIdentifier):
            var surfaceActions = paneSurfaceActions + paneContextActions
            if let openPullRequestAction = trailingActions?.openPullRequestAction {
                surfaceActions.append(openPullRequestAction)
            }
            return surfaceActions.first {
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
                    OcticonImage(
                        name: octiconName,
                        size: AppStyles.General.Icon.compact,
                        loader: octiconLoader
                    )
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
                    .foregroundStyle(paneSurfaceActionIconForeground(action, isHovered: isHovered))
                    .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)

                if let visibleLabel = action.state.visibleLabel {
                    Text(visibleLabel)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                        .lineLimit(1)
                        .padding(.trailing, AppStyles.Shell.DrawerToolbar.labeledActionTrailingPadding)
                        .transition(.identity)
                }
            }
            .frame(height: DrawerLayout.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(paneSurfaceActionForeground(action, isHovered: isHovered))
        .background(
            RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                .fill(paneSurfaceActionFill(action, isHovered: isHovered))
                .overlay(
                    RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                        .stroke(
                            paneSurfaceActionStroke(action, isHovered: isHovered),
                            lineWidth: 1
                        )
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

    private func paneSurfaceActionForeground(
        _ action: PaneSurfaceToolbarAction,
        isHovered: Bool
    ) -> Color {
        if action.state.isSelected, action.state.selectionEmphasis == .accent {
            return ChromeToolbarControlPalette.foregroundColor(
                isSelected: true,
                isHovered: isHovered
            )
        }
        return action.state.isSelected || isHovered ? .primary : .secondary
    }

    private func paneSurfaceActionIconForeground(
        _ action: PaneSurfaceToolbarAction,
        isHovered: Bool
    ) -> Color {
        guard let iconAccentColorHex = action.state.iconAccentColorHex else {
            return paneSurfaceActionForeground(action, isHovered: isHovered)
        }
        return Color(
            nsColor: NSColor(hex: iconAccentColorHex) ?? AppStyles.General.Accent.primaryNSColor
        )
        .opacity(AppStyles.Shell.Sidebar.chipForegroundOpacity)
    }

    private func paneSurfaceActionFill(
        _ action: PaneSurfaceToolbarAction,
        isHovered: Bool
    ) -> Color {
        if action.state.isSelected, action.state.selectionEmphasis == .accent {
            return ChromeToolbarControlPalette.fillColor(
                isSelected: true,
                isHovered: isHovered
            )
        }
        if action.state.isSelected {
            return Color.white.opacity(AppStyles.General.Fill.active)
        }
        return isHovered ? Color.white.opacity(AppStyles.General.Fill.hover) : Color.clear
    }

    private func paneSurfaceActionStroke(
        _ action: PaneSurfaceToolbarAction,
        isHovered: Bool
    ) -> Color {
        guard action.state.isSelected, action.state.selectionEmphasis == .accent else {
            return .clear
        }
        return ChromeToolbarControlPalette.strokeColor(
            isSelected: true,
            isHovered: isHovered
        )
    }

    @ViewBuilder
    private func paneSurfaceActionIcon(_ icon: CommandIcon) -> some View {
        switch icon {
        case .system(let symbol):
            Image(systemName: symbol.rawValue)
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
        case .octicon(let symbol):
            OcticonImage(
                name: symbol.rawValue,
                size: AppStyles.General.Icon.compact,
                loader: octiconLoader
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct DrawerIconBar_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                Spacer()
                DrawerIconBar(
                    octiconLoader: OcticonLoader(
                        resourceRootURL: URL(fileURLWithPath: "/dev/null")
                    ),
                    leadingControls: .hidden,
                    trailingActions: nil
                )
                Spacer()
            }
            .frame(width: 400, height: 200)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
#endif
