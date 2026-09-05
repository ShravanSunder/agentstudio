import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

@MainActor
@Suite("Terminal activation scheduler", .serialized)
struct TerminalActivationSchedulerTests {
    enum ReferenceVersusGatedCase: CaseIterable, CustomTestStringConvertible {
        case ready
        case createFailure
        case attachFailure
        case retryReady

        var testDescription: String { String(describing: self) }

        func results(surfaceID: UUID) -> [TerminalActivationAttemptResult] {
            switch self {
            case .ready:
                return [.ready(surfaceID: surfaceID)]
            case .createFailure:
                return [
                    .failed(
                        failure: .surfaceCreationFailed(code: "surface-unavailable"),
                        retry: .doNotRetry
                    )
                ]
            case .attachFailure:
                return [
                    .failed(
                        failure: .surfaceAttachmentFailed(code: "exact-attach-rejected"),
                        retry: .doNotRetry
                    )
                ]
            case .retryReady:
                return [
                    .failed(
                        failure: .surfaceCreationFailed(code: "transient-create"),
                        retry: .retry
                    ),
                    .ready(surfaceID: surfaceID),
                ]
            }
        }
    }

    @Test("empty cohort settles without admission")
    func emptyCohortSettlesWithoutAdmission() async throws {
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: [])
            ),
            admissionPort: port
        )

        let settlement = await scheduler.activate()
        let diagnostics = await scheduler.diagnostics()

        #expect(settlement.outcomesByPaneID.isEmpty)
        #expect(port.admissions.isEmpty)
        #expect(diagnostics.maximumSimultaneousAdmissions == 0)
    }

    @Test("single member forwards exact opaque zmx identity")
    func singleMemberForwardsExactOpaqueZmxIdentity() async throws {
        let storedText = "opaque existing zmx identity ! '$`\\"
        let storedSessionID = try makeRestoredZmxSessionID(storedText)
        let descriptor = makeDescriptor(zmxSessionID: storedSessionID)
        let surfaceID = UUIDv7.generate()
        let port = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [descriptor.paneID: [.ready(surfaceID: surfaceID)]]
        )
        let scheduler = try await makeScheduler(entries: [descriptor], port: port)

        let settlement = await scheduler.activate()
        let admittedPane = try #require(port.admissions.first?.descriptor.pane)
        guard case .terminal(let admittedTerminalState) = admittedPane.content else {
            Issue.record("expected admitted descriptor to retain terminal content")
            return
        }

        #expect(admittedTerminalState.zmxSessionID == storedSessionID)
        #expect(admittedTerminalState.zmxSessionID.rawValue == storedText)
        #expect(await scheduler.memberState(for: descriptor.paneID) == .ready(surfaceID: surfaceID))
        #expect(settlement.outcomesByPaneID[descriptor.paneID] == .ready(surfaceID: surfaceID))
    }

    @Test("active visible then visible then hidden cohorts are admitted in priority order")
    func cohortPriorityOrderIsStable() async throws {
        let active = makeDescriptors(count: 4, priority: .activeVisible)
        let visible = makeDescriptors(count: 4, priority: .visible)
        let hidden = makeDescriptors(count: 4, priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: hidden + visible + active, port: port)

        let settlement = await scheduler.activate()

        #expect(
            port.admissions.map(\.descriptor.visibilityPriority)
                == Array(repeating: .activeVisible, count: 4)
                + Array(repeating: .visible, count: 4)
                + Array(repeating: .hidden, count: 4)
        )
        #expect(settlement.outcomesByPaneID.count == 12)
    }

    @Test("closed restore gate admits nothing before release and preserves stable priority order")
    func closedRestoreGatePreservesOrderUntilRelease() async throws {
        let active = makeDescriptor(priority: .activeVisible)
        let firstHidden = makeDescriptor(priority: .hidden)
        let secondHidden = makeDescriptor(priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        port.descriptorsByPaneID = Dictionary(
            uniqueKeysWithValues: [firstHidden, active, secondHidden].map { ($0.paneID, $0) }
        )
        let releaseSignal = ControlledTerminalActivationReleaseSignal()
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: [firstHidden, active, secondHidden])
            ),
            admissionPort: port,
            releaseSignal: releaseSignal
        )
        _ = await scheduler.installGeometryEligibility([firstHidden.paneID, active.paneID, secondHidden.paneID])
        let activation = Task { await scheduler.activate() }
        await releaseSignal.waitUntilSchedulerIsWaiting()

        #expect(port.admissions.isEmpty)

        await releaseSignal.release()
        let settlement = await activation.value

        #expect(
            port.admissions.map(\.descriptor.paneID)
                == [active.paneID, firstHidden.paneID, secondHidden.paneID]
        )
        #expect(settlement.outcomesByPaneID.count == 3)
    }

    @Test("restore admissions are serial with a yield after every completed attempt")
    func restoreAdmissionsAreSerialAndYielded() async throws {
        let descriptors = makeDescriptors(count: 3, priority: .activeVisible)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: descriptors, port: port)

        _ = await scheduler.activate()
        let diagnostics = await scheduler.diagnostics()

        #expect(diagnostics.maximumSimultaneousAdmissions == 1)
        #expect(diagnostics.workerCount == 1)
        #expect(diagnostics.yieldCount == descriptors.count)
        #expect(port.admissions.map(\.descriptor.paneID) == descriptors.map(\.paneID))
    }

    @Test("replacement while gated settles without admitting stale members")
    func replacementWhileGatedSettlesWithoutAdmission() async throws {
        let originalGeneration = nextCompositionGeneration()
        let replacementGeneration = nextCompositionGeneration()
        let descriptors = makeDescriptors(count: 3, priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        port.descriptorsByPaneID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.paneID, $0) })
        let releaseSignal = ControlledTerminalActivationReleaseSignal()
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: originalGeneration,
                input: TerminalActivationInput(entries: descriptors)
            ),
            admissionPort: port,
            releaseSignal: releaseSignal
        )
        let activation = Task { await scheduler.activate() }
        await releaseSignal.waitUntilSchedulerIsWaiting()

        await scheduler.cancelAndReplace(with: replacementGeneration)
        await releaseSignal.release()
        let settlement = await activation.value

        #expect(port.admissions.isEmpty)
        #expect(
            settlement.outcomesByPaneID.values.allSatisfy {
                $0 == .cancelledReplaced(replacement: replacementGeneration)
            }
        )
    }

    @Test(
        "gated restore is lossless against the reference scheduler",
        arguments: ReferenceVersusGatedCase.allCases
    )
    func gatedRestoreMatchesReference(testCase: ReferenceVersusGatedCase) async throws {
        let storedText = "opaque restored zmx identity ! '$`\\"
        let storedSessionID = try makeRestoredZmxSessionID(storedText)
        let descriptor = makeDescriptor(zmxSessionID: storedSessionID)
        let surfaceID = UUIDv7.generate()
        let results = testCase.results(surfaceID: surfaceID)
        let referencePort = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [descriptor.paneID: results]
        )
        let gatedPort = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [descriptor.paneID: results]
        )
        gatedPort.descriptorsByPaneID = [descriptor.paneID: descriptor]
        let referenceScheduler = try await makeScheduler(entries: [descriptor], port: referencePort)
        let releaseSignal = ControlledTerminalActivationReleaseSignal()
        let gatedScheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: [descriptor])
            ),
            admissionPort: gatedPort,
            releaseSignal: releaseSignal
        )
        _ = await gatedScheduler.installGeometryEligibility([descriptor.paneID])
        let gatedActivation = Task { await gatedScheduler.activate() }
        await releaseSignal.waitUntilSchedulerIsWaiting()

        let referenceSettlement = await referenceScheduler.activate()
        #expect(gatedPort.admissions.isEmpty)
        await releaseSignal.release()
        let gatedSettlement = await gatedActivation.value

        #expect(
            gatedSettlement.outcomesByPaneID[descriptor.paneID]
                == referenceSettlement.outcomesByPaneID[descriptor.paneID]
        )
        #expect(gatedPort.admissions.map(\.attempt) == referencePort.admissions.map(\.attempt))
        for admission in gatedPort.admissions {
            #expect(admission.descriptor.pane.terminalState?.zmxSessionID == storedSessionID)
            #expect(admission.descriptor.pane.terminalState?.zmxSessionID.rawValue == storedText)
        }
    }

    @Test("slot bound holds while queued work remains")
    func slotBoundHoldsWhileQueuedWorkRemains() async throws {
        let descriptors = makeDescriptors(count: 100, priority: .activeVisible)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: descriptors, port: port)
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)

        #expect(port.admissions.count == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        #expect(
            await scheduler.diagnostics().currentSimultaneousAdmissions
                == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)

        port.releaseFirstPendingAsReady()
        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1)

        #expect(
            await scheduler.diagnostics().maximumSimultaneousAdmissions
                == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)

        while port.admissions.count < descriptors.count {
            port.releaseAllPendingAsReady()
            await port.waitUntilStartedCount(
                min(
                    port.admissions.count + AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions,
                    descriptors.count))
        }
        port.releaseAllPendingAsReady()
        let settlement = await activation.value
        #expect(settlement.outcomesByPaneID.count == descriptors.count)
    }

    @Test("large cohorts settle with a fleet-sized worker bound", arguments: [100, 300])
    func largeCohortsSettleWithFleetSizedWorkerBound(memberCount: Int) async throws {
        let descriptors = makeDescriptors(count: memberCount, priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: descriptors, port: port)

        let settlement = await scheduler.activate()
        let diagnostics = await scheduler.diagnostics()

        #expect(settlement.outcomesByPaneID.count == memberCount)
        #expect(port.admissions.count == memberCount)
        #expect(
            diagnostics.maximumSimultaneousAdmissions
                <= AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions
        )
        #expect(diagnostics.workerCount <= AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
    }

    @Test("one requested retry requeues the same member and can become ready")
    func requestedRetryRequeuesSameMemberAndCanBecomeReady() async throws {
        let descriptor = makeDescriptor()
        let failure = TerminalActivationFailure.attachmentRejected(code: "transient-attach")
        let surfaceID = UUIDv7.generate()
        let port = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [
                descriptor.paneID: [
                    .failed(failure: failure, retry: .retry),
                    .ready(surfaceID: surfaceID),
                ]
            ]
        )
        let scheduler = try await makeScheduler(entries: [descriptor], port: port)

        let settlement = await scheduler.activate()

        #expect(port.admissions.map(\.attempt) == [1, 2])
        #expect(port.admissions.map(\.descriptor.paneID) == [descriptor.paneID, descriptor.paneID])
        #expect(settlement.outcomesByPaneID[descriptor.paneID] == .ready(surfaceID: surfaceID))
    }

    @Test("non-retryable failure exposes strict terminal failure state")
    func nonRetryableFailureExposesStrictTerminalFailureState() async throws {
        let descriptor = makeDescriptor()
        let failure = TerminalActivationFailure.surfaceCreationFailed(code: "surface-unavailable")
        let port = ImmediateTerminalActivationAdmissionPort(
            resultsByPaneID: [
                descriptor.paneID: [.failed(failure: failure, retry: .doNotRetry)]
            ]
        )
        let scheduler = try await makeScheduler(entries: [descriptor], port: port)

        let settlement = await scheduler.activate()
        let expectedRetry = TerminalActivationRetry.notRequested(attemptCount: 1)

        #expect(
            await scheduler.memberState(for: descriptor.paneID)
                == .failedTerminal(failure: failure, retry: expectedRetry)
        )
        #expect(
            settlement.outcomesByPaneID[descriptor.paneID]
                == .failedTerminal(failure: failure, retry: expectedRetry)
        )
    }

    @Test("scheduler marks a member attaching only after a claim is granted")
    func schedulerMarksAMemberAttachingOnlyAfterAClaimIsGranted() async throws {
        let descriptors = makeDescriptors(count: 3, priority: .activeVisible)
        let port = RejectingTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: descriptors, port: port)

        let settlement = await scheduler.activate()
        let diagnostics = await scheduler.diagnostics()

        #expect(diagnostics.maximumSimultaneousAdmissions == 0)
        #expect(diagnostics.currentSimultaneousAdmissions == 0)
        #expect(port.claimProposals.count == descriptors.count)
        #expect(settlement.outcomesByPaneID.count == descriptors.count)
    }

    @Test("a rejected claim resolves the member without a second attempt")
    func aRejectedClaimResolvesTheMemberWithoutASecondAttempt() async throws {
        let descriptor = makeDescriptor()
        let port = RejectingTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: [descriptor], port: port)

        let settlement = await scheduler.activate()

        #expect(port.claimProposals.map(\.paneID) == [descriptor.paneID])
        #expect(port.claimProposals.map(\.attempt) == [1])
        guard case .failedTerminal(_, let retry) = settlement.outcomesByPaneID[descriptor.paneID] else {
            Issue.record("expected a terminal failure outcome for a rejected claim")
            return
        }
        #expect(retry == .notRequested(attemptCount: 1))
    }

    @Test("replacement cancels queued and attaching members without accepting stale completions")
    func replacementCancelsQueuedAndAttachingMembers() async throws {
        let originalGeneration = nextCompositionGeneration()
        let replacementGeneration = nextCompositionGeneration()
        let descriptors = makeDescriptors(count: 8, priority: .hidden)
        let port = ControlledTerminalActivationAdmissionPort()
        port.descriptorsByPaneID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.paneID, $0) })
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: originalGeneration,
                input: TerminalActivationInput(entries: descriptors)
            ),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility(Set(descriptors.map(\.paneID)))
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        await scheduler.cancelAndReplace(with: replacementGeneration)
        port.releaseAllPendingAsReady()
        let settlement = await activation.value

        #expect(port.admissions.count == AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        #expect(
            settlement.outcomesByPaneID.values.allSatisfy {
                $0 == .cancelledReplaced(replacement: replacementGeneration)
            }
        )
    }

    @Test("aggregate settlement waits for every member outcome")
    func aggregateSettlementWaitsForEveryMemberOutcome() async throws {
        let descriptors = makeDescriptors(
            count: AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1,
            priority: .activeVisible
        )
        let port = ControlledTerminalActivationAdmissionPort()
        let completionProbe = TerminalActivationCompletionProbe()
        let scheduler = try await makeScheduler(entries: descriptors, port: port)
        let activation = Task {
            let settlement = await scheduler.activate()
            await completionProbe.record(settlement)
            return settlement
        }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        let releasedAdmission = try #require(port.releaseFirstPendingAsReady())
        await port.waitUntilStartedCount(
            AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1
        )
        let newlyStartedAdmission = try #require(port.admissions.last)

        #expect(!(await completionProbe.isCompleted))
        #expect(await scheduler.memberState(for: releasedAdmission.descriptor.paneID)?.isTerminal == true)
        #expect(await scheduler.memberState(for: newlyStartedAdmission.descriptor.paneID) == .attaching)

        port.releaseAllPendingAsReady()
        let settlement = await activation.value
        #expect(settlement.outcomesByPaneID.count == descriptors.count)
        #expect(await completionProbe.isCompleted)
    }

    @Test("priority promotion preempts queued hidden work")
    func priorityPromotionPreemptsQueuedHiddenWork() async throws {
        let active = makeDescriptors(
            count: AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions,
            priority: .activeVisible
        )
        let firstHidden = makeDescriptor(priority: .hidden)
        let promotedHidden = makeDescriptor(priority: .hidden)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: active + [firstHidden, promotedHidden], port: port)
        let activation = Task { await scheduler.activate() }

        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions)
        let promotion = await scheduler.promote(
            paneID: promotedHidden.paneID,
            to: .activeVisible
        )
        port.releaseFirstPendingAsReady()
        await port.waitUntilStartedCount(AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions + 1)

        #expect(promotion == .promoted(from: .hidden, to: .activeVisible))
        #expect(
            port.admissions[AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions].descriptor.paneID
                == promotedHidden.paneID)

        port.releaseAllPendingAsReady()
        await port.waitUntilStartedCount(active.count + 2)
        port.releaseAllPendingAsReady()
        _ = await activation.value
    }

    @Test(
        "one mixed cohort admits visible main then visible drawer then background main then background drawer"
    )
    func oneMixedCohortAdmitsVisibleMainThenVisibleDrawerThenBackgroundMainThenBackgroundDrawer() async throws {
        // Arrange: deliberately adversarial source order — the reverse of the required admission order.
        let backgroundDrawer = makeDrawerDescriptor(priority: .hidden)
        let backgroundMain = makeDescriptor(priority: .hidden)
        let visibleDrawerSibling = makeDrawerDescriptor(priority: .visible)
        let visibleDrawerActive = makeDrawerDescriptor(priority: .activeVisible)
        let visibleMainSibling = makeDescriptor(priority: .visible)
        let visibleMainActive = makeDescriptor(priority: .activeVisible)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(
            entries: [
                backgroundDrawer, backgroundMain, visibleDrawerSibling,
                visibleDrawerActive, visibleMainSibling, visibleMainActive,
            ],
            port: port
        )

        // Act
        _ = await scheduler.activate()

        // Assert
        #expect(
            port.admissions.map(\.descriptor.paneID) == [
                visibleMainActive.paneID,
                visibleMainSibling.paneID,
                visibleDrawerActive.paneID,
                visibleDrawerSibling.paneID,
                backgroundMain.paneID,
                backgroundDrawer.paneID,
            ]
        )
    }

    @Test("the active member leads its visible siblings within a class")
    func theActiveMemberLeadsItsVisibleSiblingsWithinAClass() async throws {
        // Arrange
        let mainSibling = makeDescriptor(priority: .visible)
        let mainActive = makeDescriptor(priority: .activeVisible)
        let drawerSibling = makeDrawerDescriptor(priority: .visible)
        let drawerActive = makeDrawerDescriptor(priority: .activeVisible)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(
            entries: [mainSibling, mainActive, drawerSibling, drawerActive],
            port: port
        )

        // Act
        _ = await scheduler.activate()

        // Assert
        let admittedPaneIDs = port.admissions.map(\.descriptor.paneID)
        let mainActiveIndex = try #require(admittedPaneIDs.firstIndex(of: mainActive.paneID))
        let mainSiblingIndex = try #require(admittedPaneIDs.firstIndex(of: mainSibling.paneID))
        let drawerActiveIndex = try #require(admittedPaneIDs.firstIndex(of: drawerActive.paneID))
        let drawerSiblingIndex = try #require(admittedPaneIDs.firstIndex(of: drawerSibling.paneID))
        #expect(mainActiveIndex < mainSiblingIndex)
        #expect(drawerActiveIndex < drawerSiblingIndex)
    }

    @Test("stable source ordinal breaks ties within one tier")
    func stableSourceOrdinalBreaksTiesWithinOneTier() async throws {
        // Arrange
        let tiedDescriptors = makeDescriptors(count: 6, priority: .hidden)
        let port = ImmediateTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(entries: tiedDescriptors, port: port)

        // Act
        _ = await scheduler.activate()

        // Assert
        #expect(port.admissions.map(\.descriptor.paneID) == tiedDescriptors.map(\.paneID))
    }

    @Test("maximum simultaneous admissions is one across the complete cohort")
    func maximumSimultaneousAdmissionsIsOneAcrossTheCompleteCohort() async throws {
        // Arrange: a single mixed-class cohort, not a homogeneous set, and a
        // port fake that suspends until released so the bound is observed
        // rather than inferred from a synchronous fake.
        let mainActive = makeDescriptor(priority: .activeVisible)
        let mainSibling = makeDescriptor(priority: .visible)
        let drawerActive = makeDrawerDescriptor(priority: .activeVisible)
        let backgroundMain = makeDescriptor(priority: .hidden)
        let backgroundDrawer = makeDrawerDescriptor(priority: .hidden)
        let port = ControlledTerminalActivationAdmissionPort()
        let scheduler = try await makeScheduler(
            entries: [mainActive, mainSibling, drawerActive, backgroundMain, backgroundDrawer],
            port: port
        )
        let activation = Task { await scheduler.activate() }

        // Act / Assert
        for expectedStartedCount in 1...5 {
            await port.waitUntilStartedCount(expectedStartedCount)
            #expect(await scheduler.diagnostics().currentSimultaneousAdmissions == 1)
            port.releaseFirstPendingAsReady()
        }
        _ = await activation.value

        #expect(await scheduler.diagnostics().maximumSimultaneousAdmissions == 1)
    }

    @Test(
        "a promoted batch is admitted as active main then main siblings then active drawer then drawer siblings"
    )
    func aPromotedBatchIsAdmittedAsActiveMainThenMainSiblingsThenActiveDrawerThenDrawerSiblings() async throws {
        // Arrange: drawer members get LOWER original ordinals than main
        // members, so a rank model that leaks the ordinal above the tier fails.
        let generation = try makeCompositionGeneration()
        let drawerSibling = makeDrawerDescriptor(priority: .hidden)
        let drawerActive = makeDrawerDescriptor(priority: .hidden)
        let mainSibling = makeDescriptor(priority: .hidden)
        let mainActive = makeDescriptor(priority: .hidden)
        let entries = [drawerSibling, drawerActive, mainSibling, mainActive]
        let port = RevisionAwareTerminalActivationAdmissionPort(generation: generation, descriptors: entries)
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(generation: generation, input: TerminalActivationInput(entries: entries)),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility(Set(entries.map(\.paneID)))
        port.recordCurrentVisibleQueuedTerminals(
            TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [mainActive.paneID],
                visibleMainSiblingPaneIDs: [mainSibling.paneID],
                activeDrawerPaneIDs: [drawerActive.paneID],
                visibleDrawerSiblingPaneIDs: [drawerSibling.paneID]
            )
        )

        // Act
        _ = await scheduler.activate()

        // Assert
        #expect(
            port.admissions.map(\.descriptor.paneID) == [
                mainActive.paneID, mainSibling.paneID, drawerActive.paneID, drawerSibling.paneID,
            ]
        )
    }

    @Test("an in-flight admission is never cancelled by a promotion")
    func anInFlightAdmissionIsNeverCancelledByAPromotion() async throws {
        // Arrange
        let generation = try makeCompositionGeneration()
        let inFlight = makeDescriptor(priority: .hidden)
        let promoted = makeDescriptor(priority: .hidden)
        let entries = [inFlight, promoted]
        let port = RevisionAwareTerminalActivationAdmissionPort(
            generation: generation,
            descriptors: entries,
            suspendsActivation: true
        )
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(generation: generation, input: TerminalActivationInput(entries: entries)),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility(Set(entries.map(\.paneID)))
        let activation = Task { await scheduler.activate() }
        await port.waitUntilStartedCount(1)

        // Act: promote the second member while the first is still in flight.
        port.recordCurrentVisibleQueuedTerminals(
            TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [promoted.paneID],
                visibleMainSiblingPaneIDs: [],
                activeDrawerPaneIDs: [],
                visibleDrawerSiblingPaneIDs: []
            )
        )
        port.releaseFirstPendingAsReady()
        await port.waitUntilStartedCount(2)
        port.releaseAllPendingAsReady()
        let settlement = await activation.value

        // Assert: the in-flight member completed uninterrupted; the
        // promotion only ever affected the next claim.
        #expect(port.admissions.map(\.descriptor.paneID) == [inFlight.paneID, promoted.paneID])
        #expect(settlement.outcomesByPaneID.count == 2)
    }

    @Test("a stale proposal receives the newer batch and claims nothing")
    func aStaleProposalReceivesTheNewerBatchAndClaimsNothing() async throws {
        // Arrange
        let generation = try makeCompositionGeneration()
        let descriptor = makeDescriptor(priority: .hidden)
        let entries = [descriptor]
        let port = RevisionAwareTerminalActivationAdmissionPort(
            generation: generation,
            descriptors: entries,
            suspendsActivation: true
        )
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(generation: generation, input: TerminalActivationInput(entries: entries)),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility(Set(entries.map(\.paneID)))
        let activation = Task { await scheduler.activate() }
        await port.waitUntilStartedCount(1)

        // Act: bump the port's revision while attempt 1 is suspended in
        // flight, then fail it retryably so attempt 2's stale-revision
        // proposal must reconcile against the newer snapshot before claiming.
        port.recordCurrentVisibleQueuedTerminals(
            TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [descriptor.paneID],
                visibleMainSiblingPaneIDs: [],
                activeDrawerPaneIDs: [],
                visibleDrawerSiblingPaneIDs: []
            )
        )
        port.releaseFirstPending(with: .failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry))
        await port.waitUntilStartedCount(2)
        port.releaseAllPendingAsReady()
        _ = await activation.value

        // Assert: exactly two mount effects occurred — attempt 1 (failed) and
        // attempt 2 (succeeded). The stale proposal in between claimed
        // nothing and produced no extra mount effect, though it did propose.
        #expect(port.admissions.map(\.attempt) == [1, 2])
        #expect(port.claimProposals.count == 3)
    }

    @Test("a queued member absent from the new current set returns to its background rank")
    func aQueuedMemberAbsentFromTheNewCurrentSetReturnsToItsBackgroundRank() async throws {
        // Arrange: `dropped`'s static priority (.activeVisible) would
        // otherwise rank it first, but the current visible queued set omits
        // it, so it must fall to its background rank, after the promoted
        // member.
        let generation = try makeCompositionGeneration()
        let dropped = makeDescriptor(priority: .activeVisible)
        let promoted = makeDescriptor(priority: .hidden)
        let entries = [dropped, promoted]
        let port = RevisionAwareTerminalActivationAdmissionPort(generation: generation, descriptors: entries)
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(generation: generation, input: TerminalActivationInput(entries: entries)),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility(Set(entries.map(\.paneID)))
        port.recordCurrentVisibleQueuedTerminals(
            TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [promoted.paneID],
                visibleMainSiblingPaneIDs: [],
                activeDrawerPaneIDs: [],
                visibleDrawerSiblingPaneIDs: []
            )
        )

        // Act
        _ = await scheduler.activate()

        // Assert
        #expect(port.admissions.map(\.descriptor.paneID) == [promoted.paneID, dropped.paneID])
    }

    @Test("a newly visible pane that is already attaching or ready starts no second attempt")
    func aNewlyVisiblePaneThatIsAlreadyAttachingOrReadyStartsNoSecondAttempt() async throws {
        // Arrange
        let generation = try makeCompositionGeneration()
        let alreadyReady = makeDescriptor(priority: .activeVisible)
        let stillQueued = makeDescriptor(priority: .hidden)
        let promotedLater = makeDescriptor(priority: .hidden)
        let entries = [alreadyReady, stillQueued, promotedLater]
        let port = RevisionAwareTerminalActivationAdmissionPort(
            generation: generation,
            descriptors: entries,
            suspendsActivation: true
        )
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(generation: generation, input: TerminalActivationInput(entries: entries)),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility(Set(entries.map(\.paneID)))
        let activation = Task { await scheduler.activate() }
        await port.waitUntilStartedCount(1)
        port.releaseFirstPendingAsReady()

        // Act: while the scheduler is between claims, record a snapshot
        // naming both the already-ready pane and a still-queued sibling.
        await port.waitUntilStartedCount(2)
        port.recordCurrentVisibleQueuedTerminals(
            TerminalVisibleQueuedTerminals(
                generation: generation,
                activeMainPaneIDs: [alreadyReady.paneID, promotedLater.paneID],
                visibleMainSiblingPaneIDs: [],
                activeDrawerPaneIDs: [],
                visibleDrawerSiblingPaneIDs: []
            )
        )
        // Releasing `stillQueued` here forces the scheduler's next proposal
        // (for `promotedLater`) to carry a stale revision, reconcile against
        // the snapshot above, and re-propose before it can claim — that
        // reconciliation must not touch `alreadyReady`, which is no longer
        // `.queued`.
        port.releaseAllPendingAsReady()
        await port.waitUntilStartedCount(3)
        port.releaseAllPendingAsReady()
        _ = await activation.value

        // Assert: the already-ready pane was claimed exactly once — the
        // snapshot naming it again did not start a second attempt.
        #expect(port.admissions.filter { $0.descriptor.paneID == alreadyReady.paneID }.count == 1)
    }

    @Test("members without installed geometry never propose and settle as waiting")
    func membersWithoutInstalledGeometryNeverProposeAndSettleAsWaiting() async throws {
        // Arrange: no `installGeometryEligibility` call at all — every member
        // stays `waitingForGeometry` for the whole life of this cohort.
        let descriptors = makeDescriptors(count: 3, priority: .activeVisible)
        let port = RejectingTerminalActivationAdmissionPort()
        port.descriptorsByPaneID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.paneID, $0) })
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: descriptors)
            ),
            admissionPort: port
        )

        // Act
        let settlement = await scheduler.activate()

        // Assert: zero proposals reached the port — a member without
        // installed geometry is never a `nextQueuedCandidate()` candidate —
        // and the settlement carries `.waitingForGeometry`, not a failure,
        // for every member (SPEC R5, R1's deferral half).
        #expect(port.claimProposals.isEmpty)
        #expect(settlement.outcomesByPaneID.count == descriptors.count)
        #expect(settlement.outcomesByPaneID.values.allSatisfy { $0 == .waitingForGeometry })
        #expect(await scheduler.diagnostics().maximumSimultaneousAdmissions == 0)
    }

    @Test("later geometry requeues the same member in the same generation and scheduler")
    func laterGeometryRequeuesTheSameMemberInTheSameGenerationAndScheduler() async throws {
        // Arrange
        let keepAlive = makeDescriptor(priority: .activeVisible)
        let waiting = makeDescriptor(priority: .activeVisible)
        let fixture = try await makeDrainingSchedulerWithOneWaitingMember(keepAlive: keepAlive, waiting: waiting)

        // Act: accept `waiting`'s geometry while the drain is still looping.
        let acceptedPaneIDs = await fixture.scheduler.acceptLaterGeometry(for: [waiting.paneID])
        fixture.port.releaseFirstPendingAsReady()
        await fixture.port.waitUntilStartedCount(2)
        fixture.port.releaseAllPendingAsReady()
        let settlement = await fixture.activation.value

        // Assert: the same scheduler, same generation, admitted `waiting`
        // immediately after `keepAlive` — no second fleet, no new scheduler.
        #expect(acceptedPaneIDs == [waiting.paneID])
        #expect(fixture.port.admissions.map(\.descriptor.paneID) == [keepAlive.paneID, waiting.paneID])
        #expect(fixture.port.admissions.map(\.attempt) == [1, 1])
        #expect(settlement.generation == fixture.generation)
        guard case .ready = settlement.outcomesByPaneID[waiting.paneID] else {
            Issue.record("expected the requeued member to reach ready")
            return
        }
    }

    @Test("later geometry does not consume the surface failure retry budget")
    func laterGeometryDoesNotConsumeTheSurfaceFailureRetryBudget() async throws {
        // Arrange: geometry is installed up front so `member` is `.queued`
        // from the start — this test is about a *duplicate* later-geometry
        // signal arriving mid-retry, not about the initial deferral.
        let generation = try makeCompositionGeneration()
        let member = makeDescriptor(priority: .activeVisible)
        let port = RevisionAwareTerminalActivationAdmissionPort(
            generation: generation,
            descriptors: [member],
            suspendsActivation: true
        )
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(generation: generation, input: TerminalActivationInput(entries: [member])),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility([member.paneID])
        let activation = Task { await scheduler.activate() }
        await port.waitUntilStartedCount(1)
        port.releaseFirstPending(with: .failed(failure: .surfaceCreationFailed(code: "transient"), retry: .retry))

        // Act: attempt 2 is already `.attaching` by the time this observes
        // it (`waitUntilStartedCount(2)` only resolves once `admissions`
        // records attempt 2's start) — a duplicate later-geometry signal for
        // an already-active member must be a pure no-op, not a reset.
        await port.waitUntilStartedCount(2)
        let acceptedPaneIDs = await scheduler.acceptLaterGeometry(for: [member.paneID])
        port.releaseAllPendingAsReady()
        let settlement = await activation.value

        // Assert: exactly two admissions ever occurred — attempt 1 (failed)
        // and attempt 2 (succeeded) — never a third.
        #expect(acceptedPaneIDs.isEmpty)
        #expect(port.admissions.map(\.attempt) == [1, 2])
        guard case .ready = settlement.outcomesByPaneID[member.paneID] else {
            Issue.record("expected attempt two to reach ready")
            return
        }
    }

    @Test("accepting geometry while draining joins the existing drain")
    func acceptingGeometryWhileDrainingJoinsTheExistingDrain() async throws {
        // Arrange: same shape as the requeue test above — this test's whole
        // point is the diagnostic proof — no second worker fleet is ever
        // spawned just because a later-geometry signal arrived mid-drain.
        let keepAlive = makeDescriptor(priority: .activeVisible)
        let waiting = makeDescriptor(priority: .activeVisible)
        let fixture = try await makeDrainingSchedulerWithOneWaitingMember(keepAlive: keepAlive, waiting: waiting)

        // Act
        _ = await fixture.scheduler.acceptLaterGeometry(for: [waiting.paneID])
        fixture.port.releaseFirstPendingAsReady()
        await fixture.port.waitUntilStartedCount(2)
        fixture.port.releaseAllPendingAsReady()
        _ = await fixture.activation.value

        // Assert: the original one-worker fleet handled both members.
        #expect(await fixture.scheduler.diagnostics().workerCount == 1)
    }

    /// The scheduler, its in-flight `activate()` task, the controlled port
    /// driving it, and its generation — returned together by
    /// `makeDrainingSchedulerWithOneWaitingMember` since every field is
    /// needed downstream.
    private struct DrainingSchedulerFixture {
        let scheduler: TerminalActivationScheduler
        let activation: Task<TerminalActivationSettlement, Never>
        let port: ControlledTerminalActivationAdmissionPort
        let generation: WorkspaceContentMountGeneration
    }

    /// Builds a scheduler over `[keepAlive, waiting]` with `keepAlive`
    /// already eligible and `waiting` still `waitingForGeometry`, then starts
    /// `activate()` and waits until `keepAlive`'s admission is suspended
    /// mid-claim on the controlled port it also builds. Shared by the two
    /// tests needing the drain still looping before `waiting`'s geometry
    /// arrives.
    private func makeDrainingSchedulerWithOneWaitingMember(
        keepAlive: TerminalActivationDescriptor,
        waiting: TerminalActivationDescriptor
    ) async throws -> DrainingSchedulerFixture {
        let generation = try makeCompositionGeneration()
        let port = ControlledTerminalActivationAdmissionPort()
        port.descriptorsByPaneID = Dictionary(uniqueKeysWithValues: [keepAlive, waiting].map { ($0.paneID, $0) })
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: generation, input: TerminalActivationInput(entries: [keepAlive, waiting])),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility([keepAlive.paneID])
        let activation = Task { await scheduler.activate() }
        await port.waitUntilStartedCount(1)
        return DrainingSchedulerFixture(
            scheduler: scheduler, activation: activation, port: port, generation: generation)
    }

    /// Builds a scheduler and immediately installs geometry eligibility for
    /// every entry, matching the production sequencing
    /// (`installTerminalGeometryAvailability` before `mount()`'s terminal
    /// lane activates). Every test using this helper is exercising admission
    /// order, retry, promotion, or concurrency behavior downstream of
    /// eligibility — not the waiting/deferral behavior itself, which the S6
    /// tests construct directly so they can withhold eligibility.
    private func makeScheduler(
        entries: [TerminalActivationDescriptor],
        port: some FakeTerminalActivationAdmissionPort
    ) async throws -> TerminalActivationScheduler {
        port.descriptorsByPaneID = Dictionary(uniqueKeysWithValues: entries.map { ($0.paneID, $0) })
        let scheduler = TerminalActivationScheduler(
            cohort: TerminalActivationCohort(
                generation: try makeCompositionGeneration(),
                input: TerminalActivationInput(entries: entries)
            ),
            admissionPort: port
        )
        _ = await scheduler.installGeometryEligibility(Set(entries.map(\.paneID)))
        return scheduler
    }

    private func makeCompositionGeneration() throws -> WorkspaceContentMountGeneration {
        nextCompositionGeneration()
    }

    private func nextCompositionGeneration() -> WorkspaceContentMountGeneration {
        WorkspaceContentMountGeneration()
    }

    private func makeDescriptors(
        count: Int,
        priority: TerminalActivationVisibilityPriority
    ) -> [TerminalActivationDescriptor] {
        (0..<count).map { _ in
            makeDescriptor(
                zmxSessionID: .generateUUIDv7(),
                priority: priority
            )
        }
    }

    private func makeDescriptor(
        zmxSessionID: ZmxSessionID = .generateUUIDv7(),
        priority: TerminalActivationVisibilityPriority = .activeVisible,
        hostPlacement: TerminalHostPlacementIdentity = .tab(tabID: UUIDv7.generate())
    ) -> TerminalActivationDescriptor {
        let pane = Pane(
            id: UUIDv7.generate(),
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: zmxSessionID
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: URL(filePath: "/tmp/terminal-activation"),
                title: "Activation test"
            )
        )
        return TerminalActivationDescriptor(
            pane: pane,
            visibilityPriority: priority,
            hostPlacement: hostPlacement
        )
    }

    private func makeDrawerDescriptor(
        priority: TerminalActivationVisibilityPriority = .activeVisible
    ) -> TerminalActivationDescriptor {
        makeDescriptor(
            priority: priority,
            hostPlacement: .drawer(
                tabID: UUIDv7.generate(),
                parentPaneID: PaneId(existingUUID: UUIDv7.generate()),
                drawerID: UUIDv7.generate()
            )
        )
    }
}
