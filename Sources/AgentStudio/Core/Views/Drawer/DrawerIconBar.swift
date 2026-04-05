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

private struct DrawerHoverTooltip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: AppStyle.textXs, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(AppStyle.fillActive), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .fixedSize()
    }
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

    private enum TrailingActionIcon {
        case system(name: String)
        case octicon(name: String)
    }

    var body: some View {
        let togglePresentation = LocalActionPresentation.toggleDrawer(isExpanded: isExpanded).presentation
        let addPresentation = LocalActionPresentation.addDrawerPane.presentation
        let finderPresentation = LocalActionPresentation.openPaneLocationInFinder.presentation
        let editorPresentation = LocalActionPresentation.openPaneLocationInPreferredEditor.presentation

        VStack(spacing: 0) {
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
                .overlay(alignment: .top) {
                    if isToggleHovered {
                        DrawerHoverTooltip(text: togglePresentation.helpText)
                            .offset(y: -28)
                    }
                }
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
                .overlay(alignment: .top) {
                    if isAddHovered {
                        DrawerHoverTooltip(text: addPresentation.helpText)
                            .offset(y: -28)
                    }
                }
                .help(addPresentation.helpText)

                Spacer()

                if let trailingActions {
                    HStack(spacing: 6) {
                        trailingActionButton(
                            icon: .system(name: "macwindow"),
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
                        .overlay(alignment: .top) {
                            if isFinderHovered {
                                DrawerHoverTooltip(text: finderPresentation.helpText)
                                    .offset(y: -28)
                            }
                        }

                        trailingActionButton(
                            icon: .octicon(name: "octicon-code-square"),
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
                        .overlay(alignment: .top) {
                            if isCursorHovered {
                                DrawerHoverTooltip(text: editorPresentation.helpText)
                                    .offset(y: -28)
                            }
                        }
                    }
                }
            }
            .padding(DrawerLayout.iconBarVerticalPadding)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DrawerLayout.iconBarCornerRadius))
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DrawerIconBarFrameKey.self,
                        value: geo.frame(in: .global)
                    )
                }
            )
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

    var body: some View {
        let addPresentation = LocalActionPresentation.addDrawerPane.presentation
        HStack {
            Spacer()
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
            .overlay(alignment: .top) {
                if isHovered {
                    DrawerHoverTooltip(text: addPresentation.helpText)
                        .offset(y: -28)
                }
            }
            .help(addPresentation.helpText)
            Spacer()
        }
        .padding(.vertical, DrawerLayout.iconBarVerticalPadding)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DrawerLayout.iconBarCornerRadius))
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
