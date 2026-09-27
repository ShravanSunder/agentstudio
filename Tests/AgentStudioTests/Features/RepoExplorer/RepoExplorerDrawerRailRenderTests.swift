import AgentStudioInfrastructure
import AppKit
import SwiftUI
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer drawer rail rendering", .serialized)
struct RepoExplorerDrawerRailRenderTests {
    @Test("owner and two drawer rails reach their allocated row edges")
    func twoDrawersHaveContinuousRail() throws {
        let rowHeight: CGFloat = 64
        let rows: [RepoExplorerProjectedPaneRow] = [
            makePaneRow(rail: .ownerWithDrawers, isDrawer: false),
            makePaneRow(rail: .drawer(isLast: false), isDrawer: true),
            makePaneRow(rail: .drawer(isLast: true), isDrawer: true),
        ]
        let view = VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                RepoExplorerPaneRow(
                    row: rows[index],
                    octiconLoader: makeRepoExplorerTestOcticonLoader(),
                    onFocus: {}
                )
                .frame(height: rowHeight, alignment: .top)
            }
        }
        .frame(width: 300, height: rowHeight * CGFloat(rows.count), alignment: .topLeading)
        .background(Color.black)

        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: rowHeight * CGFloat(rows.count))
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let railX =
            AppStyles.Shell.Sidebar.rowHorizontalInset
            + AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth / 2
        let scaleX = CGFloat(bitmap.pixelsWide) / 300
        let scaleY = CGFloat(bitmap.pixelsHigh) / (rowHeight * CGFloat(rows.count))
        for boundary in [rowHeight, rowHeight * 2] {
            for offset in [-2, -1, 1, 2] as [CGFloat] {
                let pixel = try #require(
                    bitmap.colorAt(
                        x: Int(railX * scaleX),
                        y: Int((boundary + offset) * scaleY)
                    )?.usingColorSpace(.deviceRGB))
                #expect(max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) > 0.06)
            }
        }
    }

    private func makePaneRow(rail: RepoExplorerDrawerRail, isDrawer: Bool) -> RepoExplorerProjectedPaneRow {
        var row = RepoExplorerProjectedPaneRow(
            groupId: "drawer-rail",
            destination: navigationUnassociatedDestination(
                paneID: UUIDv7.generate(),
                tabID: UUIDv7.generate()
            ),
            rowId: "rail-\(UUIDv7.generate())",
            primaryText: isDrawer ? "Drawer" : "Owner",
            isDrawerPane: isDrawer
        )
        row.drawerRail = rail
        return row
    }
}
