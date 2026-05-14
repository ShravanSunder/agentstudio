import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

/// Pin the drawer new-row band shape:
///
///   ▸ Single-row drawer has top + bottom bands
///   ▸ Two-row drawer has NO band (third row is forbidden)
///   ▸ Main has NO band (no row creation)
///   ▸ Band height = max(panel.height * ratio, minHeight floor)
@Suite(.serialized)
struct DropTargetConfigBandTests {
    private static let largeContainer = CGRect(x: 0, y: 0, width: 600, height: 400)
    private static let shortContainer = CGRect(x: 0, y: 0, width: 600, height: 80)

    @Test
    func mainConfig_hasNoNewRowBand() {
        #expect(DropTargetConfig.main.newRowBand == nil)
    }

    @Test
    func drawerSingleRow_hasNewRowBand() {
        #expect(DropTargetConfig.drawerSingleRow.newRowBand != nil)
    }

    @Test
    func drawerTwoRow_hasNoNewRowBand() {
        #expect(DropTargetConfig.drawerTwoRow.newRowBand == nil)
    }

    // MARK: - Band height math

    @Test
    func bandHeight_atLargePanel_isOneFifthOfPanelHeight() {
        let band = DropTargetConfig.drawerSingleRow.newRowBand!

        let height = band.bandHeight(in: Self.largeContainer)

        // 400 * 0.2 = 80, well above the 28pt floor.
        #expect(height == 80)
    }

    @Test
    func bandHeight_atShortPanel_floorsAtMinimum() {
        let band = DropTargetConfig.drawerSingleRow.newRowBand!

        let height = band.bandHeight(in: Self.shortContainer)

        // 80 * 0.2 = 16, below the 28pt floor → 28.
        #expect(height == 28)
    }

    @Test
    func bandHeight_atFloorBoundary_picksTheLargerValue() {
        let band = DropTargetConfig.drawerSingleRow.newRowBand!
        // 140 * 0.2 = 28 exactly = floor.
        let exactlyAtFloor = CGRect(x: 0, y: 0, width: 600, height: 140)

        #expect(band.bandHeight(in: exactlyAtFloor) == 28)
    }
}
