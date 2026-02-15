import SwiftUI

// MARK: - DrawerResizeHandle

/// Draggable resize handle at the top of the drawer panel.
/// Reports vertical drag deltas so the parent can adjust the panel height.
struct DrawerResizeHandle: View {
    let onDrag: (CGFloat) -> Void
    @State private var isDragging = false
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(isDragging ? 0.4 : 0.2))
                    .frame(width: 40, height: 4)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let delta = value.translation.height - lastTranslation
                        lastTranslation = value.translation.height
                        onDrag(-delta) // Negative: drag up = more height
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastTranslation = 0
                    }
            )
    }
}

// MARK: - DrawerPanel

/// Floating drawer panel that overlays pane content.
/// Shows the active drawer pane's content in a rectangular panel
/// with a resize handle at the top and material background.
///
/// Follows the same callback-driven pattern as `ArrangementBar`:
/// the parent owns the state and this view is a pure render + action relay.
struct DrawerPanel: View {
    let drawerPaneView: PaneView?
    let height: CGFloat
    let onResize: (CGFloat) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Resize handle at top
            DrawerResizeHandle(onDrag: onResize)

            // Drawer pane content
            if let paneView = drawerPaneView {
                // Reuse the existing PaneViewRepresentable which correctly
                // bridges via swiftUIContainer for IOSurface stability.
                PaneViewRepresentable(paneView: paneView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Content",
                    systemImage: "rectangle.bottomhalf.inset.filled",
                    description: Text("Select a drawer pane")
                )
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Preview

#if DEBUG
struct DrawerPanel_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            DrawerPanel(
                drawerPaneView: nil,
                height: 200,
                onResize: { _ in },
                onDismiss: {}
            )
            Spacer()
        }
        .frame(width: 500, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
