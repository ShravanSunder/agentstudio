import AgentStudioGit
import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Darwin private staged-ref admission")
struct DarwinPrivateStagingRefAdmissionTests {
    @Test("private staged refs are excluded before continuity and ordinary filesystem ingress")
    func privateStagedRefsAreExcludedAtSource() {
        let rootPath = "/tmp/repo"
        let stagedRefPath =
            "/tmp/repo/.git/refs/agentstudio/staged/attempt/refs/heads/main"

        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: [(path: stagedRefPath, eventId: 41, flags: 0)],
            ordinaryPaths: [stagedRefPath],
            rootPath: rootPath,
            observationScopes: [
                AgentStudioGit.GitStatusObservationScope(
                    kind: .subtree,
                    path: URL(fileURLWithPath: "/tmp/repo/.git/refs")
                )
            ]
        )

        #expect(classification.rawEvents.map(\.hasRelevantMutation) == [false])
        #expect(classification.ordinaryPaths.isEmpty)
    }

    @Test("continuity streams exclude the private staged-ref subtree in the kernel")
    func continuityStreamsExcludePrivateStagedRefSubtree() {
        let refsScope = AgentStudioGit.GitStatusObservationScope(
            kind: .subtree,
            path: URL(fileURLWithPath: "/tmp/repo/.git/refs")
        )

        #expect(
            DarwinFSEventStreamConfiguration.privateStagingExclusionPaths(
                observationScopes: [refsScope]
            ) == ["/tmp/repo/.git/refs/agentstudio/staged"]
        )
        #expect(
            DarwinFSEventStreamConfiguration.privateStagingExclusionPaths(
                sharedParentPath: "/tmp/repo/.git"
            ) == ["/tmp/repo/.git/refs/agentstudio/staged"]
        )
    }
}
