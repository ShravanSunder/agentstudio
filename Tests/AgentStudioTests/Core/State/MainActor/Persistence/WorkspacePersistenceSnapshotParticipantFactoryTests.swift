import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceSnapshotParticipantFactoryTests {
    @Test("default factory membership policy is finite and matches AppPolicies")
    func defaultMembershipPolicyIsFiniteAndMatchesAppPolicies() {
        // Arrange
        let policy = WorkspaceSnapshotParticipantFactoryPolicy.appDefault

        // Act
        let limits = policy.fleetMembershipLimits

        // Assert
        #expect(limits.maximumKeyCount == AppPolicies.WorkspacePersistence.snapshotMaximumKeyCount)
        #expect(limits.maximumRawKeyBytes == AppPolicies.WorkspacePersistence.snapshotMaximumRawKeyBytes)
        #expect(limits.maximumKeyCount > 0)
        #expect(limits.maximumKeyCount < UInt64.max)
        #expect(limits.maximumRawKeyBytes > 0)
        #expect(limits.maximumRawKeyBytes < UInt64.max)
    }

    @Test("factory policy rejects zero limits without trapping")
    func factoryPolicyRejectsZeroLimitsWithoutTrapping() {
        // Arrange
        let zeroKeyLimits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 0,
            maximumRawKeyBytes: 1
        )
        let zeroRawByteLimits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 1,
            maximumRawKeyBytes: 0
        )

        // Act
        let zeroKeyResult = WorkspaceSnapshotParticipantFactoryPolicy.validated(
            fleetMembershipLimits: zeroKeyLimits
        )
        let zeroRawByteResult = WorkspaceSnapshotParticipantFactoryPolicy.validated(
            fleetMembershipLimits: zeroRawByteLimits
        )

        // Assert
        #expect(zeroKeyResult == .rejected(.maximumKeyCountMustBePositive))
        #expect(zeroRawByteResult == .rejected(.maximumRawKeyBytesMustBePositive))
    }

    @Test("factory policy rejects unbounded limits without trapping")
    func factoryPolicyRejectsUnboundedLimitsWithoutTrapping() {
        // Arrange
        let unboundedKeyLimits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: UInt64.max,
            maximumRawKeyBytes: 1
        )
        let unboundedRawByteLimits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 1,
            maximumRawKeyBytes: UInt64.max
        )

        // Act
        let unboundedKeyResult = WorkspaceSnapshotParticipantFactoryPolicy.validated(
            fleetMembershipLimits: unboundedKeyLimits
        )
        let unboundedRawByteResult = WorkspaceSnapshotParticipantFactoryPolicy.validated(
            fleetMembershipLimits: unboundedRawByteLimits
        )

        // Assert
        #expect(unboundedKeyResult == .rejected(.maximumKeyCountMustBeFinite))
        #expect(unboundedRawByteResult == .rejected(.maximumRawKeyBytesMustBeFinite))
    }

    @Test("factory constructs the exact closed participant inventory in canonical order")
    func constructsExactParticipantInventoryInCanonicalOrder() {
        // Arrange
        let fixture = FactoryOwnerFixture()
        let factory = fixture.makeFactory()

        // Act
        let result = factory.constructParticipantSet()

        // Assert
        guard case .constructed(let participantSet) = result else {
            Issue.record("expected the participant set to be constructed")
            return
        }
        #expect(participantSet.participantIDs == WorkspacePersistenceSnapshotParticipantID.allCases)
        #expect(participantSet.participants.count == 14)
        #expect(Set(participantSet.participantIDs).count == 14)
        #expect(factory.installedParticipantSet?.participantIDs == participantSet.participantIDs)
    }

    @Test("factory constructs all fourteen participants for a large bounded topology")
    func constructsAllParticipantsForLargeBoundedTopology() {
        // Arrange
        let fixture = FactoryOwnerFixture()
        let repositories = (0..<10_000).map { index in
            Repo(
                id: UUIDv7.generate(),
                name: "repository-\(index)",
                repoPath: URL(filePath: "/tmp/factory-repository-\(index)")
            )
        }
        #expect(
            fixture.repositoryTopologyAtom.hydrate(
                runtimeRepos: repositories,
                watchedPaths: [],
                unavailableRepoIds: []
            ) == .applied
        )
        let factory = fixture.makeFactory()

        // Act
        let result = factory.constructParticipantSet()

        // Assert
        guard case .constructed(let participantSet) = result else {
            Issue.record("expected the bounded large topology to construct")
            return
        }
        #expect(participantSet.participantIDs == WorkspacePersistenceSnapshotParticipantID.allCases)
        #expect(participantSet.participants.count == 14)
    }

    @Test("over-limit topology rejection installs no participant set")
    func overLimitTopologyRejectionInstallsNoParticipantSet() throws {
        // Arrange
        let fixture = FactoryOwnerFixture()
        let repositories = (0..<2).map { index in
            Repo(
                id: UUIDv7.generate(),
                name: "repository-\(index)",
                repoPath: URL(filePath: "/tmp/over-limit-repository-\(index)")
            )
        }
        #expect(
            fixture.repositoryTopologyAtom.hydrate(
                runtimeRepos: repositories,
                watchedPaths: [],
                unavailableRepoIds: []
            ) == .applied
        )
        let policy = try requireConstructedPolicy(
            WorkspaceSnapshotParticipantFactoryPolicy.validated(
                fleetMembershipLimits: .init(maximumKeyCount: 1, maximumRawKeyBytes: 16)
            )
        )
        let factory = fixture.makeFactory(policy: policy)

        // Act
        let result = factory.constructParticipantSet()

        // Assert
        guard case .rejected(let rejection) = result else {
            Issue.record("expected over-limit factory construction rejection")
            return
        }
        #expect(
            rejection
                == .participantConstructionRejected(
                    participantID: .repositories,
                    rejection: .baseMembershipKeyCountCapacityExceeded
                ))
        #expect(factory.installedParticipantSet == nil)
    }

    @Test("pane graph byte estimation is deterministic and strictly positive")
    func paneGraphByteEstimationIsDeterministicAndStrictlyPositive() {
        // Arrange
        let paneGraph = PaneGraphState(
            pane: Pane(
                content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
                metadata: PaneMetadata(title: "Factory estimate")
            )
        )
        let estimator = WorkspacePaneGraphPersistenceSnapshotByteEstimator()

        // Act
        let firstEstimate = estimator.estimate(paneGraph)
        let secondEstimate = estimator.estimate(paneGraph)

        // Assert
        #expect(firstEstimate > 0)
        #expect(secondEstimate == firstEstimate)
    }

    @Test("pane graph byte estimation increases with every persisted dynamic content family")
    func paneGraphByteEstimationIncreasesWithPersistedDynamicContent() {
        // Arrange
        let estimator = WorkspacePaneGraphPersistenceSnapshotByteEstimator()
        let compactText = "x"
        let expandedText = String(repeating: "x", count: 1024)
        let contentPairs: [(PaneContent, PaneContent)] = [
            (
                .terminal(.init(provider: .zmx, lifetime: .persistent, zmxSessionId: compactText)),
                .terminal(.init(provider: .zmx, lifetime: .persistent, zmxSessionId: expandedText))
            ),
            (
                .webview(.init(url: URL(filePath: "/tmp/x"), title: compactText)),
                .webview(
                    .init(
                        url: URL(filePath: "/tmp/\(expandedText)"),
                        title: expandedText
                    )
                )
            ),
            (
                .bridgePanel(
                    .init(panelKind: .diffViewer, source: .branchDiff(head: compactText, base: compactText))
                ),
                .bridgePanel(
                    .init(panelKind: .diffViewer, source: .branchDiff(head: expandedText, base: expandedText))
                )
            ),
            (
                .codeViewer(.init(filePath: URL(filePath: "/tmp/x"), scrollToLine: nil)),
                .codeViewer(.init(filePath: URL(filePath: "/tmp/\(expandedText)"), scrollToLine: nil))
            ),
            (
                .unsupported(
                    .init(type: compactText, version: 1, rawState: .array([.string(compactText)]))
                ),
                .unsupported(
                    .init(
                        type: expandedText,
                        version: 1,
                        rawState: .object([expandedText: .array([.string(expandedText)])])
                    )
                )
            ),
        ]
        let compactMetadata = PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/x"),
            executionBackend: .docker(image: compactText),
            title: compactText,
            facets: .init(cwd: URL(filePath: "/tmp/x")),
            checkoutRef: compactText,
            note: compactText
        )
        let expandedMetadata = PaneMetadata(
            launchDirectory: URL(filePath: "/tmp/\(expandedText)"),
            executionBackend: .docker(image: expandedText),
            title: expandedText,
            facets: .init(cwd: URL(filePath: "/tmp/\(expandedText)")),
            checkoutRef: expandedText,
            note: expandedText
        )

        // Act / Assert
        for (compactContent, expandedContent) in contentPairs {
            let compactPaneGraph = PaneGraphState(
                pane: Pane(content: compactContent, metadata: compactMetadata)
            )
            let expandedPaneGraph = PaneGraphState(
                pane: Pane(content: expandedContent, metadata: expandedMetadata)
            )
            #expect(estimator.estimate(expandedPaneGraph) > estimator.estimate(compactPaneGraph))
        }
    }

    @Test("pane graph byte estimation arithmetic saturates on overflow")
    func paneGraphByteEstimationArithmeticSaturatesOnOverflow() {
        // Arrange / Act / Assert
        #expect(WorkspacePaneGraphPersistenceSnapshotByteEstimator.saturatedSum(Int.max, 1) == Int.max)
        #expect(WorkspacePaneGraphPersistenceSnapshotByteEstimator.saturatedProduct(Int.max, by: 2) == Int.max)
    }

    @Test("factory rejects repeated construction even when optional owners are empty")
    func rejectsRepeatedConstructionWithEmptyOwners() {
        // Arrange
        let factory = FactoryOwnerFixture().makeFactory()
        guard case .constructed = factory.constructParticipantSet() else {
            Issue.record("expected the first construction to succeed")
            return
        }

        // Act
        let repeatedResult = factory.constructParticipantSet()

        // Assert
        guard case .rejected(let rejection) = repeatedResult else {
            Issue.record("expected repeated construction to be rejected")
            return
        }
        #expect(rejection == .constructionAlreadyAttempted)
    }

    @Test("a later owner rejection does not install a partial participant set")
    func laterOwnerRejectionDoesNotInstallPartialSet() {
        // Arrange
        let fixture = FactoryOwnerFixture()
        let tabGraphState = TabGraphState(
            tabId: UUIDv7.generate(),
            allPaneIds: [],
            arrangements: []
        )
        fixture.workspaceTabGraphAtom.replaceStates([tabGraphState])
        let preconstruction = fixture.workspaceTabGraphAtom.makePersistenceSnapshotParticipant(
            limits: WorkspaceSnapshotParticipantFactoryPolicy.appDefault.fleetMembershipLimits
        )
        guard case .constructed = preconstruction else {
            Issue.record("expected failure fixture participant preconstruction to succeed")
            return
        }
        let factory = fixture.makeFactory()

        // Act
        let result = factory.constructParticipantSet()

        // Assert
        guard case .rejected(let rejection) = result else {
            Issue.record("expected the later tab graph participant construction to fail")
            return
        }
        #expect(
            rejection
                == .participantConstructionRejected(
                    participantID: .tabGraphs,
                    rejection: .duplicateCurrentKey
                ))
        #expect(factory.installedParticipantSet == nil)
    }

    @Test("constructed participants read from the exact backing owners supplied to the factory")
    func constructedParticipantsUseSuppliedBackingOwners() {
        // Arrange
        let workspaceID = UUIDv7.generate()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let workspaceIdentityAtom = WorkspaceIdentityAtom(
            workspaceId: workspaceID,
            workspaceName: "Factory owner",
            createdAt: createdAt
        )
        let workspaceWindowMemoryAtom = WorkspaceWindowMemoryAtom(sidebarWidth: 321, windowFrame: nil)
        let fixture = FactoryOwnerFixture(
            workspaceIdentityAtom: workspaceIdentityAtom,
            workspaceWindowMemoryAtom: workspaceWindowMemoryAtom
        )
        let factory = fixture.makeFactory()
        guard case .constructed(let participantSet) = factory.constructParticipantSet() else {
            Issue.record("expected the participant set to be constructed")
            return
        }
        workspaceIdentityAtom.setWorkspaceName("Mutated through supplied owner")
        workspaceWindowMemoryAtom.setSidebarWidth(456)
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let lease = WorkspaceStateSnapshotLease.open(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner
        )
        let singletonLimits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 1,
            maximumRawKeyBytes: 1
        )
        let identityParticipant = participantSet.participants[0]
        let windowParticipant = participantSet.participants[1]

        // Act
        let identityOpenResult = identityParticipant.open(lease: lease, limits: singletonLimits)
        let windowOpenResult = windowParticipant.open(lease: lease, limits: singletonLimits)
        let identityInspection = identityParticipant.inspectBaseSlot(lease: lease, slotCursor: 0)
        let windowInspection = windowParticipant.inspectBaseSlot(lease: lease, slotCursor: 0)

        // Assert
        #expect(identityOpenResult == .opened(baseMembershipCount: 1))
        #expect(windowOpenResult == .opened(baseMembershipCount: 1))
        guard case .item(let identityItem, _, _, _) = identityInspection else {
            Issue.record("expected workspace identity item")
            return
        }
        guard case .workspaceIdentity(let identity) = identityItem.item else {
            Issue.record("expected workspace identity payload")
            return
        }
        #expect(identity.workspaceID == workspaceID)
        #expect(identity.workspaceName == "Mutated through supplied owner")
        #expect(identity.createdAt == createdAt)

        guard case .item(let windowItem, _, _, _) = windowInspection else {
            Issue.record("expected workspace window memory item")
            return
        }
        guard case .windowMemory(let windowMemory) = windowItem.item else {
            Issue.record("expected workspace window memory payload")
            return
        }
        #expect(windowMemory.sidebarWidth == 456)
    }
}

private enum FactoryPolicyTestError: Error {
    case expectedConstructedPolicy
}

private func requireConstructedPolicy(
    _ result: WorkspaceSnapshotParticipantFactoryPolicyResult
) throws -> WorkspaceSnapshotParticipantFactoryPolicy {
    guard case .constructed(let policy) = result else {
        Issue.record("expected a constructed factory policy")
        throw FactoryPolicyTestError.expectedConstructedPolicy
    }
    return policy
}

@MainActor
private struct FactoryOwnerFixture {
    let workspaceIdentityAtom: WorkspaceIdentityAtom
    let workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom
    let repositoryTopologyAtom: RepositoryTopologyAtom
    let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    let workspaceTabShellAtom: WorkspaceTabShellAtom
    let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom

    init(
        workspaceIdentityAtom: WorkspaceIdentityAtom = WorkspaceIdentityAtom(),
        workspaceWindowMemoryAtom: WorkspaceWindowMemoryAtom = WorkspaceWindowMemoryAtom()
    ) {
        self.workspaceIdentityAtom = workspaceIdentityAtom
        self.workspaceWindowMemoryAtom = workspaceWindowMemoryAtom
        repositoryTopologyAtom = RepositoryTopologyAtom()
        workspacePaneGraphAtom = WorkspacePaneGraphAtom()
        workspaceDrawerCursorAtom = WorkspaceDrawerCursorAtom()
        workspaceTabCursorAtom = WorkspaceTabCursorAtom()
        workspaceTabShellAtom = WorkspaceTabShellAtom(cursorAtom: workspaceTabCursorAtom)
        workspaceTabGraphAtom = WorkspaceTabGraphAtom()
        workspaceArrangementCursorAtom = WorkspaceArrangementCursorAtom()
    }

    func makeFactory(
        policy: WorkspaceSnapshotParticipantFactoryPolicy = .appDefault
    ) -> WorkspacePersistenceSnapshotParticipantFactory {
        WorkspacePersistenceSnapshotParticipantFactory(
            workspaceIdentityAtom: workspaceIdentityAtom,
            workspaceWindowMemoryAtom: workspaceWindowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceDrawerCursorAtom: workspaceDrawerCursorAtom,
            workspaceTabShellAtom: workspaceTabShellAtom,
            workspaceTabCursorAtom: workspaceTabCursorAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            policy: policy
        )
    }
}
