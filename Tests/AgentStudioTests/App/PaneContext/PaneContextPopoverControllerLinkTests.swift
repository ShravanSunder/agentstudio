import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PaneContextPopoverControllerLinkTests {
    struct MemberCase: Sendable {
        let result: BridgeMemberRemoveResult
        let shown: String
    }
    nonisolated static let memberCases: [MemberCase] = [
        .init(result: .removed(removedContributions: [.person]), shown: "Link removed"),
        .init(result: .alreadyAbsent, shown: "Link already absent"),
        .init(result: .refusedProtectedCurrentDirectory, shown: "Cannot remove the current-directory worktree"),
        .init(result: .refusedNotAuthor, shown: "Link removal refused: not author"),
        .init(result: .staleOwner, shown: "Link removal refused: stale owner"),
        .init(result: .staleReceiver, shown: "Link removal refused: stale receiver"),
    ]
    @Test(arguments: memberCases)
    func everyImmediateMemberOutcomeIsVisible(scenario: MemberCase) async throws {
        let pane = PaneId.generateUUIDv7()
        let ports = PaneContextPopoverTestPorts(PaneContextPopoverShapingTests.detail(paneId: pane))
        let controller = makePopoverController(ports: ports)
        await controller.open(pane)
        await ports.configureMember(scenario.result)
        await controller.removeMember(UUIDv7.generate())
        #expect(controller.linkFeedback == scenario.shown)
        #expect(await ports.removals == [.person])
        controller.close()
        try await ports.finish()
    }

    struct SettlementCase: Sendable {
        let result: BridgePendingMemberRemovalSettlement
        let shown: String
    }
    nonisolated static let settlements: [SettlementCase] = [
        .init(result: .removed(removedContributions: [.person]), shown: "Link removed"),
        .init(result: .alreadyAbsent, shown: "Link already absent"),
        .init(result: .refusedProtectedCurrentDirectory, shown: "Cannot remove the current-directory worktree"),
        .init(result: .refusedNotAuthor, shown: "Link removal refused: not author"),
        .init(result: .staleOwner, shown: "Link removal refused: stale owner"),
        .init(result: .staleReceiver, shown: "Link removal refused: stale receiver"),
        .init(result: .draftKept(reason: .refused), shown: "Draft kept: refused"),
        .init(result: .draftKept(reason: .saveFailed), shown: "Draft kept: save failed"),
        .init(result: .draftKept(reason: .saveOutcomeUnknown), shown: "Draft kept: save outcome unknown"),
        .init(result: .membershipOutcomeUnknown, shown: "Membership outcome unknown"),
    ]
    @Test(arguments: settlements)
    func pendingRemovalUsesTheReturnedOperationAndShowsSettlement(scenario: SettlementCase) async throws {
        let pane = PaneId.generateUUIDv7()
        let operation = UUIDv7.generate()
        let ports = PaneContextPopoverTestPorts(PaneContextPopoverShapingTests.detail(paneId: pane))
        let controller = makePopoverController(ports: ports)
        await controller.open(pane)
        await ports.configureMember(.pendingDraftSettlement(operationId: operation), settlement: scenario.result)
        await controller.removeMember(UUIDv7.generate())
        #expect(await ports.pendingOperations == [operation])
        #expect(controller.linkFeedback == scenario.shown)
        controller.close()
        try await ports.finish()
    }

    @Test
    func pendingDraftSettlementIsShownBeforeItsSettlementArrives() async throws {
        let pane = PaneId.generateUUIDv7()
        let operation = UUIDv7.generate()
        let ports = PaneContextPopoverTestPorts(PaneContextPopoverShapingTests.detail(paneId: pane))
        let controller = makePopoverController(ports: ports)
        await controller.open(pane)
        await ports.configureMember(
            .pendingDraftSettlement(operationId: operation), settlement: .removed(removedContributions: [.person]))
        await ports.holdPendingSettlement()
        let removal = Task { await controller.removeMember(UUIDv7.generate()) }
        try await ports.settlements.expectNext(in: 0, .awaiting)
        #expect(controller.linkFeedback == "Pending draft settlement")
        await ports.releasePendingSettlement()
        await removal.value
        #expect(controller.linkFeedback == "Link removed")
        controller.close()
        try await ports.finish()
    }

    struct ReferenceCase: Sendable {
        let result: BridgePullRequestReferenceRemoveResult
        let shown: String
    }
    @Test(arguments: [
        ReferenceCase(result: .removed(removedContributions: [.person]), shown: "Pull request reference removed"),
        .init(result: .alreadyAbsent, shown: "Pull request reference already absent"),
        .init(result: .refusedNotAuthor, shown: "Reference removal refused: not author"),
        .init(result: .staleOwner, shown: "Reference removal refused: stale owner"),
        .init(result: .staleReceiver, shown: "Reference removal refused: stale receiver"),
    ])
    func everyReferenceOutcomeIsVisible(scenario: ReferenceCase) async throws {
        let pane = PaneId.generateUUIDv7()
        let ports = PaneContextPopoverTestPorts(PaneContextPopoverShapingTests.detail(paneId: pane))
        let controller = makePopoverController(ports: ports)
        await controller.open(pane)
        await ports.configureReference(scenario.result)
        await controller.removePullRequestReference(
            try .init(host: "github.com", owner: "org", repository: "repo", number: 7))
        #expect(controller.linkFeedback == scenario.shown)
        #expect(await ports.removals == [.person])
        controller.close()
        try await ports.finish()
    }

    @Test(arguments: [BridgeLinkPortFailure.unavailable, .outcomeUnknown])
    func preDispatchAndUnknownCommitFailuresStayDistinct(failure: BridgeLinkPortFailure) async throws {
        let pane = PaneId.generateUUIDv7()
        let ports = PaneContextPopoverTestPorts(PaneContextPopoverShapingTests.detail(paneId: pane))
        let controller = makePopoverController(ports: ports)
        await controller.open(pane)
        await ports.configureLinkFailure(failure)
        await controller.removeMember(UUIDv7.generate())
        #expect(
            controller.linkFeedback
                == (failure == .unavailable ? "Link removal unavailable" : "Link removal outcome unknown"))
        await controller.removePullRequestReference(
            try .init(host: "github.com", owner: "org", repository: "repo", number: 7))
        #expect(
            controller.linkFeedback
                == (failure == .unavailable ? "Link removal unavailable" : "Link removal outcome unknown"))
        controller.close()
        try await ports.finish()
    }
}
