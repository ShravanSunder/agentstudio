import Foundation
import Testing

@testable import AgentStudioCore

@Suite
struct ZoomCommandCapabilityPolicyTests {
    private let activeTabId = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let inactiveTabId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let activePaneId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let targetPaneId = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
    private let otherPaneId = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!

    @Test("explicit eligible pane in the active tab enters Zoom")
    func explicitEligiblePaneEntersZoom() {
        let result = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            explicitPaneId: targetPaneId,
            candidate: candidate(paneId: targetPaneId, tabId: activeTabId),
            zoomSourcePaneId: nil
        )

        #expect(
            result
                == ZoomCommandCapability(
                    tabId: activeTabId,
                    sourcePaneId: targetPaneId,
                    effect: .enter,
                    requiresTabActivation: false
                ))
    }

    @Test("explicit active Zoom source cancels even when it is no longer eligible")
    func explicitActiveZoomSourceCancelsBeforeEligibility() {
        let result = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: targetPaneId,
            explicitPaneId: targetPaneId,
            candidate: candidate(
                paneId: targetPaneId,
                tabId: activeTabId,
                isEligible: false
            ),
            zoomSourcePaneId: targetPaneId
        )

        #expect(
            result
                == ZoomCommandCapability(
                    tabId: activeTabId,
                    sourcePaneId: targetPaneId,
                    effect: .cancel,
                    requiresTabActivation: false
                ))
    }

    @Test("explicit source in an inactive Zoom tab resumes and activates its tab")
    func explicitInactiveZoomSourceResumes() {
        let result = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            explicitPaneId: targetPaneId,
            candidate: candidate(paneId: targetPaneId, tabId: inactiveTabId),
            zoomSourcePaneId: targetPaneId
        )

        #expect(
            result
                == ZoomCommandCapability(
                    tabId: inactiveTabId,
                    sourcePaneId: targetPaneId,
                    effect: .resume,
                    requiresTabActivation: true
                ))
    }

    @Test("explicit eligible pane retargets an inactive tab with another Zoom source")
    func explicitInactivePaneRetargetsZoom() {
        let result = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            explicitPaneId: targetPaneId,
            candidate: candidate(paneId: targetPaneId, tabId: inactiveTabId),
            zoomSourcePaneId: otherPaneId
        )

        #expect(
            result
                == ZoomCommandCapability(
                    tabId: inactiveTabId,
                    sourcePaneId: targetPaneId,
                    effect: .retarget,
                    requiresTabActivation: true
                ))
    }

    @Test("untargeted active Zoom cancels without requiring a candidate pane")
    func untargetedActiveZoomCancelsWithoutCandidate() {
        let result = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: nil,
            explicitPaneId: nil,
            candidate: nil,
            zoomSourcePaneId: targetPaneId
        )

        #expect(
            result
                == ZoomCommandCapability(
                    tabId: activeTabId,
                    sourcePaneId: targetPaneId,
                    effect: .cancel,
                    requiresTabActivation: false
                ))
    }

    @Test("untargeted eligible active pane enters Zoom")
    func untargetedEligibleActivePaneEntersZoom() {
        let result = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            explicitPaneId: nil,
            candidate: candidate(paneId: activePaneId, tabId: activeTabId),
            zoomSourcePaneId: nil
        )

        #expect(
            result
                == ZoomCommandCapability(
                    tabId: activeTabId,
                    sourcePaneId: activePaneId,
                    effect: .enter,
                    requiresTabActivation: false
                ))
    }

    @Test("ineligible or mismatched candidates are rejected")
    func invalidCandidatesAreRejected() {
        let ineligibleResult = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            explicitPaneId: activePaneId,
            candidate: candidate(
                paneId: activePaneId,
                tabId: activeTabId,
                isEligible: false
            ),
            zoomSourcePaneId: nil
        )
        let mismatchedResult = ZoomCommandCapabilityPolicy.resolve(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            explicitPaneId: activePaneId,
            candidate: candidate(paneId: otherPaneId, tabId: activeTabId),
            zoomSourcePaneId: nil
        )

        #expect(ineligibleResult == nil)
        #expect(mismatchedResult == nil)
    }

    private func candidate(
        paneId: UUID,
        tabId: UUID,
        isEligible: Bool = true
    ) -> ZoomCommandCandidate {
        ZoomCommandCandidate(
            paneId: paneId,
            tabId: tabId,
            isEligible: isEligible
        )
    }
}
