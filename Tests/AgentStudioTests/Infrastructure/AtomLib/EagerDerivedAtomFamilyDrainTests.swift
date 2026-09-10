import Testing

@testable import AgentStudioInfrastructure

@MainActor
@Suite("Eager derived atom family drain", .serialized)
struct EagerDerivedAtomFamilyDrainTests {
    private func makeFamily() -> EagerDerivedAtomTestFamily {
        EagerDerivedAtomTestFamily(
            intentIdentity: \EagerDerivedAtomTestRequest.identity,
            combinePendingIntents: { _, latestRequest in latestRequest },
            prepare: { request, _ in .prepared(request) },
            project: projectEagerDerivedAtomTestRequest,
            classify: { candidate, currentValue in
                currentValue?.content == candidate.content
                    ? .equalCurrent(candidate)
                    : .immediateAccepted(candidate)
            }
        )
    }

    @Test("remove and drain revokes readiness before awaiting termination")
    func removeAndDrainRevokesReadinessBeforeAwaitingTermination() async {
        let gate = EagerDerivedAtomProjectionGate()
        let family = makeFamily()
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 1,
                gate: gate,
                projectionCount: EagerDerivedAtomTestCounter()
            ),
            for: 1
        )
        _ = await requireEagerDerivedAtomTestEvent("projection start") {
            await gate.waitUntilStarted()
        }

        family.remove(for: 1)
        #expect(family.atom(for: 1) == nil)
        #expect(family.currentValue(for: 1) == nil)
        async let drain: Void = family.removeAndDrain(for: 1)
        gate.release()
        await drain

        await family.removeAndDrain(for: 1)
        #expect(family.atom(for: 1) == nil)
    }

    @Test("family stop and drain awaits every removed and active slot")
    func stopAndDrainAwaitsRemovedAndActiveSlots() async {
        let firstGate = EagerDerivedAtomProjectionGate()
        let secondGate = EagerDerivedAtomProjectionGate()
        let family = makeFamily()
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 1,
                gate: firstGate,
                projectionCount: EagerDerivedAtomTestCounter()
            ),
            for: 1
        )
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 2,
                outputContent: 2,
                gate: secondGate,
                projectionCount: EagerDerivedAtomTestCounter()
            ),
            for: 2
        )
        _ = await requireEagerDerivedAtomTestEvent("first projection start") {
            await firstGate.waitUntilStarted()
        }
        _ = await requireEagerDerivedAtomTestEvent("second projection start") {
            await secondGate.waitUntilStarted()
        }

        family.remove(for: 1)
        family.stop()
        async let firstDrain: Void = family.stopAndDrain()
        async let secondDrain: Void = family.stopAndDrain()
        #expect(family.atoms.isEmpty)
        firstGate.release()
        secondGate.release()
        _ = await (firstDrain, secondDrain)

        await family.stopAndDrain()
        #expect(family.atoms.isEmpty)
    }

    @Test("remove and drain retains an awaiting-owner slot through synchronous revocation")
    func removeAndDrainRetainsAwaitingOwnerSlotThroughSynchronousRevocation() async {
        let awaitingOwner = EagerDerivedAtomTestSignal()
        var retainedToken: EagerDerivedAtomTestNode.CandidateToken?
        let family = EagerDerivedAtomTestFamily(
            intentIdentity: \EagerDerivedAtomTestRequest.identity,
            combinePendingIntents: { _, latestRequest in latestRequest },
            prepare: { request, _ in .prepared(request) },
            project: projectEagerDerivedAtomTestRequest,
            classify: { candidate, _ in .changedAwaitingOwner(candidate) },
            onAwaitingOwner: { _, token, _, _ in
                retainedToken = token
                awaitingOwner.signal()
            }
        )
        family.admit(
            makeEagerDerivedAtomTestRequest(
                identity: 1,
                outputContent: 1,
                projectionCount: EagerDerivedAtomTestCounter()
            ),
            for: 1
        )
        _ = await requireEagerDerivedAtomTestEvent("awaiting-owner candidate") {
            await awaitingOwner.wait()
        }
        let retainedAtom = family.atom(for: 1)

        await family.removeAndDrain(for: 1)

        #expect(family.atom(for: 1) == nil)
        #expect(retainedAtom?.hasUnsettledProjectionTasks == false)
        guard let retainedAtom, let retainedToken else {
            Issue.record("Expected the awaiting-owner atom and candidate token")
            return
        }
        #expect(
            !retainedAtom.settle(
                retainedToken,
                .accepted(EagerDerivedAtomTestValue(content: 1))
            ))
    }
}
