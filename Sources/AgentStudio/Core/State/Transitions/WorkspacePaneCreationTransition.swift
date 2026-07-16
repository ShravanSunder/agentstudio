import Foundation

enum WorkspaceNewPaneTabIdentity: Equatable, Sendable {
    case pane
    case drawer
    case tab
    case arrangement
}

enum WorkspaceNewPaneTabIDRejection: Equatable, Sendable {
    case nonUUIDv7(identity: WorkspaceNewPaneTabIdentity, value: UUID)
    case duplicateIdentity(UUID)
}

enum WorkspaceNewPaneTabIDsPreparation: Equatable, Sendable {
    case validated(WorkspaceNewPaneTabIDs)
    case rejected(WorkspaceNewPaneTabIDRejection)
}

/// Caller-minted identities for one pane plus its initial tab. Construction is
/// strict so the transition never needs to generate or repair identity.
struct WorkspaceNewPaneTabIDs: Equatable, Sendable {
    let paneID: PaneId
    let drawerID: UUID
    let tabID: UUID
    let arrangementID: UUID

    private init(
        paneID: PaneId,
        drawerID: UUID,
        tabID: UUID,
        arrangementID: UUID
    ) {
        self.paneID = paneID
        self.drawerID = drawerID
        self.tabID = tabID
        self.arrangementID = arrangementID
    }

    static func prepare(
        paneID: UUID,
        drawerID: UUID,
        tabID: UUID,
        arrangementID: UUID
    ) -> WorkspaceNewPaneTabIDsPreparation {
        let identities: [(WorkspaceNewPaneTabIdentity, UUID)] = [
            (.pane, paneID),
            (.drawer, drawerID),
            (.tab, tabID),
            (.arrangement, arrangementID),
        ]
        for (identity, value) in identities where !UUIDv7.isV7(value) {
            return .rejected(.nonUUIDv7(identity: identity, value: value))
        }

        var uniqueValues: Set<UUID> = []
        for (_, value) in identities where !uniqueValues.insert(value).inserted {
            return .rejected(.duplicateIdentity(value))
        }

        return .validated(
            Self(
                paneID: PaneId(uuid: paneID),
                drawerID: drawerID,
                tabID: tabID,
                arrangementID: arrangementID
            )
        )
    }
}

enum WorkspaceResolvedTopLevelZmxAnchor: Equatable, Sendable {
    case worktree(repoStableKey: String, worktreeStableKey: String)
    case floating(launchDirectory: URL)
}

enum WorkspaceResolvedPaneContent: Equatable, Sendable {
    case zmxTerminal(lifetime: SessionLifetime, anchor: WorkspaceResolvedTopLevelZmxAnchor)
    case ghosttyTerminal(lifetime: SessionLifetime)
    case webview(WebviewState)
    case bridgePanel(BridgePaneState)
    case codeViewer(CodeViewerState)

    func paneContent(for paneID: PaneId) -> PaneContent {
        switch self {
        case .zmxTerminal(let lifetime, let anchor):
            let sessionID: String
            switch anchor {
            case .worktree(let repoStableKey, let worktreeStableKey):
                sessionID = ZmxBackend.sessionId(
                    repoStableKey: repoStableKey,
                    worktreeStableKey: worktreeStableKey,
                    paneId: paneID.uuid
                )
            case .floating(let launchDirectory):
                sessionID = ZmxBackend.floatingSessionId(
                    launchDirectory: launchDirectory,
                    paneId: paneID.uuid
                )
            }
            return .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: lifetime,
                    zmxSessionId: sessionID
                )
            )
        case .ghosttyTerminal(let lifetime):
            return .terminal(
                TerminalState(
                    provider: .ghostty,
                    lifetime: lifetime,
                    zmxSessionId: nil
                )
            )
        case .webview(let state):
            return .webview(state)
        case .bridgePanel(let state):
            return .bridgePanel(state)
        case .codeViewer(let state):
            return .codeViewer(state)
        }
    }
}

struct WorkspacePaneCreationRequest: Equatable, Sendable {
    let identities: WorkspaceNewPaneTabIDs
    let content: WorkspaceResolvedPaneContent
    let metadata: PaneMetadata
    let residency: SessionResidency
    let tabName: String
}

struct WorkspacePaneCreationTransition: Equatable, Sendable {
    let paneState: PaneGraphState
    let tab: Tab
    let tabTransition: WorkspaceTabTransition

    var presentationPane: Pane {
        paneState.pane(isDrawerExpanded: false)
    }
}

enum WorkspacePaneCreationTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneCreationTransition)
    case rejected(WorkspacePaneCreationTransitionRejection)
}

enum WorkspacePaneCreationTransitionRejection: Equatable, Sendable {
    case paneIdentityAlreadyExists(UUID)
    case drawerIdentityAlreadyExists(UUID)
    case tab(WorkspaceTabTransitionRejection)
    case tabTransitionWasUnchanged
}

enum WorkspacePaneCreationTransitionDecider {
    static func decide(
        request: WorkspacePaneCreationRequest,
        context: WorkspaceAppendTabContext
    ) -> WorkspacePaneCreationTransitionDecision {
        let identities = request.identities
        guard context.panePlacements.placement(for: identities.paneID.uuid) == .missing else {
            return .rejected(.paneIdentityAlreadyExists(identities.paneID.uuid))
        }
        guard context.panePlacements.drawer(for: identities.drawerID) == .missing else {
            return .rejected(.drawerIdentityAlreadyExists(identities.drawerID))
        }

        let content = request.content.paneContent(for: identities.paneID)
        let pane = Pane(
            id: identities.paneID.uuid,
            content: content,
            metadata: request.metadata,
            residency: request.residency,
            kind: .layout(
                drawer: Drawer(
                    drawerId: identities.drawerID,
                    parentPaneId: identities.paneID.uuid
                )
            )
        )
        let arrangement = PaneArrangement(
            id: identities.arrangementID,
            name: "Default",
            isDefault: true,
            layout: Layout(paneId: identities.paneID.uuid),
            activePaneId: identities.paneID.uuid
        )
        let tab = Tab(
            id: identities.tabID,
            name: request.tabName,
            allPaneIds: [identities.paneID.uuid],
            arrangements: [arrangement],
            activeArrangementId: identities.arrangementID
        )
        let prospectiveContext = WorkspaceAppendTabContext(
            activeTab: context.activeTab,
            alignedTabOwners: context.alignedTabOwners,
            panePlacements: WorkspacePanePlacementIndex.prospectiveLayoutPane(
                paneID: identities.paneID.uuid,
                drawerID: identities.drawerID
            ),
            paneOwnerByPaneID: context.paneOwnerByPaneID,
            existingArrangementIDs: context.existingArrangementIDs,
            existingActiveArrangementTabIDs: context.existingActiveArrangementTabIDs,
            existingActivePaneArrangementIDs: context.existingActivePaneArrangementIDs,
            existingActiveDrawerChildKeys: context.existingActiveDrawerChildKeys
        )

        switch WorkspaceAppendTabTransitionDecider.decide(
            tab: tab,
            context: prospectiveContext
        ) {
        case .changed(let tabTransition):
            return .changed(
                WorkspacePaneCreationTransition(
                    paneState: PaneGraphState(pane: pane),
                    tab: tab,
                    tabTransition: tabTransition
                )
            )
        case .rejected(let rejection):
            return .rejected(.tab(rejection))
        case .unchanged:
            return .rejected(.tabTransitionWasUnchanged)
        }
    }
}
