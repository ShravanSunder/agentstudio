import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneFramePublicationPolicyTests {
    @Test
    func drawerPane_publishesOnlyDrawerScopedFrames() {
        #expect(
            PaneFramePublicationPolicy.destinations(useDrawerFramePreference: true)
                == [.drawerContainer]
        )
    }

    @Test
    func mainPane_publishesOnlyTabScopedFrames() {
        #expect(
            PaneFramePublicationPolicy.destinations(useDrawerFramePreference: false)
                == [.tabContainer]
        )
    }
}
