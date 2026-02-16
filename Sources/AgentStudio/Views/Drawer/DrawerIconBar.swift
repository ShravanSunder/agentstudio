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

    @State private var isAddHovered = false
    @State private var isToggleHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Trapezoid connector — visual bridge from pane to icon strip
            TrapezoidConnector()
                .fill(.ultraThinMaterial)
                .frame(height: 8)

            // Icon strip: [toggle] | [+]
            HStack(spacing: 2) {
                // Expand/collapse toggle (left)
                Button(action: onToggleExpand) {
                    Image(systemName: "rectangle.bottomhalf.filled")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isExpanded ? .primary : (isToggleHovered ? .primary : .secondary))
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isExpanded ? Color.white.opacity(0.15) : (isToggleHovered ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
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
        VStack {
            Spacer()
            DrawerIconBar(
                isExpanded: true,
                onAdd: {},
                onToggleExpand: {}
            )
            Spacer()
        }
        .frame(width: 400, height: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
