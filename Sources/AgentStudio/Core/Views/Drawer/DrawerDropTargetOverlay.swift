import SwiftUI

struct DrawerDropTargetOverlay: View {
    let target: DrawerRearrangeTarget?
    let targetRects: [DrawerRearrangeTarget: CGRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target, let rect = targetRects[target] {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
