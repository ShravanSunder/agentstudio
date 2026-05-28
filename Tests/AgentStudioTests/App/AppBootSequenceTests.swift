import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct AppBootSequenceTests {
    @Test("boot sequence exposes the architecture-ordered steps")
    func orderedStepsMatchesArchitectureContract() {
        #expect(
            WorkspaceBootSequence.orderedSteps == [
                .loadCanonicalStore,
                .loadCacheStore,
                .loadUIStore,
                .establishRuntimeBus,
                .startFilesystemActor,
                .startGitProjector,
                .startForgeActor,
                .startCacheCoordinator,
                .triggerInitialTopologySync,
                .armPersistenceObservation,
                .readyForReactiveSidebar,
            ])
    }

    @Test("boot runner executes all steps in declared order")
    func runExecutesOrderedSequence() {
        var recorded: [WorkspaceBootStep] = []
        WorkspaceBootSequence.run { step in
            recorded.append(step)
        }
        #expect(recorded == WorkspaceBootSequence.orderedSteps)
    }

    @Test("every boot step explains why it exists")
    func bootStepsDocumentTheirPurpose() {
        for step in WorkspaceBootSequence.orderedSteps {
            #expect(!step.purpose.isEmpty, "Missing boot purpose for \(step.rawValue)")
        }
    }
}
