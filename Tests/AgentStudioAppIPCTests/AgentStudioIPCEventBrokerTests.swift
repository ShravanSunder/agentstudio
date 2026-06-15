import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC event broker")
struct AgentStudioIPCEventBrokerTests {
    @Test("publishes permission notifications only to visible subscribers")
    func publishesPermissionNotificationsOnlyToVisibleSubscribers() async throws {
        let sequence = UUIDSequence()
        let broker = IPCEventBroker(makeSubscriptionId: sequence.next)
        let requester = makeEventPrincipal(boundPaneId: "pane-1")
        let scope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane("pane-2"),
            dataScope: .terminalInput
        )
        let approver = makeEventApprover(scope: scope)
        let unrelated = makeEventPrincipal(boundPaneId: "pane-3")
        let requesterSubscriber = RecordingEventSubscriber()
        let unrelatedSubscriber = RecordingEventSubscriber()
        _ = try await broker.subscribe(
            eventNames: [.permissionRequestCreated],
            principal: requester,
            subscriber: requesterSubscriber
        )
        _ = try await broker.subscribe(
            eventNames: [.permissionRequestCreated],
            principal: unrelated,
            subscriber: unrelatedSubscriber
        )
        let record = PermissionRecord(
            requestId: UUID(),
            requesterPrincipalId: requester.principalId,
            requestedScope: scope,
            reason: "paired pane",
            approvalRoute: .delegatedPrincipal(approver.principalId),
            state: .pending
        )
        let notification = PermissionEventProjector()
            .requestCreated(from: record, occurredAt: Date(timeIntervalSince1970: 1_800_000_000))
            .eventNotification

        let failures = await broker.publish(notification) { notification, principal in
            PermissionEventProjector().isVisible(notification, to: principal)
        }

        #expect(failures.isEmpty)
        let frames = await requesterSubscriber.deliveredFrames()
        let unrelatedFrames = await unrelatedSubscriber.deliveredFrames()
        #expect(frames.count == 1)
        #expect(unrelatedFrames.isEmpty)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(frames[0].utf8)) as? [String: Any])
        let params = try #require(object["params"] as? [String: Any])
        let payload = try #require(params["payload"] as? [String: Any])

        #expect(object["method"] as? String == "events.notification")
        #expect(object["id"] == nil)
        #expect(params["name"] as? String == "permission.requestCreated")
        #expect(payload["kind"] as? String == "permission")
    }

    @Test("unsubscribes only the owning principal subscription")
    func unsubscribesOnlyTheOwningPrincipalSubscription() async throws {
        let sequence = UUIDSequence()
        let broker = IPCEventBroker(makeSubscriptionId: sequence.next)
        let owner = makeEventPrincipal(boundPaneId: "pane-1")
        let unrelated = makeEventPrincipal(boundPaneId: "pane-2")
        let result = try await broker.subscribe(
            eventNames: [.terminalCommandFinished],
            principal: owner,
            subscriber: RecordingEventSubscriber()
        )

        await #expect(throws: IPCEventBrokerError.self) {
            try await broker.unsubscribe(result.subscriptionId, principal: unrelated)
        }
        try await broker.unsubscribe(result.subscriptionId, principal: owner)

        #expect(await broker.subscriptionCount() == 0)
    }

    @Test("removes slow subscribers that report backpressure")
    func removesSlowSubscribersThatReportBackpressure() async throws {
        let sequence = UUIDSequence()
        let broker = IPCEventBroker(makeSubscriptionId: sequence.next)
        let principal = makeEventPrincipal(boundPaneId: "pane-1")
        let subscriber = RecordingEventSubscriber(result: .backpressure)
        let result = try await broker.subscribe(
            eventNames: [.terminalCommandFinished],
            principal: principal,
            subscriber: subscriber
        )
        let notification = IPCEventNotification(
            eventId: UUID(),
            name: .terminalCommandFinished,
            occurredAt: Date(timeIntervalSince1970: 1_800_000_001),
            payload: .terminal(
                IPCTerminalEventPayload(
                    paneId: UUID(),
                    condition: .commandFinished,
                    exitCode: 0,
                    duration: 0.5
                )
            )
        )

        let failures = await broker.publish(notification) { _, _ in true }

        #expect(failures == [IPCEventDeliveryFailure(subscriptionId: result.subscriptionId, reason: .backpressure)])
        #expect(await broker.subscriptionCount() == 0)
        #expect(await subscriber.deliveredFrames().count == 1)
    }

    @Test("rejects unsupported event subscriptions")
    func rejectsUnsupportedEventSubscriptions() async throws {
        let broker = IPCEventBroker(allowedEventNames: [.permissionRequestCreated])

        await #expect(throws: IPCEventBrokerError.self) {
            try await broker.subscribe(
                eventNames: [.terminalCommandFinished],
                principal: makeEventPrincipal(boundPaneId: "pane-1"),
                subscriber: RecordingEventSubscriber()
            )
        }
    }

    @Test("rejects inbound client frames that impersonate server event notifications")
    func rejectsInboundClientFramesThatImpersonateServerEventNotifications() throws {
        #expect(throws: IPCEventBrokerError.self) {
            try IPCEventBroker.validateInboundClientNotification(method: "events.notification")
        }
        #expect(throws: IPCEventBrokerError.self) {
            try IPCEventBroker.validateInboundClientNotification(method: "permission.requestResolved")
        }
        #expect(throws: IPCEventBrokerError.self) {
            try IPCEventBroker.validateInboundClientNotification(method: "terminal.commandFinished")
        }

        try IPCEventBroker.validateInboundClientNotification(method: "terminal.send")
    }
}

private actor RecordingEventSubscriber: IPCEventSubscriber {
    private let result: IPCEventDeliveryResult
    private let shouldThrow: Bool
    private var frames: [String] = []

    init(result: IPCEventDeliveryResult = .delivered, shouldThrow: Bool = false) {
        self.result = result
        self.shouldThrow = shouldThrow
    }

    func deliver(_ frame: String) async throws -> IPCEventDeliveryResult {
        if shouldThrow {
            throw RecordingEventSubscriberError.deliveryFailed
        }
        frames.append(frame)
        return result
    }

    func deliveredFrames() -> [String] {
        frames
    }
}

private enum RecordingEventSubscriberError: Error {
    case deliveryFailed
}

private final class UUIDSequence: @unchecked Sendable {
    private let ids = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
    ]
    private let lock = NSLock()
    private var index = 0

    func next() -> UUID {
        lock.withLock {
            defer { index += 1 }
            return ids[index % ids.count]
        }
    }
}

private func makeEventPrincipal(boundPaneId: String) -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: UUID(),
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: boundPaneId, boundWorkspaceId: nil),
        approvalAuthority: .noApprovalAuthority
    )
}

private func makeEventApprover(scope: IPCPermissionScope) -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: UUID(),
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: "approver-pane", boundWorkspaceId: nil),
        approvalAuthority: .delegatedApprover(
            scopes: [
                IPCApprovalScope(
                    privilege: scope.privilege,
                    target: scope.target,
                    dataScope: scope.dataScope
                )
            ]
        )
    )
}
