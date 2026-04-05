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
                .help(isExpanded ? "Collapse drawer" : "Expand drawer")

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
                .help("Add drawer pane")

                Spacer()

                if let trailingActions {
                    HStack(spacing: 6) {
                        trailingActionButton(
                            icon: .system(name: "macwindow"),
                            helpText: "Open pane location in Finder",
                            isHovered: isFinderHovered,
                            action: trailingActions.onOpenFinder
                        )
                        .disabled(!trailingActions.canOpenTarget)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: AppStyle.animationFast)) {
                                isFinderHovered = hovering
                            }
                        }

                        trailingActionButton(
                            icon: .octicon(name: "octicon-code-square"),
                            helpText: "Open pane location in Cursor or VS Code",
                            isHovered: isCursorHovered,
                            action: trailingActions.onOpenCursor
                        )
                        .disabled(!trailingActions.canOpenTarget)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: AppStyle.animationFast)) {
                                isCursorHovered = hovering
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
            .help("Add drawer pane")
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
