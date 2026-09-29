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
    @Environment(\.sidebarRowVerticalInset) private var rowVerticalInset

    package init(segment: DrawerRailSegment, ownerLineCount: Int) {
        self.segment = segment
        self.ownerLineCount = ownerLineCount
    }

    package var body: some View {
        GeometryReader { geometry in
            Self.path(
                segment: segment,
                ownerLineCount: ownerLineCount,
                rowVerticalInset: rowVerticalInset,
                size: geometry.size
            ).stroke(
                Color(nsColor: .separatorColor).opacity(AppStyles.Shell.Sidebar.drawerRailOpacity),
                lineWidth: AppStyles.Shell.Sidebar.drawerRailLineWidth
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    package static func path(
        segment: DrawerRailSegment,
        ownerLineCount: Int,
        rowVerticalInset: CGFloat,
        size: CGSize
    ) -> Path {
        Path { path in
            let railX = AppStyles.Shell.Sidebar.rowIdentityIconSize / 2
            let titleMidpoint = rowVerticalInset + AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight / 2
            switch segment {
            case .none:
                break
            case .ownerWithDrawers:
                let lastIconBottom =
                    rowVerticalInset
                    + CGFloat(ownerLineCount) * AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight
                    + CGFloat(max(0, ownerLineCount - 1)) * AppStyles.Shell.Sidebar.rowContentSpacing
                path.move(to: CGPoint(x: railX, y: min(lastIconBottom, size.height)))
                path.addLine(to: CGPoint(x: railX, y: size.height))
            case .drawer(let isLast):
                path.move(to: CGPoint(x: railX, y: 0))
                path.addLine(to: CGPoint(x: railX, y: isLast ? titleMidpoint : size.height))
                path.move(to: CGPoint(x: railX, y: titleMidpoint))
                path.addLine(
                    to: CGPoint(
                        x: AppStyles.Shell.Sidebar.drawerChildLeadingInset
                            - AppStyles.Shell.Sidebar.drawerRailIconGap,
                        y: titleMidpoint
                    )
                )
            }
        }
    }
}
