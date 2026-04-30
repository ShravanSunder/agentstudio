import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropTargetConfigTests {
    @Test
    func mainConfig_allowsPaneSplit_withCorridor() {
        let config = DropTargetConfig.main

        #expect(config.rows == [.main])
        #expect(config.newRowBand == nil)
        #expect(config.edgeCorridorWidth == 24)
        #expect(config.allowsPaneSplit)
    }

    @Test
    func drawerSingleRow_allowsPaneSplit_hasNewRowBand() {
        let config = DropTargetConfig.drawerSingleRow

        #expect(config.rows == [.drawerTop])
        #expect(config.newRowBand?.heightRatio == 0.2)
        #expect(config.newRowBand?.minHeight == 28)
        #expect(config.edgeCorridorWidth == 0)
        #expect(config.allowsPaneSplit)
    }

    @Test
    func drawerTwoRow_allowsPaneSplit_noNewRowBand() {
        let config = DropTargetConfig.drawerTwoRow

        #expect(config.rows == [.drawerTop, .drawerBottom])
        #expect(config.newRowBand == nil)
        #expect(config.edgeCorridorWidth == 0)
        #expect(config.allowsPaneSplit)
    }
}
