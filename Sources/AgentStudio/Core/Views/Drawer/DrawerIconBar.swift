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
    case editor
    case emptyAdd
}

// MARK: - DrawerIconBar

/// Icon bar at the bottom of a pane showing drawer controls.
/// Layout: [toggle] | [+]
///
/// Toggle uses `sidebar.bottom` (macOS convention for bottom panel toggle).
/// Follows the same callback-driven pattern as `ArrangementBar`.
struct DrawerIconBar: View {
    let isExpanded: Bool
    let onAdd: () -> Void
    let onToggleExpand: () -> Void
    let trailingActions: DrawerOverlay.TrailingActions?

    @State private var isAddHovered = false
    @State private var isToggleHovered = false
    @State private var isFinderHovered = false
    @State private var isCursorHovered = false
    @State private var tooltipFrames: [DrawerTooltipTarget: CGRect] = [:]

    private enum TrailingActionIcon {
        case system(name: String)
        case octicon(name: String)
    }

    private static let tooltipCoordinateSpaceName = "drawerTooltipBar"

    var body: some View {
        let togglePresentation = LocalActionSpec.toggleDrawer(isExpanded: isExpanded).actionSpec
        let addPresentation = LocalActionSpec.addDrawerPane.actionSpec
        let finderPresentation = LocalActionSpec.openPaneLocationInFinder.actionSpec
        let editorPresentation = LocalActionSpec.openPaneLocationInPreferredEditor.actionSpec

        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: DrawerLayout.iconBarCornerRadius)
                        .fill(.ultraThinMaterial)

                    // Icon strip: [toggle] | [+]
                    HStack(spacing: 2) {
                        // Expand/collapse toggle (left)
                        Button(action: onToggleExpand) {
                            Image(systemName: "rectangle.bottomhalf.filled")
                                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                                .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isExpanded ? .primary : (isToggleHovered ? .primary : .secondary))
                        .background(
                            RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                                .fill(
                                    isExpanded
                                        ? Color.white.opacity(AppStyle.fillActive)
                                        : (isToggleHovered
                                            ? Color.white.opacity(AppStyle.fillHover)
                                            : Color.clear))
                        )
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: AppStyle.animationFast)) {
                                isToggleHovered = hovering
                            }
                        }
                        .hoverTooltipAnchor(DrawerTooltipTarget.toggle, in: Self.tooltipCoordinateSpaceName)
                        .help(togglePresentation.helpText)

                        // Vertical divider
                        Divider()
                            .frame(height: 16)
                            .padding(.horizontal, 2)

                        // Add button (right)
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                                .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isAddHovered ? .primary : .secondary)
                        .background(
                            RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                                .fill(isAddHovered ? Color.white.opacity(AppStyle.fillHover) : Color.clear)
                        )
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: AppStyle.animationFast)) {
                                isAddHovered = hovering
                            }
                        }
                        .hoverTooltipAnchor(DrawerTooltipTarget.add, in: Self.tooltipCoordinateSpaceName)
                        .help(addPresentation.helpText)

                        Spacer()

                        if let trailingActions {
                            HStack(spacing: 6) {
                                trailingActionButton(
                                    icon: trailingActionIcon(for: finderPresentation.icon) ?? .system(name: "finder"),
                                    helpText: finderPresentation.helpText,
                                    isHovered: isFinderHovered,
                                    action: trailingActions.onOpenFinder
                                )
                                .disabled(!trailingActions.canOpenTarget)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: AppStyle.animationFast)) {
                                        isFinderHovered = hovering
                                    }
                                }
                                .hoverTooltipAnchor(DrawerTooltipTarget.finder, in: Self.tooltipCoordinateSpaceName)

                                trailingActionButton(
                                    icon: trailingActionIcon(for: editorPresentation.icon)
                                        ?? .octicon(name: "octicon-code-square"),
                                    helpText: editorPresentation.helpText,
                                    isHovered: isCursorHovered,
                                    action: trailingActions.onOpenCursor
                                )
                                .disabled(!trailingActions.canOpenTarget)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: AppStyle.animationFast)) {
                                        isCursorHovered = hovering
                                    }
                                }
                                .hoverTooltipAnchor(DrawerTooltipTarget.editor, in: Self.tooltipCoordinateSpaceName)
                            }
                        }
                    }
                    .padding(DrawerLayout.iconBarVerticalPadding)

                    FloatingHoverTooltipPresenter(
                        activeTarget: activeTooltipTarget,
                        anchorFrames: tooltipFrames,
                        availableWidth: geo.size.width,
                        tooltipText: tooltipText(for:)
                    )
                }
                .coordinateSpace(name: Self.tooltipCoordinateSpaceName)
                .onPreferenceChange(HoverTooltipAnchorPreferenceKey<DrawerTooltipTarget>.self) { tooltipFrames = $0 }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DrawerIconBarFrameKey.self,
                        value: geo.frame(in: .global)
                    )
                }
            )
            .frame(height: DrawerLayout.iconButtonSize + (DrawerLayout.iconBarVerticalPadding * 2))
        }
    }

    private var activeTooltipTarget: DrawerTooltipTarget? {
        if isToggleHovered { return .toggle }
        if isAddHovered { return .add }
        if isFinderHovered { return .finder }
        if isCursorHovered { return .editor }
        return nil
    }

    private func tooltipText(for target: DrawerTooltipTarget) -> String? {
        switch target {
        case .toggle:
            return LocalActionSpec.toggleDrawer(isExpanded: isExpanded).actionSpec.helpText
        case .add:
            return LocalActionSpec.addDrawerPane.actionSpec.helpText
        case .finder:
            return LocalActionSpec.openPaneLocationInFinder.actionSpec.helpText
        case .editor:
            return LocalActionSpec.openPaneLocationInPreferredEditor.actionSpec.helpText
        case .emptyAdd:
            return nil
        }
    }

    private func trailingActionIcon(for descriptor: ActionIconDescriptor?) -> TrailingActionIcon? {
        switch descriptor {
        case .system(let name):
            return .system(name: name)
        case .octicon(let name):
            return .octicon(name: name)
        case nil:
            return nil
        }
    }

    private func trailingActionButton(
        icon: TrailingActionIcon,
        helpText: String,
        isHovered: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                switch icon {
                case .system(let systemName):
                    Image(systemName: systemName)
                        .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                case .octicon(let octiconName):
                    OcticonImage(name: octiconName, size: AppStyle.compactIconSize)
                }
            }
            .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .background(
            RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                .fill(isHovered ? Color.white.opacity(AppStyle.fillHover) : Color.clear)
        )
        .help(helpText)
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

    var body: some View {
        let addPresentation = LocalActionSpec.addDrawerPane.actionSpec
        HStack {
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: DrawerLayout.iconBarCornerRadius)
                        .fill(.ultraThinMaterial)

                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                            .frame(width: DrawerLayout.iconButtonSize, height: DrawerLayout.iconButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: DrawerLayout.iconButtonCornerRadius)
                            .fill(isHovered ? Color.white.opacity(AppStyle.fillHover) : Color.clear)
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: AppStyle.animationFast)) {
                            isHovered = hovering
                        }
                    }
                    .hoverTooltipAnchor(DrawerTooltipTarget.emptyAdd, in: Self.tooltipCoordinateSpaceName)
                    .help(addPresentation.helpText)
                    .padding(.vertical, DrawerLayout.iconBarVerticalPadding)

                    FloatingHoverTooltipPresenter(
                        activeTarget: isHovered ? .emptyAdd : nil,
                        anchorFrames: tooltipFrames,
                        availableWidth: geo.size.width
                    ) { target in
                        switch target {
                        case .emptyAdd:
                            return addPresentation.helpText
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
