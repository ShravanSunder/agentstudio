import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace pane creation context builder")
struct WorkspacePaneCreationContextBuilderTests {
    @Test("capture work and retained context stay fixed across a 300-tab fleet")
    func captureWorkStaysFixedAcrossFleetSize() throws {
        // Arrange
        let emptyIdentities = try #require(makePaneCreationIdentities())
        let fleetIdentities = try #require(makePaneCreationIdentities())
        let emptyQueries = WorkspacePaneCreationQuerySpy(tabCount: 0)
        let fleetQueries = WorkspacePaneCreationQuerySpy(tabCount: 300)

        // Act
        let emptyCapture = WorkspacePaneCreationContextBuilder(queries: emptyQueries)
            .capture(identities: emptyIdentities)
        let fleetCapture = WorkspacePaneCreationContextBuilder(queries: fleetQueries)
            .capture(identities: fleetIdentities)

        // Assert
        let emptyContext = try #require(emptyCapture.capturedContext)
        let fleetContext = try #require(fleetCapture.capturedContext)
        #expect(emptyQueries.queryCounts == fleetQueries.queryCounts)
        #expect(emptyQueries.queryCounts == WorkspacePaneCreationQuerySpy.expectedOnePaneQueryCounts)
        #expect(contextCardinality(emptyContext) == contextCardinality(fleetContext))
        #expect(emptyContext.appendTabContext.alignedTabOwners.count == Set<UUID>().count)
        #expect(fleetContext.appendTabContext.alignedTabOwners.count == 300)
        #expect(try insertionIndex(identities: emptyIdentities, context: emptyContext) == 0)
        #expect(try insertionIndex(identities: fleetIdentities, context: fleetContext) == 300)
    }

    @Test("capture rejects count and relevant-key membership divergence")
    func captureRejectsOwnerDivergence() throws {
        // Arrange
        let identities = try #require(makePaneCreationIdentities())
        let countMismatch = WorkspacePaneCreationQuerySpy(tabCount: 1)
        countMismatch.graphTabCountValue = 2
        let membershipMismatch = WorkspacePaneCreationQuerySpy(tabCount: 1)
        membershipMismatch.shellTabIDs.insert(identities.tabID)

        // Act / Assert
        #expect(
            WorkspacePaneCreationContextBuilder(queries: countMismatch)
                .capture(identities: identities)
                == .rejected(
                    .tabOwnerAlignment(
                        .tabOwnerCountMismatch(shellCount: 1, graphCount: 2)
                    )
                )
        )
        #expect(
            WorkspacePaneCreationContextBuilder(queries: membershipMismatch)
                .capture(identities: identities)
                == .rejected(
                    .tabOwnerAlignment(
                        .relevantTabMembershipMismatch(
                            tabID: identities.tabID,
                            shellContains: true,
                            graphContains: false
                        )
                    )
                )
        )
    }

    @Test("selected active tab adds only its two relevant membership queries")
    func selectedActiveTabAddsRelevantMembershipQueries() throws {
        // Arrange
        let identities = try #require(makePaneCreationIdentities())
        let activeTabID = UUIDv7.generate()
        let queries = WorkspacePaneCreationQuerySpy(tabCount: 300)
        queries.activeTabSelectionValue = .selected(activeTabID)
        queries.shellTabIDs.insert(activeTabID)
        queries.graphTabIDs.insert(activeTabID)

        // Act
        let capture = WorkspacePaneCreationContextBuilder(queries: queries)
            .capture(identities: identities)

        // Assert
        let context = try #require(capture.capturedContext)
        #expect(context.appendTabContext.activeTab == .selected(activeTabID))
        #expect(queries.queryCounts[.shellMembership] == 2)
        #expect(queries.queryCounts[.graphMembership] == 2)
        #expect(context.appendTabContext.alignedTabOwners.contains(activeTabID))
        #expect(!context.appendTabContext.alignedTabOwners.contains(identities.tabID))
    }
}

private struct WorkspacePaneCreationContextCardinality: Equatable {
    let paneOwners: Int
    let arrangements: Int
    let activeArrangements: Int
    let activePanes: Int
    let drawerCursors: Int
}

private func contextCardinality(
    _ context: WorkspacePaneCreationContext
) -> WorkspacePaneCreationContextCardinality {
    let appendContext = context.appendTabContext
    return WorkspacePaneCreationContextCardinality(
        paneOwners: appendContext.paneOwnerByPaneID.count,
        arrangements: appendContext.existingArrangementIDs.count,
        activeArrangements: appendContext.existingActiveArrangementTabIDs.count,
        activePanes: appendContext.existingActivePaneArrangementIDs.count,
        drawerCursors: appendContext.existingActiveDrawerChildKeys.count
    )
}

private func insertionIndex(
    identities: WorkspaceNewPaneTabIDs,
    context: WorkspacePaneCreationContext
) throws -> Int {
    let decision = WorkspacePaneCreationTransitionDecider.decide(
        request: WorkspacePaneCreationRequest(
            identities: identities,
            content: .ghosttyTerminal(lifetime: .temporary, zmxSessionID: .generateUUIDv7()),
            metadata: PaneMetadata(title: "Terminal"),
            residency: .active,
            tabName: "Terminal"
        ),
        context: context
    )
    guard case .changed(let transition) = decision else {
        throw WorkspacePaneCreationContextBuilderTestError.creationRejected
    }
    guard case .insert(_, let index) = transition.tabTransition.shell else {
        throw WorkspacePaneCreationContextBuilderTestError.missingShellInsertion
    }
    return index
}

private func makePaneCreationIdentities() -> WorkspaceNewPaneTabIDs? {
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

private enum WorkspacePaneCreationQuery: Hashable {
    case activeTab
    case shellCount
    case graphCount
    case shellMembership
    case graphMembership
    case paneExistence
    case drawerOwner
    case paneOwner
    case arrangementOwner
    case activeArrangementCursor
    case paneCursor
}

@MainActor
private final class WorkspacePaneCreationQuerySpy: WorkspacePaneCreationContextQuerying {
    static let expectedOnePaneQueryCounts: [WorkspacePaneCreationQuery: Int] = [
        .activeTab: 1,
        .shellCount: 1,
        .graphCount: 1,
        .shellMembership: 1,
        .graphMembership: 1,
        .paneExistence: 1,
        .drawerOwner: 1,
        .paneOwner: 1,
        .arrangementOwner: 1,
        .activeArrangementCursor: 1,
        .paneCursor: 1,
    ]

    var activeTabSelectionValue = WorkspaceExistingActiveTabSelection.noSelection
    var shellTabCountValue: Int
    var graphTabCountValue: Int
    var shellTabIDs: Set<UUID> = []
    var graphTabIDs: Set<UUID> = []
    private(set) var queryCounts: [WorkspacePaneCreationQuery: Int] = [:]

    init(tabCount: Int) {
        shellTabCountValue = tabCount
        graphTabCountValue = tabCount
    }

    var activeTabSelection: WorkspaceExistingActiveTabSelection {
        record(.activeTab)
        return activeTabSelectionValue
    }

    var tabShellCount: Int {
        record(.shellCount)
        return shellTabCountValue
    }

    var tabGraphCount: Int {
        record(.graphCount)
        return graphTabCountValue
    }

    func tabShellContains(_ tabID: UUID) -> Bool {
        record(.shellMembership)
        return shellTabIDs.contains(tabID)
    }

    func tabGraphContains(_ tabID: UUID) -> Bool {
        record(.graphMembership)
        return graphTabIDs.contains(tabID)
    }

    func paneExists(_: UUID) -> Bool {
        record(.paneExistence)
        return false
    }

    func parentPaneID(containingDrawer _: UUID) -> UUID? {
        record(.drawerOwner)
        return nil
    }

    func tabID(containingPane _: UUID) -> UUID? {
        record(.paneOwner)
        return nil
    }

    func tabID(containingArrangement _: UUID) -> UUID? {
        record(.arrangementOwner)
        return nil
    }

    func hasActiveArrangementCursor(tabID _: UUID) -> Bool {
        record(.activeArrangementCursor)
        return false
    }

    func hasPaneCursor(arrangementID _: UUID) -> Bool {
        record(.paneCursor)
        return false
    }

    private func record(_ query: WorkspacePaneCreationQuery) {
        queryCounts[query, default: 0] += 1
    }
}

extension WorkspacePaneCreationContextCapture {
    fileprivate var capturedContext: WorkspacePaneCreationContext? {
        guard case .captured(let context) = self else { return nil }
        return context
    }
}

private enum WorkspacePaneCreationContextBuilderTestError: Error {
    case creationRejected
    case missingShellInsertion
}
