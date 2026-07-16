import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Nonterminal content mount owner")
struct NonterminalContentMountOwnerTests {
    @Test("empty cohort settles without mounting")
    func emptyCohortSettlesWithoutMounting() async throws {
        // Arrange
        let generation = try makeNonterminalMountGeneration()
        let port = RecordingNonterminalContentMountPort()
        let owner = NonterminalContentMountOwner(
            generation: generation,
            input: NonterminalContentMountInput(entries: []),
            admissionPort: port
        )

        // Act
        let settlement = await owner.mount()

        // Assert
        #expect(settlement.generation == generation)
        #expect(settlement.outcomesByPaneID.isEmpty)
        #expect(port.mountedPaneIDs.isEmpty)
    }

    @Test("prepared order and exact accepted panes reach the mount port")
    func preparedOrderAndExactAcceptedPanesReachMountPort() async throws {
        // Arrange
        let visiblePane = makeNonterminalMountPane(title: "Visible")
        let hiddenPane = makeNonterminalMountPane(title: "Hidden")
        let descriptors = [
            NonterminalContentMountDescriptor(
                content: .webview(visiblePane),
                visibilityPriority: .visible,
                hostPlacement: .tab(tabID: UUIDv7.generate())
            ),
            NonterminalContentMountDescriptor(
                content: .webview(hiddenPane),
                visibilityPriority: .hidden,
                hostPlacement: .tab(tabID: UUIDv7.generate())
            ),
        ]
        let port = RecordingNonterminalContentMountPort()
        let owner = NonterminalContentMountOwner(
            generation: try makeNonterminalMountGeneration(),
            input: NonterminalContentMountInput(entries: descriptors),
            admissionPort: port
        )

        // Act
        let settlement = await owner.mount()

        // Assert
        #expect(port.mountedPanes == [visiblePane, hiddenPane])
        #expect(settlement.outcomesByPaneID.values.allSatisfy { $0 == .mounted })
        #expect(owner.memberState(for: descriptors[0].paneID) == .mounted)
        #expect(owner.memberState(for: descriptors[1].paneID) == .mounted)
    }

    @Test("typed mount failure settles without retry or fallback")
    func typedMountFailureSettlesWithoutRetryOrFallback() async throws {
        // Arrange
        let pane = makeNonterminalMountPane(title: "Rejected")
        let descriptor = NonterminalContentMountDescriptor(
            content: .webview(pane),
            visibilityPriority: .activeVisible,
            hostPlacement: .tab(tabID: UUIDv7.generate())
        )
        let failure = NonterminalContentMountFailure.mountRejected
        let port = RecordingNonterminalContentMountPort(results: [descriptor.paneID: .failed(failure)])
        let owner = NonterminalContentMountOwner(
            generation: try makeNonterminalMountGeneration(),
            input: NonterminalContentMountInput(entries: [descriptor]),
            admissionPort: port
        )

        // Act
        let settlement = await owner.mount()

        // Assert
        #expect(port.mountedPaneIDs == [descriptor.paneID])
        #expect(settlement.outcomesByPaneID[descriptor.paneID] == .failedNonterminal(failure))
        #expect(owner.memberState(for: descriptor.paneID) == .failedNonterminal(failure))
    }

    @Test("replacement closes every unmounted member in the old generation")
    func replacementClosesEveryUnmountedMemberInOldGeneration() async throws {
        // Arrange
        let firstGeneration = try makeNonterminalMountGeneration()
        let replacementGeneration = try makeNonterminalMountGeneration()
        let pane = makeNonterminalMountPane(title: "Cancelled")
        let descriptor = NonterminalContentMountDescriptor(
            content: .webview(pane),
            visibilityPriority: .hidden,
            hostPlacement: .tab(tabID: UUIDv7.generate())
        )
        let port = RecordingNonterminalContentMountPort()
        let owner = NonterminalContentMountOwner(
            generation: firstGeneration,
            input: NonterminalContentMountInput(entries: [descriptor]),
            admissionPort: port
        )

        // Act
        let settlement = owner.cancelAndReplace(with: replacementGeneration)

        // Assert
        #expect(port.mountedPaneIDs.isEmpty)
        #expect(
            settlement.outcomesByPaneID[descriptor.paneID]
                == .cancelledReplaced(replacement: replacementGeneration)
        )
    }
}

@MainActor
private final class RecordingNonterminalContentMountPort: NonterminalContentMountAdmissionPort {
    private let results: [PaneId: NonterminalContentMountAdmissionResult]
    private(set) var mountedPanes: [Pane] = []

    var mountedPaneIDs: [PaneId] {
        mountedPanes.map { PaneId(existingUUID: $0.id) }
    }

    init(results: [PaneId: NonterminalContentMountAdmissionResult] = [:]) {
        self.results = results
    }

    func mount(_ descriptor: NonterminalContentMountDescriptor) -> NonterminalContentMountAdmissionResult {
        mountedPanes.append(descriptor.pane)
        return results[descriptor.paneID] ?? .mounted
    }
}

@MainActor
private func makeNonterminalMountGeneration() throws -> WorkspaceContentMountGeneration {
    let revisionOwner = WorkspacePersistenceRevisionOwner()
    let revision = try revisionOwner.performSynchronousTransaction { preparation in
        preparation.commit { preparation.transaction.proposedRevision }
    }
    return WorkspaceContentMountGeneration(
        processGeneration: revisionOwner.processGeneration,
        revision: revision
    )
}

private func makeNonterminalMountPane(title: String) -> Pane {
    Pane(
        id: UUIDv7.generate(),
        content: .webview(
            WebviewState(
                url: URL(filePath: "/tmp/nonterminal-content-mount"),
                title: title,
                showNavigation: false
            )
        ),
        metadata: PaneMetadata(title: title)
    )
}
