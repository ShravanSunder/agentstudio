import SwiftUI

/// Edge-only focus cue for inactive split panes.
/// Keeps the center readable while dimming the outer band on all four sides.
struct InactivePaneEdgeDimmingOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let horizontalDepth = min(AppStyle.inactivePaneDimmingDepth, geometry.size.width / 2)
            let verticalDepth = min(AppStyle.inactivePaneDimmingDepth, geometry.size.height / 2)

            Color.black
                .opacity(AppStyle.inactivePaneDimmingOpacity)
                .mask {
                    edgeMask(
                        horizontalDepth: horizontalDepth,
                        verticalDepth: verticalDepth
                    )
                }
                .allowsHitTesting(false)
        }
    }

    private func edgeMask(
        horizontalDepth: CGFloat,
        verticalDepth: CGFloat
    ) -> some View {
        ZStack {
            edgeGradient(startPoint: .top, endPoint: .bottom)
                .frame(height: verticalDepth)
                .frame(maxHeight: .infinity, alignment: .top)
                .blendMode(.lighten)

            edgeGradient(startPoint: .bottom, endPoint: .top)
                .frame(height: verticalDepth)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .blendMode(.lighten)

            edgeGradient(startPoint: .leading, endPoint: .trailing)
                .frame(width: horizontalDepth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .blendMode(.lighten)

            edgeGradient(startPoint: .trailing, endPoint: .leading)
                .frame(width: horizontalDepth)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .blendMode(.lighten)
        }
        .compositingGroup()
    }

    private func edgeGradient(
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) -> some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .clear, location: 1),
            ],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
