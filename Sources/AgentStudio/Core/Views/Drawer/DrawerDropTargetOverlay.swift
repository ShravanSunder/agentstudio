import SwiftUI

/// Drawer-specific alias for the shared `DropTargetVisual`. Drawer
/// callers use this name to make the type's role at the call site
/// obvious; new code can use `DropTargetVisual` directly.
typealias DrawerDropTargetVisual = DropTargetVisual

struct DrawerDropTargetOverlay: View {
    let target: DrawerRearrangeTarget?
    let targetVisuals: [DrawerRearrangeTarget: DropTargetVisual]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target, let visual = targetVisuals[target] {
                switch visual {
                case .region(let rect):
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                case .insertionMarker(let rect):
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
