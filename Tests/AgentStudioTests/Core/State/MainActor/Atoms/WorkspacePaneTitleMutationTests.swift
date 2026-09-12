import Foundation
import Observation
import Testing
import os

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

private final class WorkspacePaneTitleObservationCounter: Sendable {
    private let invalidationCountStorage = OSAllocatedUnfairLock(initialState: 0)

    var invalidationCount: Int {
        invalidationCountStorage.withLock { $0 }
    }

    func record() {
        invalidationCountStorage.withLock { $0 += 1 }
    }
}

@MainActor
private struct WorkspacePaneTitleFleet {
    let graphAtom: WorkspacePaneGraphAtom
    let paneIDs: [UUID]

    var targetPaneID: UUID {
        paneIDs[0]
    }

    var unrelatedPaneIDs: ArraySlice<UUID> {
        paneIDs.dropFirst()
    }
}

private struct WorkspacePaneTitleDerivedState: Equatable {
    let structuralFacts: [UUID: PaneStructuralFacts]
    let residency: [UUID: SessionResidency]
    let association: [UUID: PaneRepositoryAssociation]
    let canonicalMembership: Set<UUID>
    let associationMembership: Set<UUID>
}

private struct WorkspacePaneTitleObservations {
    let title: WorkspacePaneTitleObservationCounter
    let unrelatedCanonical: WorkspacePaneTitleObservationCounter
    let structural: WorkspacePaneTitleObservationCounter
    let residency: WorkspacePaneTitleObservationCounter
    let association: WorkspacePaneTitleObservationCounter
    let membership: WorkspacePaneTitleObservationCounter
    let acceptedRevision: WorkspacePaneTitleObservationCounter
}

@MainActor
@Suite("Workspace pane title mutation", .serialized)
struct WorkspacePaneTitleMutationTests {
    @Test("title mutation avoids pane graph snapshots and derived-family mutations")
    func titleMutationAvoidsWholeGraphWork() async throws {
        let fleet = makePaneFleet()
        let traceLines = try await recordTitleMutationTrace(in: fleet)
        let paneGraphSnapshotReads = traceLines.filter { traceLine in
            traceLine.contains("\"body\":\"performance.atom.read\"")
                && traceLine.contains("\"agentstudio.performance.atom.label\":\"pane_graph_")
                && traceLine.contains("\"agentstudio.performance.atom.operation\":\"snapshot\"")
        }
        let derivedFamilyMutations = traceLines.filter { traceLine in
            traceLine.contains("\"body\":\"performance.atom.mutation\"")
                && [
                    "pane_graph_structural",
                    "pane_graph_residency",
                    "pane_graph_repository_association",
                ].contains { label in
                    traceLine.contains("\"agentstudio.performance.atom.label\":\"\(label)\"")
                }
        }
        let canonicalMutations = traceLines.filter { traceLine in
            traceLine.contains("\"body\":\"performance.atom.mutation\"")
                && traceLine.contains(
                    "\"agentstudio.performance.atom.label\":\"pane_graph_canonical\""
                )
        }

        #expect(paneGraphSnapshotReads.isEmpty)
        #expect(derivedFamilyMutations.isEmpty)
        #expect(canonicalMutations.count == 1)
        #expect(
            canonicalMutations.first?.contains(
                "\"agentstudio.performance.atom.operation\":\"set\""
            ) == true
        )
    }

    @Test("title mutation updates only the target canonical slot")
    func titleMutationPreservesDerivedFamiliesAndKeyedObservations() {
        let fleet = makePaneFleet()
        let graphAtom = fleet.graphAtom
        let canonicalStateBeforeMutation = graphAtom.paneStateSnapshot()
        let derivedStateBeforeMutation = captureDerivedState(in: fleet)
        let acceptedRevisionBeforeMutation = graphAtom.paneAcceptedCommitRevision
        let observations = observeTitleMutationBoundaries(in: fleet)

        graphAtom.updatePaneTitle(fleet.targetPaneID, title: "Renamed target pane")

        #expect(graphAtom.paneState(fleet.targetPaneID)?.metadata.title == "Renamed target pane")
        for paneID in fleet.unrelatedPaneIDs {
            #expect(graphAtom.paneState(paneID) == canonicalStateBeforeMutation[paneID])
        }
        #expect(captureDerivedState(in: fleet) == derivedStateBeforeMutation)
        #expect(graphAtom.paneAcceptedCommitRevision == acceptedRevisionBeforeMutation + 1)
        #expect(observations.title.invalidationCount == 1)
        #expect(observations.unrelatedCanonical.invalidationCount == 0)
        #expect(observations.structural.invalidationCount == 0)
        #expect(observations.residency.invalidationCount == 0)
        #expect(observations.association.invalidationCount == 0)
        #expect(observations.membership.invalidationCount == 0)
        #expect(observations.acceptedRevision.invalidationCount == 1)
    }

    @Test("equal and missing title updates are semantic no-ops")
    func equalAndMissingTitleUpdatesDoNotPublish() {
        let fleet = makePaneFleet()
        let graphAtom = fleet.graphAtom
        graphAtom.updatePaneTitle(fleet.targetPaneID, title: "Renamed target pane")
        let equalTitleObservation = observe {
            _ = graphAtom.paneState(fleet.targetPaneID)?.metadata.title
        }
        let revisionBeforeNoOpUpdates = graphAtom.paneAcceptedCommitRevision

        graphAtom.updatePaneTitle(fleet.targetPaneID, title: "Renamed target pane")
        graphAtom.updatePaneTitle(UUIDv7.generate(), title: "Missing pane")

        #expect(equalTitleObservation.invalidationCount == 0)
        #expect(graphAtom.paneAcceptedCommitRevision == revisionBeforeNoOpUpdates)
    }

    private func makePaneFleet(paneCount: Int = 64) -> WorkspacePaneTitleFleet {
        let graphAtom = WorkspacePaneGraphAtom()
        var paneIDs: [UUID] = []
        paneIDs.reserveCapacity(paneCount)

        for paneIndex in 0..<paneCount {
            let pane = graphAtom.createPane(
                launchDirectory: URL(
                    filePath: "/tmp/title-mutation-\(paneIndex)",
                    directoryHint: .isDirectory
                ),
                title: "Pane \(paneIndex)",
                zmxSessionID: .generateUUIDv7(),
                facets: PaneContextFacets(
                    repoId: UUIDv7.generate(),
                    worktreeId: UUIDv7.generate()
                )
            )
            paneIDs.append(pane.id)
        }
        return WorkspacePaneTitleFleet(graphAtom: graphAtom, paneIDs: paneIDs)
    }

    private func captureDerivedState(
        in fleet: WorkspacePaneTitleFleet
    ) -> WorkspacePaneTitleDerivedState {
        let graphAtom = fleet.graphAtom
        return WorkspacePaneTitleDerivedState(
            structuralFacts: Dictionary(
                uniqueKeysWithValues: fleet.paneIDs.compactMap { paneID in
                    graphAtom.paneStructuralFacts(paneID).map { (paneID, $0) }
                }
            ),
            residency: Dictionary(
                uniqueKeysWithValues: fleet.paneIDs.compactMap { paneID in
                    graphAtom.paneResidency(paneID).map { (paneID, $0) }
                }
            ),
            association: Dictionary(
                uniqueKeysWithValues: fleet.paneIDs.compactMap { paneID in
                    graphAtom.repositoryAssociation(for: paneID).map { (paneID, $0) }
                }
            ),
            canonicalMembership: graphAtom.paneIDs,
            associationMembership: graphAtom.repositoryAssociationPaneIds
        )
    }

    private func observeTitleMutationBoundaries(
        in fleet: WorkspacePaneTitleFleet
    ) -> WorkspacePaneTitleObservations {
        let graphAtom = fleet.graphAtom
        return WorkspacePaneTitleObservations(
            title: observe { _ = graphAtom.paneState(fleet.targetPaneID)?.metadata.title },
            unrelatedCanonical: observe {
                for paneID in fleet.unrelatedPaneIDs {
                    _ = graphAtom.paneState(paneID)
                }
            },
            structural: observe {
                for paneID in fleet.paneIDs {
                    _ = graphAtom.paneStructuralFacts(paneID)
                }
            },
            residency: observe {
                for paneID in fleet.paneIDs {
                    _ = graphAtom.paneResidency(paneID)
                }
            },
            association: observe {
                for paneID in fleet.paneIDs {
                    _ = graphAtom.repositoryAssociation(for: paneID)
                }
            },
            membership: observe {
                _ = graphAtom.paneIDs
                _ = graphAtom.repositoryAssociationPaneIds
            },
            acceptedRevision: observe { _ = graphAtom.paneAcceptedCommitRevision }
        )
    }

    private func recordTitleMutationTrace(
        in fleet: WorkspacePaneTitleFleet
    ) async throws -> [String] {
        let traceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "workspace-pane-title-mutation-\(UUIDv7.generate().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: traceDirectory) }
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "workspace-pane-title-mutation",
                "AGENTSTUDIO_TRACE_TAGS": "atoms",
            ]),
            processIdentifier: 932,
            timeUnixNano: { 932 }
        )
        AtomPerformanceTelemetry.shared.configure(traceRuntime: traceRuntime)
        defer { AtomPerformanceTelemetry.shared.resetForTests() }

        fleet.graphAtom.updatePaneTitle(fleet.targetPaneID, title: "Renamed target pane")
        try await AtomPerformanceTelemetry.shared.drainForTests()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        return try String(contentsOf: outputFileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func observe(
        _ read: @escaping @MainActor () -> Void
    ) -> WorkspacePaneTitleObservationCounter {
        let counter = WorkspacePaneTitleObservationCounter()
        withObservationTracking {
            read()
        } onChange: {
            counter.record()
        }
        return counter
    }
}
