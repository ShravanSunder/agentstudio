import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct PreparedNonterminalContentMountTests {
        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test("prepared Bridge mount uses the exact accepted pane and settles one generation claim")
        func preparedBridgeMountUsesExactAcceptedPaneAndSettlesOneClaim() async throws {
            // Arrange
            let generation = try makePreparedBridgeContentMountGeneration()
            let acceptedState = BridgePaneState(
                panelKind: .diffViewer,
                source: .workspace(
                    rootPath: "/accepted/bridge/source",
                    baseline: .unstaged
                )
            )
            let acceptedPane = Pane(
                id: UUIDv7.generate(),
                content: .bridgePanel(acceptedState),
                metadata: PaneMetadata(
                    contentType: .diff,
                    launchDirectory: URL(filePath: "/accepted/bridge/launch-directory"),
                    title: "Accepted Bridge",
                    facets: PaneContextFacets(
                        cwd: URL(filePath: "/accepted/bridge/current-working-directory")
                    ),
                    fillNilLaunchDirectoryFacet: false
                )
            )
            let descriptor = NonterminalContentMountDescriptor(
                content: .bridgePanel(acceptedPane),
                visibilityPriority: .activeVisible,
                hostPlacement: .tab(tabID: UUIDv7.generate())
            )
            let mountInput = NonterminalContentMountInput(entries: [descriptor])
            let store = WorkspaceStore()
            let viewRegistry = ViewRegistry()
            let coordinator = WorkspaceSurfaceCoordinator(
                store: store,
                viewRegistry: viewRegistry,
                runtime: SessionRuntime(store: store),
                windowLifecycleStore: WindowLifecycleAtom()
            )
            viewRegistry.installPreparedContentMountCohort(
                WorkspacePreparedContentMountCohort(
                    generation: generation,
                    terminalActivationInput: TerminalActivationInput(entries: []),
                    nonterminalContentMountInput: mountInput
                )
            )
            let admissionPort = PreparedNonterminalMountAdmissionPort(
                generation: generation,
                coordinator: coordinator
            )
            let owner = NonterminalContentMountOwner(
                generation: generation,
                input: mountInput,
                admissionPort: admissionPort
            )
            let paneID = PaneId(existingUUID: acceptedPane.id)

            // Act
            let settlement = await owner.mount()

            // Assert
            #expect(settlement.outcomesByPaneID[paneID] == .mounted)
            #expect(
                viewRegistry.preparedContentMountState(for: paneID, generation: generation)
                    == .completed(owner: .nonterminal, disposition: .mounted)
            )
            #expect(
                viewRegistry.claimPreparedContentMount(
                    paneID: paneID,
                    owner: .nonterminal,
                    generation: generation
                )
                    == .rejected(
                        .alreadyClaimed(
                            .completed(owner: .nonterminal, disposition: .mounted)
                        )
                    )
            )

            let mountedBridgeView =
                viewRegistry.view(for: acceptedPane.id)?.mountedContentViewForTesting
                as? BridgePaneMountView
            #expect(mountedBridgeView != nil)
            #expect(mountedBridgeView?.controller.bridgePaneState == acceptedState)
            #expect(coordinator.runtimeForPane(paneID) is BridgeRuntime)

            coordinator.teardownView(for: acceptedPane.id)
            await coordinator.shutdown()
        }
    }
}

@MainActor
private func makePreparedBridgeContentMountGeneration() throws -> WorkspaceContentMountGeneration {
    WorkspaceContentMountGeneration()
}
