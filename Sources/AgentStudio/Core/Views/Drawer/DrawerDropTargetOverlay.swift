import AgentStudioInfrastructure
import SwiftUI

/// Drawer-specific alias for the shared `DropTargetVisual`. Drawer
/// callers use this name to make the type's role at the call site
/// obvious; new code can use `DropTargetVisual` directly.
package typealias DrawerDropTargetVisual = DropTargetVisual

package struct DrawerDropTargetOverlay: View {
    let target: DrawerRearrangeTarget?
    let targetVisuals: [DrawerRearrangeTarget: DropTargetVisual]

    package init(
        target: DrawerRearrangeTarget?,
        targetVisuals: [DrawerRearrangeTarget: DropTargetVisual]
    ) {
        self.target = target
        self.targetVisuals = targetVisuals
    }

    package var body: some View {
        ZStack(alignment: .topLeading) {
            if let target, let visual = targetVisuals[target] {
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppStyles.General.Accent.primaryColor.opacity(0.16))
                    .frame(width: visual.region.width, height: visual.region.height)
                    .offset(x: visual.region.minX, y: visual.region.minY)

                if let marker = visual.insertionMarker {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppStyles.General.Accent.primaryColor.opacity(0.85))
                        .frame(width: marker.width, height: marker.height)
                        .offset(x: marker.minX, y: marker.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
