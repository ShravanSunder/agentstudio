import SwiftUI

enum DrawerDropTargetVisual: Equatable {
    case region(CGRect)
    case insertionMarker(CGRect)

    var rect: CGRect {
        switch self {
        case .region(let rect), .insertionMarker(let rect):
            return rect
        }
    }

    var insertionMarkerRect: CGRect? {
        switch self {
        case .insertionMarker(let rect):
            return rect
        case .region:
            return nil
        }
    }
}

struct DrawerDropTargetOverlay: View {
    let target: DrawerRearrangeTarget?
    let targetVisuals: [DrawerRearrangeTarget: DrawerDropTargetVisual]

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
