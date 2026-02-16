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
/// Renders the drawer's split tree (via SplitSubtreeView) in a rectangular panel
/// with a resize handle at the top and material background.
///
/// Translates tab-level PaneActions dispatched by SplitSubtreeView/TerminalPaneLeaf
/// into drawer-specific actions (resize, minimize, close, focus, equalize).
struct DrawerPanel: View {
    let tree: PaneSplitTree
    let parentPaneId: UUID
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let height: CGFloat
    let store: WorkspaceStore
    let action: (PaneAction) -> Void
    let onResize: (CGFloat) -> Void
    let onDismiss: () -> Void

    /// Translates tab-level actions into drawer-specific actions.
    /// SplitSubtreeView and TerminalPaneLeaf dispatch actions using tabId,
    /// but in the drawer context these need to be routed to drawer operations.
    private var drawerAction: (PaneAction) -> Void {
        { paneAction in
            switch paneAction {
            case .resizePane(_, let splitId, let ratio):
                action(.resizeDrawerPane(parentPaneId: parentPaneId, splitId: splitId, ratio: ratio))
            case .equalizePanes:
                action(.equalizeDrawerPanes(parentPaneId: parentPaneId))
            case .minimizePane(_, let paneId):
                action(.minimizeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            case .expandPane(_, let paneId):
                action(.expandDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            case .closePane(_, let paneId):
                action(.removeDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            case .focusPane(_, let paneId):
                action(.setActiveDrawerPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
            default:
                // Pass through any other actions (e.g., toggleDrawer)
                action(paneAction)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Resize handle at top
            DrawerResizeHandle(onDrag: onResize)

            // Drawer split tree content
            if let node = tree.root {
                SplitSubtreeView(
                    node: node,
                    tabId: tabId,
                    isSplit: tree.isSplit,
                    activePaneId: activePaneId,
                    minimizedPaneIds: minimizedPaneIds,
                    action: drawerAction,
                    onPersist: nil,
                    shouldAcceptDrop: { _, _ in false },
                    onDrop: { _, _, _ in },
                    store: store
                )
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Button {
                        let content = PaneContent.terminal(
                            TerminalState(provider: .ghostty, lifetime: .temporary)
                        )
                        let metadata = PaneMetadata(
                            source: .floating(workingDirectory: nil, title: nil),
                            title: "Drawer"
                        )
                        action(.addDrawerPane(parentPaneId: parentPaneId, content: content, metadata: metadata))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Add a drawer terminal")

                    Text("Add a drawer terminal")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
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
                tree: PaneSplitTree(),
                parentPaneId: UUID(),
                tabId: UUID(),
                activePaneId: nil,
                minimizedPaneIds: [],
                height: 200,
                store: WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: FileManager.default.temporaryDirectory)),
                action: { _ in },
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
