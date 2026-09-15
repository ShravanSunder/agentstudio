import AppKit
import SwiftUI

/// Presents one already-registered pane host for a held Space gesture.
///
/// The preview uses the same stable container as the canonical pane path. Its
/// surface registration is the only additional custody claim, and disappears
/// with this branch so retired slots can finalize normally.
@MainActor
struct HeldPanePreviewContainer: View {
    let tabId: UUID
    let paneHost: PaneHostView
    let viewRegistry: ViewRegistry

    private var surfaceId: String {
        "held-preview:\(tabId)"
    }

    var body: some View {
        PaneViewRepresentable(paneHost: paneHost)
            .id(paneHost.hostIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                registerRenderedSurface()
            }
            .onChange(of: paneHost.hostIdentity) { _, _ in
                registerRenderedSurface()
            }
            .onDisappear {
                viewRegistry.unregisterSurface(surfaceId)
            }
    }

    private func registerRenderedSurface() {
        viewRegistry.surfaceRenderedIds(surfaceId, ids: [paneHost.paneId])
    }
}
