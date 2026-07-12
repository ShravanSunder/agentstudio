import Foundation
import Testing

@testable import AgentStudio

@Suite("FSEvent observation admission types")
struct DarwinFSEventObservationAdmissionTests {
    @Test("observation preserves closed watermark, completeness, and copied-byte custody")
    func observationPreservesClosedCaptureState() throws {
        let registration = makeRegistrationToken()
        let record = FSEventRecord(
            path: "/workspace/repo/file.swift",
            flags: [.itemCreated, .ownEvent],
            eventID: 41
        )

        let observation = try FSEventObservation(
            registration: registration,
            capturedAt: ContinuousClock.now,
            totalRecordCount: .exact(2),
            inspectedNativeRecordCount: 2,
            records: [record],
            unionedInspectedFlags: [.itemCreated, .ownEvent, .kernelDropped],
            eventIDWatermark: .inspected(first: 41, last: 42),
            completeness: .truncated([.copiedRecordLimitReached])
        )

        #expect(observation.copiedRecordCount == 1)
        #expect(observation.copiedUTF8ByteCount == record.path.utf8.count)
        #expect(observation.eventIDWatermark == .inspected(first: 41, last: 42))
        #expect(observation.completeness == .truncated([.copiedRecordLimitReached]))
    }

    @Test("invalid correlated observation states are rejected")
    func invalidObservationStatesAreRejected() {
        #expect(throws: FSEventObservationValidationError.self) {
            try FSEventObservation(
                registration: makeRegistrationToken(),
                capturedAt: ContinuousClock.now,
                totalRecordCount: .exact(1),
                inspectedNativeRecordCount: 1,
                records: [],
                unionedInspectedFlags: [.itemModified],
                eventIDWatermark: .noInspectedRecords,
                completeness: .complete
            )
        }
    }

    @Test("malformed native counts retain a valid bounded inspected prefix")
    func malformedNativeCountsValidateTheirPayload() throws {
        let record = FSEventRecord(
            path: "/workspace/repo/file.swift",
            flags: [.itemModified],
            eventID: 8
        )
        let valid = try FSEventObservation(
            registration: makeRegistrationToken(),
            capturedAt: ContinuousClock.now,
            totalRecordCount: .malformed(
                .nativeArrayCountMismatch(reportedRecordCount: 3, availableRecordCount: 1)
            ),
            inspectedNativeRecordCount: 1,
            records: [record],
            unionedInspectedFlags: [.itemModified],
            eventIDWatermark: .inspected(first: 8, last: 8),
            completeness: .truncated([.malformedNativeShape])
        )
        #expect(valid.inspectedNativeRecordCount == 1)

        #expect(throws: FSEventObservationValidationError.self) {
            try FSEventObservation(
                registration: makeRegistrationToken(),
                capturedAt: ContinuousClock.now,
                totalRecordCount: .malformed(
                    .nativeArrayUnavailable(reportedRecordCount: -1)
                ),
                inspectedNativeRecordCount: 1,
                records: [record],
                unionedInspectedFlags: [.itemModified],
                eventIDWatermark: .inspected(first: 8, last: 8),
                completeness: .truncated([.malformedNativeShape])
            )
        }
    }

    @Test("capture limits validate four independent positive bounds")
    func captureLimitsValidateIndependentBounds() throws {
        let limits = try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 17,
            maximumCopiedRecords: 13,
            maximumCopiedUTF8Bytes: 4097,
            maximumSinglePathUTF8Bytes: 1025
        )

        #expect(limits.maximumInspectedNativeRecords == 17)
        #expect(limits.maximumCopiedRecords == 13)
        #expect(limits.maximumCopiedUTF8Bytes == 4097)
        #expect(limits.maximumSinglePathUTF8Bytes == 1025)
        #expect(throws: FSEventCaptureLimitsValidationError.self) {
            try FSEventCaptureLimits(
                maximumInspectedNativeRecords: 0,
                maximumCopiedRecords: 13,
                maximumCopiedUTF8Bytes: 4097,
                maximumSinglePathUTF8Bytes: 1025
            )
        }
    }

    @Test("flag disposition retains joining recovery requirements")
    func flagDispositionJoinsIndependentRequirements() {
        let disposition = FSEventFlagDisposition(
            retainedFlags: [.kernelDropped, .rootChanged, .itemRenamed],
            pathTreatment: .ordinaryHint,
            recoveryRequirements: [.continuityRepair, .rootRevalidation],
            unsupportedRawBits: 0
        )

        #expect(disposition.recoveryRequirements.contains(.continuityRepair))
        #expect(disposition.recoveryRequirements.contains(.rootRevalidation))
        #expect(disposition.pathTreatment == .ordinaryHint)

        let unsupported = FSEventFlagDisposition(
            retainedFlags: [],
            pathTreatment: .diagnosticOnly,
            recoveryRequirements: [],
            unsupportedRawBits: 1 << 31
        )
        #expect(unsupported.recoveryRequirements.contains(.continuityRepair))
        #expect(unsupported.recoveryRequirements.contains(.unsupportedNativeFlags))
    }

    private func makeRegistrationToken() -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            registrationGeneration: 7,
            rootGeneration: 3
        )
    }
}
