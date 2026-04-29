import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropSizingModeResolverTests {
    @Test
    func mode_paneSplit_noShift_isHalveTarget() {
        let mode = DropSizingModeResolver.mode(
            for: .paneSplit(paneId: UUID(), side: .left),
            isShiftHeld: false
        )

        #expect(mode == .halveTarget)
    }

    @Test
    func mode_paneSplit_shift_isProportional() {
        let mode = DropSizingModeResolver.mode(
            for: .paneSplit(paneId: UUID(), side: .right),
            isShiftHeld: true
        )

        #expect(mode == .proportional)
    }

    @Test
    func mode_paneSlot_alwaysProportional() {
        let modeNoShift = DropSizingModeResolver.mode(
            for: .paneSlot(row: .main, index: 0),
            isShiftHeld: false
        )
        let modeShift = DropSizingModeResolver.mode(
            for: .paneSlot(row: .drawerTop, index: 2),
            isShiftHeld: true
        )

        #expect(modeNoShift == .proportional)
        #expect(modeShift == .proportional)
    }

    @Test
    func mode_paneNewRow_alwaysProportional() {
        let topMode = DropSizingModeResolver.mode(
            for: .paneNewRow(position: .top),
            isShiftHeld: false
        )
        let bottomMode = DropSizingModeResolver.mode(
            for: .paneNewRow(position: .bottom),
            isShiftHeld: true
        )

        #expect(topMode == .proportional)
        #expect(bottomMode == .proportional)
    }
}
