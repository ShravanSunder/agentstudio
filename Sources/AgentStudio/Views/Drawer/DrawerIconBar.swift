import SwiftUI

// MARK: - TrapezoidConnector

/// Trapezoid shape that visually connects a pane to its drawer icon bar.
/// Wide at top (pane boundary), narrow at bottom (icon bar).
struct TrapezoidConnector: Shape {
    /// How much the sides taper inward (0 = rectangle, 1 = full taper).
    var taperRatio: CGFloat = 0.15

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * taperRatio
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))                                // top-left (full width)
        path.addLine(to: CGPoint(x: rect.width, y: 0))                    // top-right (full width)
        path.addLine(to: CGPoint(x: rect.width - inset, y: rect.height))  // bottom-right (narrower)
        path.addLine(to: CGPoint(x: inset, y: rect.height))               // bottom-left (narrower)
        path.closeSubpath()
        return path
    }
}

// MARK: - DrawerPaneItem

/// View-layer data model for a single drawer pane icon in the bar.
/// Mirrors the domain `DrawerPane` but carries only what the icon bar needs to render.
struct DrawerPaneItem: Identifiable {
    let id: UUID
    let title: String
    let icon: String
}

// MARK: - DrawerPaneIcon

/// Individual icon button representing a single drawer pane.
/// Uses proper SwiftUI Button for gesture priority over parent onTapGesture.
/// Active state uses a subtle highlight; right-click exposes a close action.
struct DrawerPaneIcon: View {
    let pane: DrawerPaneItem
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            Image(systemName: pane.icon)
                .font(.system(size: 12))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? .primary : (isHovered ? .primary : .secondary))
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.white.opacity(0.15) : (isHovered ? Color.white.opacity(0.08) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(pane.title)
        .contextMenu {
            Button("Close", role: .destructive, action: onClose)
        }
    }
}

// MARK: - DrawerIconBar

/// Icon bar at the bottom of a pane showing drawer pane icons.
/// Connected to the pane via a trapezoid visual bridge.
///
/// Follows the same callback-driven pattern as `ArrangementBar`:
/// the parent owns the state and this view is a pure render + action relay.
struct DrawerIconBar: View {
    let drawerPanes: [DrawerPaneItem]
    let activeDrawerPaneId: UUID?
    let isExpanded: Bool
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void
    let onClose: (UUID) -> Void
    let onToggleExpand: () -> Void

    @State private var isAddHovered = false
    @State private var isToggleHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Trapezoid connector — visual bridge from pane to icon strip
            TrapezoidConnector()
                .fill(.ultraThinMaterial)
                .frame(height: 8)

            // Icon strip
            HStack(spacing: 2) {
                // Drawer pane icons
                ForEach(drawerPanes) { pane in
                    DrawerPaneIcon(
                        pane: pane,
                        isActive: pane.id == activeDrawerPaneId,
                        onSelect: { onSelect(pane.id) },
                        onClose: { onClose(pane.id) }
                    )
                }

                // Add button
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isAddHovered ? .primary : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isAddHovered ? Color.white.opacity(0.08) : Color.clear)
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isAddHovered = hovering
                    }
                }
                .help("Add drawer pane")

                Spacer()

                // Expand/collapse toggle
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isToggleHovered ? .primary : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isToggleHovered ? Color.white.opacity(0.08) : Color.clear)
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isToggleHovered = hovering
                    }
                }
                .help(isExpanded ? "Collapse drawer" : "Expand drawer")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
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
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHovered ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .help("Add drawer pane")
            Spacer()
        }
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Preview

#if DEBUG
struct DrawerIconBar_Previews: PreviewProvider {
    static var previews: some View {
        let items: [DrawerPaneItem] = [
            DrawerPaneItem(id: UUID(), title: "Terminal", icon: "terminal"),
            DrawerPaneItem(id: UUID(), title: "Web", icon: "globe"),
            DrawerPaneItem(id: UUID(), title: "Code", icon: "doc.text"),
        ]
        let activeId = items[0].id

        return VStack {
            Spacer()
            DrawerIconBar(
                drawerPanes: items,
                activeDrawerPaneId: activeId,
                isExpanded: true,
                onSelect: { _ in },
                onAdd: {},
                onClose: { _ in },
                onToggleExpand: {}
            )
            Spacer()
        }
        .frame(width: 400, height: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
