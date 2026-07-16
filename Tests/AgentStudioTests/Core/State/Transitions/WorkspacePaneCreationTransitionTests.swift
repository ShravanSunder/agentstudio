import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace pane creation transitions")
struct WorkspacePaneCreationTransitionTests {
    @Test("validated identities preserve four explicit UUIDv7 values")
    func validatedIdentitiesPreserveExplicitValues() {
        // Arrange
        let paneID = UUIDv7.generate()
        let drawerID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let arrangementID = UUIDv7.generate()

        // Act
        let preparation = WorkspaceNewPaneTabIDs.prepare(
            paneID: paneID,
            drawerID: drawerID,
            tabID: tabID,
            arrangementID: arrangementID
        )

        // Assert
        guard case .validated(let identities) = preparation else {
            Issue.record("expected validated UUIDv7 identities")
            return
        }
        #expect(identities.paneID.uuid == paneID)
        #expect(identities.drawerID == drawerID)
        #expect(identities.tabID == tabID)
        #expect(identities.arrangementID == arrangementID)
        #expect(identities.paneID.isV7)
        #expect(UUIDv7.isV7(identities.drawerID))
        #expect(UUIDv7.isV7(identities.tabID))
        #expect(UUIDv7.isV7(identities.arrangementID))
    }

    @Test("identity preparation rejects non-v7 and duplicate identities without trapping")
    func identityPreparationRejectsInvalidIdentities() {
        // Arrange
        let validPaneID = UUIDv7.generate()
        let validDrawerID = UUIDv7.generate()
        let validTabID = UUIDv7.generate()
        let validArrangementID = UUIDv7.generate()
        let nonV7ID = UUID()

        // Act / Assert
        #expect(
            WorkspaceNewPaneTabIDs.prepare(
                paneID: nonV7ID,
                drawerID: validDrawerID,
                tabID: validTabID,
                arrangementID: validArrangementID
            ) == .rejected(.nonUUIDv7(identity: .pane, value: nonV7ID))
        )
        #expect(
            WorkspaceNewPaneTabIDs.prepare(
                paneID: validPaneID,
                drawerID: nonV7ID,
                tabID: validTabID,
                arrangementID: validArrangementID
            ) == .rejected(.nonUUIDv7(identity: .drawer, value: nonV7ID))
        )
        #expect(
            WorkspaceNewPaneTabIDs.prepare(
                paneID: validPaneID,
                drawerID: validDrawerID,
                tabID: nonV7ID,
                arrangementID: validArrangementID
            ) == .rejected(.nonUUIDv7(identity: .tab, value: nonV7ID))
        )
        #expect(
            WorkspaceNewPaneTabIDs.prepare(
                paneID: validPaneID,
                drawerID: validDrawerID,
                tabID: validTabID,
                arrangementID: nonV7ID
            ) == .rejected(.nonUUIDv7(identity: .arrangement, value: nonV7ID))
        )
        #expect(
            WorkspaceNewPaneTabIDs.prepare(
                paneID: validPaneID,
                drawerID: validPaneID,
                tabID: validTabID,
                arrangementID: validArrangementID
            ) == .rejected(.duplicateIdentity(validPaneID))
        )
    }

    @Test("zmx creation derives exact top-level worktree and floating session identities")
    func zmxCreationDerivesExactSessionIdentities() throws {
        // Arrange
        let worktreeIDs = try #require(makeIdentities())
        let floatingIDs = try #require(makeIdentities())
        let floatingDirectory = URL(fileURLWithPath: "/tmp/agent-studio-floating")

        // Act
        let worktreeDecision = makeCreationDecision(
            identities: worktreeIDs,
            content: .zmxTerminal(
                lifetime: .persistent,
                anchor: .worktree(repoStableKey: "repo-key", worktreeStableKey: "worktree-key")
            )
        )
        let floatingDecision = makeCreationDecision(
            identities: floatingIDs,
            content: .zmxTerminal(
                lifetime: .persistent,
                anchor: .floating(launchDirectory: floatingDirectory)
            )
        )
        // Assert
        #expect(
            terminalState(from: worktreeDecision)?.zmxSessionId
                == ZmxBackend.sessionId(
                    repoStableKey: "repo-key",
                    worktreeStableKey: "worktree-key",
                    paneId: worktreeIDs.paneID.uuid
                )
        )
        #expect(
            terminalState(from: floatingDecision)?.zmxSessionId
                == ZmxBackend.floatingSessionId(
                    launchDirectory: floatingDirectory,
                    paneId: floatingIDs.paneID.uuid
                )
        )
    }

    @Test("creation produces canonical pane graph and exact append-tab transition")
    func creationProducesCanonicalPaneAndTabTransition() throws {
        // Arrange
        let identities = try #require(makeIdentities())
        let requestedMetadata = PaneMetadata(
            paneId: PaneId(),
            contentType: .terminal,
            title: "Review"
        )
        let content = WorkspaceResolvedPaneContent.webview(
            WebviewState(url: URL(string: "https://example.com/review")!, title: "Review")
        )

        // Act
        let decision = makeCreationDecision(
            identities: identities,
            content: content,
            metadata: requestedMetadata,
            tabName: "Review Tab"
        )

        // Assert
        guard case .changed(let creation) = decision else {
            Issue.record("expected changed pane creation transition")
            return
        }
        #expect(creation.paneState.id == identities.paneID.uuid)
        #expect(creation.paneState.metadata.paneId == identities.paneID)
        #expect(creation.paneState.metadata.contentType == .browser)
        #expect(creation.paneState.content == content.paneContent(for: identities.paneID))
        #expect(creation.paneState.residency == .active)
        #expect(
            creation.paneState.kind
                == .layout(
                    drawer: DrawerGraphState(
                        drawerId: identities.drawerID,
                        parentPaneId: identities.paneID.uuid
                    )
                )
        )
        #expect(creation.tab.id == identities.tabID)
        #expect(creation.tab.name == "Review Tab")
        #expect(creation.tab.allPaneIds == [identities.paneID.uuid])
        #expect(creation.tab.activeArrangementId == identities.arrangementID)
        #expect(creation.tab.arrangements.map(\.id) == [identities.arrangementID])
        #expect(creation.presentationPane == creation.paneState.pane(isDrawerExpanded: false))
        #expect(
            creation.tabTransition.shell
                == .insert(
                    TabShell(id: identities.tabID, name: "Review Tab", colorHex: nil),
                    at: 0
                )
        )
        #expect(creation.tabTransition.activeTab == .select(identities.tabID))
        #expect(
            creation.tabTransition.graph
                == .insert(
                    TabGraphState(
                        tabId: identities.tabID,
                        allPaneIds: [identities.paneID.uuid],
                        arrangements: creation.tab.arrangements.map(PaneArrangementGraphState.init)
                    ),
                    at: 0
                )
        )
        #expect(
            creation.tabTransition.activeArrangement
                == .insert(
                    tabID: identities.tabID,
                    arrangementID: identities.arrangementID
                )
        )
        #expect(
            creation.tabTransition.activePanes
                == [
                    .insert(
                        arrangementID: identities.arrangementID,
                        selection: .selected(identities.paneID.uuid)
                    )
                ]
        )
        #expect(creation.tabTransition.activeDrawerChildren.isEmpty)
    }

    @Test("creation rejects existing pane drawer and tab identities atomically")
    func creationRejectsExistingIdentities() throws {
        // Arrange
        let identities = try #require(makeIdentities())
        let paneConflictContext = makeAppendContext(
            panePlacementDescriptors: [.mainLayout(paneID: identities.paneID.uuid)]
        )
        let drawerConflictContext = makeAppendContext(
            panePlacementDescriptors: [
                .drawerParent(
                    paneID: UUIDv7.generate(),
                    drawerID: identities.drawerID,
                    drawerChildPaneIDs: []
                )
            ]
        )
        let tabConflictContext = makeAppendContext(orderedTabIDs: [identities.tabID])

        // Act / Assert
        #expect(
            makeCreationDecision(identities: identities, context: paneConflictContext)
                == .rejected(.paneIdentityAlreadyExists(identities.paneID.uuid))
        )
        #expect(
            makeCreationDecision(identities: identities, context: drawerConflictContext)
                == .rejected(.drawerIdentityAlreadyExists(identities.drawerID))
        )
        #expect(
            makeCreationDecision(identities: identities, context: tabConflictContext)
                == .rejected(.tab(.duplicateTabShellID(identities.tabID)))
        )
    }
}

private func makeIdentities() -> WorkspaceNewPaneTabIDs? {
    guard
        case .validated(let identities) = WorkspaceNewPaneTabIDs.prepare(
            paneID: UUIDv7.generate(),
            drawerID: UUIDv7.generate(),
            tabID: UUIDv7.generate(),
            arrangementID: UUIDv7.generate()
        )
    else { return nil }
    return identities
}

private func makeCreationDecision(
    identities: WorkspaceNewPaneTabIDs,
    content: WorkspaceResolvedPaneContent = .ghosttyTerminal(lifetime: .temporary),
    metadata: PaneMetadata = PaneMetadata(title: "Terminal"),
    tabName: String = "Terminal",
    context: WorkspaceAppendTabContext = makeAppendContext()
) -> WorkspacePaneCreationTransitionDecision {
    WorkspacePaneCreationTransitionDecider.decide(
        request: WorkspacePaneCreationRequest(
            identities: identities,
            content: content,
            metadata: metadata,
            residency: .active,
            tabName: tabName
        ),
        context: context
    )
}

private func terminalState(
    from decision: WorkspacePaneCreationTransitionDecision
) -> TerminalState? {
    guard case .changed(let creation) = decision else { return nil }
    guard case .terminal(let terminalState) = creation.paneState.content else { return nil }
    return terminalState
}
