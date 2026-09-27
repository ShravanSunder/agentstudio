import AgentStudioInfrastructure
import SwiftUI

package enum DrawerRailSegment: Equatable, Sendable {
    // The Program Design names the absent tree segment `.none`.
    // swiftlint:disable:next discouraged_none_name
    case none
    case ownerWithDrawers
    case drawer(isLast: Bool)
}

/// Stateless rail paint for a row's already prepared tree segment.
package struct DrawerRail: View {
    package let segment: DrawerRailSegment
    package let ownerLineCount: Int

    package init(segment: DrawerRailSegment, ownerLineCount: Int) {
        self.segment = segment
        self.ownerLineCount = ownerLineCount
    }

    package var body: some View {
        GeometryReader { geometry in
            Path { path in
                let railX = AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth / 2
                let titleMidpoint = AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight / 2
                switch segment {
                case .none:
                    break
                case .ownerWithDrawers:
                    let lastIconBottom =
                        CGFloat(ownerLineCount)
                        * AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
                        + CGFloat(max(0, ownerLineCount - 1)) * AppStyles.Shell.Sidebar.rowContentSpacing
                    path.move(to: CGPoint(x: railX, y: min(lastIconBottom, geometry.size.height)))
                    path.addLine(to: CGPoint(x: railX, y: geometry.size.height))
                case .drawer(let isLast):
                    path.move(to: CGPoint(x: railX, y: 0))
                    path.addLine(to: CGPoint(x: railX, y: isLast ? titleMidpoint : geometry.size.height))
                    path.move(to: CGPoint(x: railX, y: titleMidpoint))
                    path.addLine(
                        to: CGPoint(
                            x: railX + AppStyles.Shell.Sidebar.drawerRailElbowWidth,
                            y: titleMidpoint
                        )
                    )
                }
            }
            .stroke(
                Color(nsColor: .separatorColor).opacity(AppStyles.Shell.Sidebar.drawerRailOpacity),
                lineWidth: AppStyles.Shell.Sidebar.drawerRailLineWidth
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
