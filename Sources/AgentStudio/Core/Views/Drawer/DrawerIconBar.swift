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
    case chooser
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
    @State private var isChooserHovered = false
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
        let chooserPresentation = LocalActionSpec.openPaneLocationInEditorMenu.actionSpec

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
                        .help(togglePresentation.helpText)

                        // Vertical divider
                        Divider()
                            .frame(height: 16)
                            .padding(.horizontal, 2)

                        // Add button (right)
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
                                .fill(isAddHovered ? Color.white.opacity(AppStyles.General.Fill.hover) : Color.clear)
                        )
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                isAddHovered = hovering
                            }
                        }
                        .hoverTooltipAnchor(DrawerTooltipTarget.add, in: Self.tooltipCoordinateSpaceName)
                        .help(addPresentation.helpText)

                        Spacer()

                        if let trailingActions {
                            HStack(spacing: AppStyles.Components.EditorChooser.trailingClusterSpacing) {
                                Button {
                                    trailingActions.editorMenuPresented.wrappedValue.toggle()
                                } label: {
                                    HStack(spacing: AppStyles.Components.EditorChooser.chooserButtonContentSpacing) {
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
                                .help(chooserPresentation.helpText)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                        isChooserHovered = hovering
                                    }
                                }
                                .hoverTooltipAnchor(DrawerTooltipTarget.chooser, in: Self.tooltipCoordinateSpaceName)

                                Divider()
                                    .frame(height: AppStyles.Components.EditorChooser.dividerHeight)
                                    .padding(.horizontal, AppStyles.Components.EditorChooser.dividerHorizontalPadding)

                                trailingActionButton(
                                    icon: trailingActionIcon(for: finderPresentation.icon) ?? .system(name: "finder"),
                                    helpText: finderPresentation.helpText,
                                    isHovered: isFinderHovered,
                                    action: trailingActions.onOpenFinder
                                )
                                .disabled(!trailingActions.canOpenTarget)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: AppStyles.General.Animation.fast)) {
                                        isFinderHovered = hovering
                                    }
                                }
                                .hoverTooltipAnchor(DrawerTooltipTarget.finder, in: Self.tooltipCoordinateSpaceName)
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
        if trailingActions?.editorMenuPresented.wrappedValue == true { return nil }
        if isToggleHovered { return .toggle }
        if isAddHovered { return .add }
        if isChooserHovered { return .chooser }
        if isFinderHovered { return .finder }
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
        case .chooser:
            return LocalActionSpec.openPaneLocationInEditorMenu.actionSpec.helpText
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
