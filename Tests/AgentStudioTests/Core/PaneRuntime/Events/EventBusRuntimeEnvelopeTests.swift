import Foundation
import Testing

@testable import AgentStudio

@Suite("EventBus RuntimeEnvelope replay")
struct EventBusRuntimeEnvelopeTests {
    @Test("replay keeps at most 256 envelopes per source")
    func replayBoundPerSource() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 256,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let paneA = PaneId.generateUUIDv7()
        let paneB = PaneId.generateUUIDv7()

        for seq in 1...300 {
            _ = await bus.post(makePaneEnvelope(paneId: paneA, seq: UInt64(seq)))
            _ = await bus.post(makePaneEnvelope(paneId: paneB, seq: UInt64(seq)))
        }

        let subscription = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "replayBoundPerSource")
        var iterator = subscription.makeAsyncIterator()
        var replayed: [RuntimeEnvelope] = []
        for _ in 0..<(256 * 2) {
            guard let envelope = await iterator.next() else {
                Issue.record("Expected replay payload for all retained runtime envelopes")
                return
            }
            replayed.append(envelope)
        }

        let paneASeqs = replayed.filter { $0.source == .pane(paneA) }.map(\.seq)
        let paneBSeqs = replayed.filter { $0.source == .pane(paneB) }.map(\.seq)
        #expect(paneASeqs.count == 256)
        #expect(paneBSeqs.count == 256)
        #expect(paneASeqs.first == 45)
        #expect(paneASeqs.last == 300)
        #expect(paneBSeqs.first == 45)
        #expect(paneBSeqs.last == 300)
    }

    @Test("replay bound is isolated per source")
    func replayBoundIsolationPerSource() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 256,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let hotPane = PaneId.generateUUIDv7()
        let coolPane = PaneId.generateUUIDv7()

        for seq in 1...400 {
            _ = await bus.post(makePaneEnvelope(paneId: hotPane, seq: UInt64(seq)))
        }
        for seq in 1...3 {
            _ = await bus.post(makePaneEnvelope(paneId: coolPane, seq: UInt64(seq)))
        }

        let subscription = await bus.subscribe(
            policy: .criticalUnbounded, subscriberName: "replayBoundIsolationPerSource")
        var iterator = subscription.makeAsyncIterator()
        var replayed: [RuntimeEnvelope] = []
        for _ in 0..<(256 + 3) {
            guard let envelope = await iterator.next() else {
                Issue.record("Expected replay payload for bounded + sparse sources")
                return
            }
            replayed.append(envelope)
        }

        let hotSeqs = replayed.filter { $0.source == .pane(hotPane) }.map(\.seq)
        let coolSeqs = replayed.filter { $0.source == .pane(coolPane) }.map(\.seq)
        #expect(hotSeqs.count == 256)
        #expect(hotSeqs.first == 145)
        #expect(hotSeqs.last == 400)
        #expect(coolSeqs == [1, 2, 3])
    }

    @Test("replay source eviction removes closed pane history")
    func replaySourceEvictionRemovesClosedPaneHistory() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 256,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let evictedPane = PaneId.generateUUIDv7()
        let retainedPane = PaneId.generateUUIDv7()

        _ = await bus.post(makePaneEnvelope(paneId: evictedPane, seq: 1))
        _ = await bus.post(makePaneEnvelope(paneId: retainedPane, seq: 2))
        await bus.evictReplay(sourceKey: EventSource.pane(evictedPane).description)

        let subscription = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "replaySourceEviction")
        var iterator = subscription.makeAsyncIterator()
        let envelope = await iterator.next()

        #expect(envelope?.source == .pane(retainedPane))
    }

    @Test("replay drops are counted when subscriber buffering is smaller than replay snapshot")
    func replayDropsAreCountedForSmallSubscriberBuffer() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 8,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let paneId = PaneId.generateUUIDv7()
        for seq in 1...8 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        let subscription = await bus.subscribe(policy: .lossyNewest(1), subscriberName: "smallReplayBuffer")
        let dropped = await bus.totalDroppedEvents()
        #expect(dropped > 0)
        withExtendedLifetime(subscription) {}
    }

    @Test("critical subscriber receives more than standard lossy limit without drops")
    func criticalSubscriberReceivesMoreThanStandardLossyLimit() async {
        let bus = EventBus<RuntimeEnvelope>()
        let paneId = PaneId.generateUUIDv7()
        let subscription = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "criticalBurst")

        for seq in 1...BusSubscriberPolicy.standardLossyBufferLimit + 1 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        var iterator = subscription.makeAsyncIterator()
        var received: [UInt64] = []
        for _ in 1...BusSubscriberPolicy.standardLossyBufferLimit + 1 {
            guard let envelope = await iterator.next() else {
                Issue.record("Expected critical subscriber to receive the whole burst")
                return
            }
            received.append(envelope.seq)
        }

        #expect(received.count == BusSubscriberPolicy.standardLossyBufferLimit + 1)
        #expect(await bus.totalDroppedEvents() == 0)
        let diagnostics = await bus.diagnosticsSnapshot()
        #expect(diagnostics.activeSubscribers.first?.liveDroppedCount == 0)
    }

    @Test("lossy subscriber drops are attributed to subscriber and policy")
    func lossySubscriberDropsAreAttributed() async {
        let bus = EventBus<RuntimeEnvelope>()
        let paneId = PaneId.generateUUIDv7()
        let subscription = await bus.subscribe(policy: .lossyNewest(1), subscriberName: "lossyDiagnostic")

        for seq in 1...8 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        let diagnostics = await bus.diagnosticsSnapshot()
        let subscriber = diagnostics.activeSubscribers.first
        #expect(subscriber?.subscriberName == "lossyDiagnostic")
        #expect(subscriber?.policy == .lossyNewest(1))
        #expect((subscriber?.liveDroppedCount ?? 0) > 0)
        #expect(subscriber?.failureClasses.contains(.lossyDrop) == true)
        withExtendedLifetime(subscription) {}
    }

    @Test("critical pressure diagnostics are visible for stalled consumers")
    func criticalPressureDiagnosticsAreVisible() async {
        let bus = EventBus<RuntimeEnvelope>()
        let paneId = PaneId.generateUUIDv7()
        let subscription = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "stalledCritical")

        for seq in 1...BusSubscriberPolicy.criticalPressureWarningLimit + 1 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        let diagnostics = await bus.diagnosticsSnapshot()
        let subscriber = diagnostics.activeSubscribers.first
        #expect((subscriber?.highWaterLag ?? 0) > UInt64(BusSubscriberPolicy.criticalPressureWarningLimit))
        #expect(subscriber?.failureClasses.contains(.criticalPressure) == true)
        #expect(subscriber?.requiresRecovery == true)
        withExtendedLifetime(subscription) {}
    }

    @Test("critical pressure diagnostics do not fire for drained consumers")
    func criticalPressureDiagnosticsDoNotFireForDrainedConsumers() async {
        let bus = EventBus<RuntimeEnvelope>()
        let paneId = PaneId.generateUUIDv7()
        let subscription = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "drainingCritical")
        var iterator = subscription.makeAsyncIterator()

        for seq in 1...BusSubscriberPolicy.criticalPressureWarningLimit + 1 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
            guard let envelope = await iterator.next() else {
                Issue.record("Expected draining critical subscriber to receive event \(seq)")
                return
            }
            #expect(envelope.seq == UInt64(seq))
        }

        let diagnostics = await bus.diagnosticsSnapshot()
        let subscriber = diagnostics.activeSubscribers.first
        #expect(subscriber?.failureClasses.contains(.criticalPressure) == false)
        #expect(subscriber?.requiresRecovery == false)
        #expect(subscriber?.highWaterLag == 1)
    }

    @Test("replay truncation status uses safe source labels")
    func replayTruncationStatusUsesSafeSourceLabels() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 2,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let paneId = PaneId.generateUUIDv7()
        for seq in 1...3 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        let subscription = await bus.subscribe(policy: .criticalUnbounded, subscriberName: "lateCritical")

        guard case .possiblyTruncated(let sourceLabels) = subscription.replayStatus else {
            Issue.record("Expected replay truncation status")
            return
        }
        #expect(sourceLabels.count == 1)
        #expect(sourceLabels.first?.hasPrefix("source-") == true)
        #expect(sourceLabels.first?.contains(paneId.uuidString) == false)

        let diagnostics = await bus.diagnosticsSnapshot()
        let subscriber = diagnostics.activeSubscribers.first
        #expect(subscriber?.failureClasses.contains(.replayPossiblyTruncated) == true)
        #expect(subscriber?.requiresRecovery == true)
    }

    @Test("recovery diagnostics survive subscriber termination")
    func recoveryDiagnosticsSurviveSubscriberTermination() async {
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 2,
                sourceKey: { envelope in
                    envelope.source.description
                }
            )
        )
        let paneId = PaneId.generateUUIDv7()
        for seq in 1...3 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        var subscription: EventBusSubscription<RuntimeEnvelope>? = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "terminatingCritical"
        )
        #expect(subscription?.replayStatus != .complete)
        subscription = nil

        await assertBusDrained(bus)

        let diagnostics = await bus.diagnosticsSnapshot()
        #expect(diagnostics.activeSubscribers.isEmpty)
        let retained = diagnostics.retainedRecoveryDiagnostics.first
        #expect(retained?.subscriberName == "terminatingCritical")
        #expect(retained?.failureClasses.contains(.replayPossiblyTruncated) == true)
        #expect(retained?.requiresRecovery == true)

        await bus.clearRetainedRecoveryDiagnostics()
        let clearedDiagnostics = await bus.diagnosticsSnapshot()
        #expect(clearedDiagnostics.retainedRecoveryDiagnostics.isEmpty)
    }

    @Test("performance debt tracks stalled delivery and returns to zero after consumption")
    func performanceDebtTracksStalledDeliveryAndConsumption() async {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        let bus = EventBus<RuntimeEnvelope>(performanceReporter: reporter)
        let paneId = PaneId.generateUUIDv7()
        let subscription = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "performanceDebtStalled"
        )

        for seq in 1...3 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        #expect(reporter.snapshot().eventBusActiveDeliveryDebt == 3)
        #expect(reporter.snapshot().eventBusActiveSubscriberCount == 1)

        var iterator = subscription.makeAsyncIterator()
        for expectedDebt in [2, 1, 0] {
            _ = await iterator.next()
            #expect(reporter.snapshot().eventBusActiveDeliveryDebt == UInt64(expectedDebt))
        }
    }

    @Test("lossy replacement drops stay separate from active delivery debt")
    func lossyReplacementDropsStaySeparateFromDebt() async {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        let bus = EventBus<RuntimeEnvelope>(performanceReporter: reporter)
        let paneId = PaneId.generateUUIDv7()
        let subscription = await bus.subscribe(
            policy: .lossyNewest(1),
            subscriberName: "performanceDebtLossy"
        )

        for seq in 1...8 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        let pressuredSnapshot = reporter.snapshot()
        #expect(pressuredSnapshot.eventBusActiveDeliveryDebt == 1)
        #expect(pressuredSnapshot.eventBusLiveDroppedCount == 7)

        var iterator = subscription.makeAsyncIterator()
        _ = await iterator.next()
        #expect(reporter.snapshot().eventBusActiveDeliveryDebt == 0)
    }

    @Test("replay delivery contributes debt while retained replay storage does not")
    func replayDeliveryContributesOnlyWhilePending() async {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        let bus = EventBus<RuntimeEnvelope>(
            replayConfiguration: .init(
                capacityPerSource: 4,
                sourceKey: { envelope in envelope.source.description }
            ),
            performanceReporter: reporter
        )
        let paneId = PaneId.generateUUIDv7()
        for seq in 1...4 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }

        let subscription = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "performanceDebtReplay"
        )
        #expect(reporter.snapshot().eventBusActiveDeliveryDebt == 4)

        var iterator = subscription.makeAsyncIterator()
        for _ in 1...4 {
            _ = await iterator.next()
        }

        #expect(reporter.snapshot().eventBusActiveDeliveryDebt == 0)
        #expect(await bus.diagnosticsSnapshot().activeSubscribers.first?.replayStatus == .complete)
    }

    @Test("subscriber termination retires undelivered debt without leaving active debt")
    func subscriberTerminationRetiresUndeliveredDebt() async {
        let reporter = RuntimeDeliveryPerformanceReporter()
        reporter.enable()
        let bus = EventBus<RuntimeEnvelope>(performanceReporter: reporter)
        let paneId = PaneId.generateUUIDv7()
        var subscription: EventBusSubscription<RuntimeEnvelope>? = await bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "performanceDebtTermination"
        )
        for seq in 1...3 {
            _ = await bus.post(makePaneEnvelope(paneId: paneId, seq: UInt64(seq)))
        }
        #expect(reporter.snapshot().eventBusActiveDeliveryDebt == 3)
        #expect(subscription != nil)

        subscription = nil
        await assertBusDrained(bus)

        let retiredSnapshot = reporter.snapshot()
        #expect(retiredSnapshot.eventBusActiveDeliveryDebt == 0)
        #expect(retiredSnapshot.eventBusRetiredUndeliveredCount == 3)
        #expect(retiredSnapshot.eventBusActiveSubscriberCount == 0)
    }

    private func makePaneEnvelope(paneId: PaneId, seq: UInt64) -> RuntimeEnvelope {
        .pane(
            PaneEnvelope.test(
                event: .terminal(.bellRang),
                paneId: paneId,
                paneKind: .terminal,
                source: .pane(paneId),
                seq: seq
            )
        )
    }
}
