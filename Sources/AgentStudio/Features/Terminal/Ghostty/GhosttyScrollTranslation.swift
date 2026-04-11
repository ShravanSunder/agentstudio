import AppKit
import GhosttyKit

struct GhosttyScrollTranslation: Equatable {
    let deltaX: Double
    let deltaY: Double
    let scrollMods: ghostty_input_scroll_mods_t

    static func translate(event: NSEvent) -> Self {
        translate(
            deltaX: Double(event.scrollingDeltaX),
            deltaY: Double(event.scrollingDeltaY),
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            momentumPhase: event.momentumPhase
        )
    }

    static func translate(
        deltaX: Double,
        deltaY: Double,
        hasPreciseScrollingDeltas: Bool,
        momentumPhase: NSEvent.Phase
    ) -> Self {
        let multiplier = hasPreciseScrollingDeltas ? 2.0 : 1.0
        let precisionBits: Int32 = hasPreciseScrollingDeltas ? 0b0000_0001 : 0
        let momentumBits = momentumCode(for: momentumPhase) << 1

        return Self(
            deltaX: deltaX * multiplier,
            deltaY: deltaY * multiplier,
            scrollMods: precisionBits | momentumBits
        )
    }

    private static func momentumCode(for phase: NSEvent.Phase) -> Int32 {
        if phase.contains(.began) {
            return 1
        }
        if phase.contains(.stationary) {
            return 2
        }
        if phase.contains(.changed) {
            return 3
        }
        if phase.contains(.ended) {
            return 4
        }
        if phase.contains(.cancelled) {
            return 5
        }
        if phase.contains(.mayBegin) {
            return 6
        }
        return 0
    }
}
