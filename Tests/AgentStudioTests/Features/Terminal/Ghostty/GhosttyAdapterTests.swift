import GhosttyKit
import Testing

@testable import AgentStudio

@Suite("GhosttyAdapter")
@MainActor
struct GhosttyAdapterTests {
    @Test("known action tags map to typed events")
    func knownTagMappings() {
        let adapter = GhosttyAdapter.shared

        #expect(
            adapter.translate(actionTag: UInt32(GHOSTTY_ACTION_NEW_TAB.rawValue)) == .newTab
        )
        #expect(
            adapter.translate(
                actionTag: UInt32(GHOSTTY_ACTION_CLOSE_TAB.rawValue),
                payload: .closeTab(modeRawValue: GHOSTTY_ACTION_CLOSE_TAB_MODE_THIS.rawValue)
            ) == .closeTab(mode: .thisTab)
        )
        #expect(
            adapter.translate(
                actionTag: UInt32(GHOSTTY_ACTION_GOTO_TAB.rawValue),
                payload: .gotoTab(targetRawValue: GHOSTTY_GOTO_TAB_NEXT.rawValue)
            ) == .gotoTab(target: .next)
        )
        #expect(
            adapter.translate(
                actionTag: UInt32(GHOSTTY_ACTION_MOVE_TAB.rawValue),
                payload: .moveTab(amount: 2)
            ) == .moveTab(amount: 2)
        )
        #expect(
            adapter.translate(
                actionTag: UInt32(GHOSTTY_ACTION_NEW_SPLIT.rawValue),
                payload: .newSplit(directionRawValue: GHOSTTY_SPLIT_DIRECTION_RIGHT.rawValue)
            ) == .newSplit(direction: .right)
        )
        #expect(
            adapter.translate(
                actionTag: UInt32(GHOSTTY_ACTION_GOTO_SPLIT.rawValue),
                payload: .gotoSplit(directionRawValue: GHOSTTY_GOTO_SPLIT_PREVIOUS.rawValue)
            ) == .gotoSplit(direction: .previous)
        )
        #expect(
            adapter.translate(
                actionTag: UInt32(GHOSTTY_ACTION_RESIZE_SPLIT.rawValue),
                payload: .resizeSplit(amount: 3, directionRawValue: GHOSTTY_RESIZE_SPLIT_LEFT.rawValue)
            ) == .resizeSplit(amount: 3, direction: .left)
        )
        #expect(
            adapter.translate(actionTag: UInt32(GHOSTTY_ACTION_EQUALIZE_SPLITS.rawValue)) == .equalizeSplits
        )
        #expect(
            adapter.translate(actionTag: UInt32(GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM.rawValue)) == .toggleSplitZoom
        )
        #expect(
            adapter.translate(actionTag: UInt32(GHOSTTY_ACTION_RING_BELL.rawValue)) == .bellRang
        )
    }

    @Test("invalid payload maps to unhandled")
    func invalidPayloadMapsToUnhandled() {
        let adapter = GhosttyAdapter.shared
        let closeTag = UInt32(GHOSTTY_ACTION_CLOSE_TAB.rawValue)
        #expect(adapter.translate(actionTag: closeTag, payload: .noPayload) == .unhandled(tag: closeTag))
    }

    @Test("unknown action tags map to unhandled event")
    func unknownTagMapsToUnhandled() {
        let adapter = GhosttyAdapter.shared
        #expect(adapter.translate(actionTag: 9999) == .unhandled(tag: 9999))
    }
}
