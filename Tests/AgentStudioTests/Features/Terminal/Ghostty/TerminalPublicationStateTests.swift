import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioTerminal

extension TerminalLocalActionAccumulatorTests {
    @Test(
        "publication acknowledgement sequences preserve the ungated terminal state",
        arguments: TerminalPublicationSequence.allCases
    )
    func publicationAcknowledgementSequencesPreserveReferenceEndState(
        sequence: TerminalPublicationSequence
    ) throws {
        let recorder = PublicationDrainRequestRecorder()
        let accumulator = TerminalLocalActionAccumulator(
            scheduleDrain: recorder.record,
            scheduleFollowUpDrain: recorder.record
        )
        let surfaceID = UUIDv7.generate()
        var publishedTitles: [String] = []

        func drainTitle(successfully: Bool) throws {
            let batch = try #require(accumulator.beginDrain(for: surfaceID, lane: .title))
            let projection = try #require(batch.titleMetadata)
            if successfully {
                guard case .titleChanged(let title) = projection.runtimeTitle else {
                    Issue.record("Expected a title projection")
                    return
                }
                publishedTitles.append(title)
                accumulator.acknowledgeSuccessfulTitlePublication(projection, for: surfaceID)
            } else {
                accumulator.restoreUnacknowledgedPublications(from: batch)
            }
        }

        switch sequence {
        case .unknown:
            #expect(accumulator.offer(.titleChanged("A"), for: surfaceID) == .scheduled)
            try drainTitle(successfully: true)
            #expect(accumulator.finishDrain(for: surfaceID, lane: .title) == .idle)
        case .pendingEqual:
            #expect(accumulator.offer(.titleChanged("A"), for: surfaceID) == .scheduled)
            #expect(accumulator.offer(.titleChanged("A"), for: surfaceID) == .equalSuppressed)
            try drainTitle(successfully: true)
            #expect(accumulator.finishDrain(for: surfaceID, lane: .title) == .idle)
        case .pendingReplacement:
            accumulator.offer(.titleChanged("A"), for: surfaceID)
            #expect(accumulator.offer(.titleChanged("B"), for: surfaceID) == .coalesced)
            try drainTitle(successfully: true)
            _ = accumulator.finishDrain(for: surfaceID, lane: .title)
        case .committedEqual, .committedChange:
            accumulator.offer(.titleChanged("A"), for: surfaceID)
            try drainTitle(successfully: true)
            _ = accumulator.finishDrain(for: surfaceID, lane: .title)
            let nextTitle = sequence == .committedEqual ? "A" : "B"
            let result = accumulator.offer(.titleChanged(nextTitle), for: surfaceID)
            if sequence == .committedEqual {
                #expect(result == .equalSuppressed)
            } else {
                #expect(result == .scheduled)
                try drainTitle(successfully: true)
                _ = accumulator.finishDrain(for: surfaceID, lane: .title)
            }
        case .ackRacingNewerPending:
            accumulator.offer(.titleChanged("A"), for: surfaceID)
            let appliedBatch = try #require(accumulator.beginDrain(for: surfaceID, lane: .title))
            accumulator.offer(.titleChanged("B"), for: surfaceID)
            publishedTitles.append("A")
            accumulator.acknowledgeSuccessfulTitlePublication(
                try #require(appliedBatch.titleMetadata),
                for: surfaceID
            )
            #expect(accumulator.finishDrain(for: surfaceID, lane: .title) == .followUpScheduled)
            try drainTitle(successfully: true)
            _ = accumulator.finishDrain(for: surfaceID, lane: .title)
        case .failedApplyRetry, .schedulerCancellationAfterAdmission:
            accumulator.offer(.titleChanged("A"), for: surfaceID)
            try drainTitle(successfully: false)
            #expect(accumulator.finishDrain(for: surfaceID, lane: .title) == .followUpScheduled)
            try drainTitle(successfully: true)
            _ = accumulator.finishDrain(for: surfaceID, lane: .title)
        case .staleGeneration, .close, .schedulerCancellationBeforeMainActorAdmission:
            accumulator.offer(.titleChanged("A"), for: surfaceID)
            accumulator.removeSurface(surfaceID)
            #expect(accumulator.offer(.titleChanged("A"), for: surfaceID) == .scheduled)
            try drainTitle(successfully: true)
            _ = accumulator.finishDrain(for: surfaceID, lane: .title)
        }

        #expect(publishedTitles.last == sequence.referenceEndState)
    }

    @Test("committed equal activity aggregate does not create another MainActor claim")
    func committedEqualActivityDoesNotCreateAnotherMainActorClaim() throws {
        let recorder = PublicationDrainRequestRecorder()
        let accumulator = TerminalLocalActionAccumulator(scheduleDrain: recorder.record)
        let surfaceID = UUIDv7.generate()
        let scrollbarState = ScrollbarState(top: 80, bottom: 100, total: 100)

        #expect(
            accumulator.offer(.scrollbar(scrollbarState, observedAtMilliseconds: 7), for: surfaceID)
                == .scheduled
        )
        let appliedBatch = try #require(accumulator.beginDrain(for: surfaceID, lane: .immediate))
        accumulator.acknowledgeSuccessfulActivityPublication(
            try #require(appliedBatch.activity),
            for: surfaceID
        )
        #expect(accumulator.finishDrain(for: surfaceID, lane: .immediate) == .idle)
        #expect(
            accumulator.offer(.scrollbar(scrollbarState, observedAtMilliseconds: 7), for: surfaceID)
                == .equalSuppressed
        )
        #expect(recorder.requestCount == 1)
    }

    @Test("CWD publication admission retries failure and suppresses only committed equality")
    func cwdPublicationAdmissionRetriesFailureAndSuppressesCommittedEquality() {
        let accumulator = TerminalLocalActionAccumulator { _, _ in }
        let surfaceID = UUIDv7.generate()

        #expect(accumulator.admitCWDPublication("/tmp/project", for: surfaceID) == .scheduled)
        accumulator.recordFailedCWDPublication("/tmp/project", for: surfaceID)
        #expect(accumulator.admitCWDPublication("/tmp/project", for: surfaceID) == .scheduled)
        accumulator.acknowledgeSuccessfulCWDPublication("/tmp/project", for: surfaceID)
        #expect(accumulator.admitCWDPublication("/tmp/./project", for: surfaceID) == .equalSuppressed)
        #expect(accumulator.admitCWDPublication("/tmp/other", for: surfaceID) == .scheduled)
        accumulator.removeSurface(surfaceID)
        #expect(accumulator.admitCWDPublication("/tmp/project", for: surfaceID) == .scheduled)
    }
}

enum TerminalPublicationSequence: String, CaseIterable, Sendable {
    case unknown
    case pendingEqual
    case pendingReplacement
    case committedEqual
    case committedChange
    case ackRacingNewerPending
    case failedApplyRetry
    case staleGeneration
    case close
    case schedulerCancellationBeforeMainActorAdmission
    case schedulerCancellationAfterAdmission

    var referenceEndState: String {
        switch self {
        case .pendingReplacement, .committedChange, .ackRacingNewerPending: "B"
        default: "A"
        }
    }
}

private final class PublicationDrainRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [TerminalLocalDrainRequest] = []

    var requestCount: Int { lock.withLock { requests.count } }

    func record(_: UUID, _ request: TerminalLocalDrainRequest) {
        lock.withLock { requests.append(request) }
    }
}
