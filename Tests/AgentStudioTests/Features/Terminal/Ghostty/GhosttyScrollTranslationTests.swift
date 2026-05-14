import AppKit
import Testing

@testable import AgentStudio

@Suite("Ghostty scroll translation")
struct GhosttyScrollTranslationTests {
    @Test("precise scrolling sets precision bit and doubles deltas")
    func preciseScrolling_setsPrecisionBitAndScalesDeltas() {
        let translation = GhosttyScrollTranslation.translate(
            deltaX: 1.5,
            deltaY: -2.0,
            hasPreciseScrollingDeltas: true,
            momentumPhase: []
        )

        #expect(translation.deltaX == 3.0)
        #expect(translation.deltaY == -4.0)
        #expect(translation.scrollMods == 0b0000_0001)
    }

    @Test("momentum phase is packed into scroll mods without modifier bits")
    func momentumPhase_isPackedIntoScrollMods() {
        let translation = GhosttyScrollTranslation.translate(
            deltaX: 0,
            deltaY: 4,
            hasPreciseScrollingDeltas: false,
            momentumPhase: .changed
        )

        #expect(translation.deltaY == 4)
        #expect(translation.scrollMods == 0b0000_0110)
    }

    @Test("mayBegin momentum maps to Ghostty momentum value")
    func mayBeginMomentum_mapsCorrectly() {
        let translation = GhosttyScrollTranslation.translate(
            deltaX: 0,
            deltaY: 1,
            hasPreciseScrollingDeltas: false,
            momentumPhase: .mayBegin
        )

        #expect(translation.scrollMods == 0b0000_1100)
    }
}
