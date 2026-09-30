import AgentStudioInfrastructure
import SwiftUI
import Testing

@testable import AgentStudioSharedComponents

@MainActor
@Suite("Drawer rail geometry", .serialized)
struct DrawerRailTests {
    @Test("owner and two drawers form one continuous rail through full row bounds")
    func twoDrawerRailContinuity() {
        let rowSize = CGSize(width: 14, height: 64)
        let contentInset = AppStyles.Shell.Sidebar.rowVerticalInset
        let railX = AppStyles.Shell.Sidebar.rowIdentityIconSize / 2
        let titleY = contentInset + AppStyles.Shell.Sidebar.nativePrimaryTextLineHeight / 2

        let owner = points(
            in: DrawerRail.path(
                segment: .ownerWithDrawers,
                ownerLineCount: 2,
                rowVerticalInset: contentInset,
                size: rowSize
            )
        )
        let firstDrawer = points(
            in: DrawerRail.path(
                segment: .drawer(isLast: false),
                ownerLineCount: 2,
                rowVerticalInset: contentInset,
                size: rowSize
            )
        )
        let lastDrawer = points(
            in: DrawerRail.path(
                segment: .drawer(isLast: true),
                ownerLineCount: 2,
                rowVerticalInset: contentInset,
                size: rowSize
            )
        )

        #expect(owner.first?.x == railX)
        #expect(owner.last == CGPoint(x: railX, y: rowSize.height))
        #expect(firstDrawer.first == CGPoint(x: railX, y: 0))
        #expect(firstDrawer[1] == CGPoint(x: railX, y: rowSize.height))
        #expect(firstDrawer[2] == CGPoint(x: railX, y: titleY))
        #expect(
            firstDrawer[3].x
                == AppStyles.Shell.Sidebar.drawerChildLeadingInset
                - AppStyles.Shell.Sidebar.drawerRailIconGap
        )
        #expect(lastDrawer.first == CGPoint(x: railX, y: 0))
        #expect(lastDrawer[1] == CGPoint(x: railX, y: titleY))
        #expect(lastDrawer[2] == CGPoint(x: railX, y: titleY))
        #expect(lastDrawer[3].x == firstDrawer[3].x)
    }

    private func points(in path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        // Path exposes its elements through forEach; it is not a Sequence.
        // swift-format-ignore: ReplaceForEachWithForLoop
        path.forEach { element in
            switch element {
            case .move(to: let point), .line(to: let point):
                points.append(point)
            default:
                break
            }
        }
        return points
    }
}
