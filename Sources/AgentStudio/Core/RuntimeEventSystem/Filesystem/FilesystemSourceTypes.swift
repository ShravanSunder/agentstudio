import Foundation

enum FilesystemSourceKind: Hashable, Sendable {
    case watchedParentMembership
    case registeredWorktreeContent
}

struct FilesystemSourceID: Hashable, Sendable {
    let kind: FilesystemSourceKind
    let rootID: UUID
}

struct FSEventRegistrationToken: Hashable, Sendable {
    let sourceID: FilesystemSourceID
    let registrationGeneration: UInt64
    let rootGeneration: UInt64
}

struct WatchRoot: Hashable, Sendable {
    let sourceID: FilesystemSourceID
    let declaredPath: String
    let resolvedPath: String
}

struct FSEventFlags: OptionSet, Hashable, Sendable {
    let rawValue: UInt32

    static let mustScanSubdirectories = Self(rawValue: 0x0000_0001)
    static let userDropped = Self(rawValue: 0x0000_0002)
    static let kernelDropped = Self(rawValue: 0x0000_0004)
    static let eventIDsWrapped = Self(rawValue: 0x0000_0008)
    static let historyDone = Self(rawValue: 0x0000_0010)
    static let rootChanged = Self(rawValue: 0x0000_0020)
    static let mount = Self(rawValue: 0x0000_0040)
    static let unmount = Self(rawValue: 0x0000_0080)
    static let itemCreated = Self(rawValue: 0x0000_0100)
    static let itemRemoved = Self(rawValue: 0x0000_0200)
    static let itemInodeMetadataModified = Self(rawValue: 0x0000_0400)
    static let itemRenamed = Self(rawValue: 0x0000_0800)
    static let itemModified = Self(rawValue: 0x0000_1000)
    static let itemFinderInfoModified = Self(rawValue: 0x0000_2000)
    static let itemOwnershipChanged = Self(rawValue: 0x0000_4000)
    static let itemXattrModified = Self(rawValue: 0x0000_8000)
    static let itemIsFile = Self(rawValue: 0x0001_0000)
    static let itemIsDirectory = Self(rawValue: 0x0002_0000)
    static let itemIsSymbolicLink = Self(rawValue: 0x0004_0000)
    static let ownEvent = Self(rawValue: 0x0008_0000)
    static let itemIsHardlink = Self(rawValue: 0x0010_0000)
    static let itemIsLastHardlink = Self(rawValue: 0x0020_0000)
    static let itemCloned = Self(rawValue: 0x0040_0000)
}

struct FSEventRecord: Equatable, Sendable {
    let path: String
    let flags: FSEventFlags
    let eventID: UInt64
}

enum FSEventMalformedRecordCount: Equatable, Sendable {
    case nativeArrayUnavailable(reportedRecordCount: Int)
    case nativeArrayCountMismatch(reportedRecordCount: Int, availableRecordCount: Int)
}

enum FSEventRecordCount: Equatable, Sendable {
    case exact(Int)
    case malformed(FSEventMalformedRecordCount)
}

enum FSEventIDWatermark: Equatable, Sendable {
    case noInspectedRecords
    case inspected(first: UInt64, last: UInt64)
}

struct FSEventCaptureTruncation: OptionSet, Equatable, Sendable {
    let rawValue: UInt16

    static let malformedNativeShape = Self(rawValue: 1 << 0)
    static let inspectedRecordLimitReached = Self(rawValue: 1 << 1)
    static let copiedRecordLimitReached = Self(rawValue: 1 << 2)
    static let copiedByteLimitReached = Self(rawValue: 1 << 3)
    static let singlePathByteLimitReached = Self(rawValue: 1 << 4)
    static let checkedArithmeticFailed = Self(rawValue: 1 << 5)
    static let pathConversionFailed = Self(rawValue: 1 << 6)
}

enum FSEventCaptureCompleteness: Equatable, Sendable {
    case complete
    case truncated(FSEventCaptureTruncation)
}

enum FSEventObservationValidationError: Error, Equatable {
    case invalidInspectedNativeRecordCount(Int)
    case invalidExactTotalRecordCount(Int)
    case invalidMalformedRecordCount(FSEventMalformedRecordCount)
    case malformedCountPayloadIsNotMismatched(reported: Int, available: Int)
    case inspectedCountExceedsTotal(inspected: Int, total: Int)
    case inspectedCountExceedsMalformedPrefix(inspected: Int, availablePrefix: Int)
    case copiedCountExceedsInspected(copied: Int, inspected: Int)
    case copiedByteCountOverflow
    case watermarkDoesNotMatchInspectedCount
    case completeCaptureRequiresExactTotal
    case completeCaptureDidNotRetainAllRecords
    case truncatedCaptureRequiresReason
}

struct FSEventObservation: Sendable {
    let registration: FSEventRegistrationToken
    let capturedAt: ContinuousClock.Instant
    let totalRecordCount: FSEventRecordCount
    let inspectedNativeRecordCount: Int
    let records: [FSEventRecord]
    let copiedUTF8ByteCount: Int
    let unionedInspectedFlags: FSEventFlags
    let eventIDWatermark: FSEventIDWatermark
    let completeness: FSEventCaptureCompleteness

    var copiedRecordCount: Int { records.count }

    init(
        registration: FSEventRegistrationToken,
        capturedAt: ContinuousClock.Instant,
        totalRecordCount: FSEventRecordCount,
        inspectedNativeRecordCount: Int,
        records: [FSEventRecord],
        unionedInspectedFlags: FSEventFlags,
        eventIDWatermark: FSEventIDWatermark,
        completeness: FSEventCaptureCompleteness
    ) throws {
        try Self.validateRecordCounts(
            totalRecordCount: totalRecordCount,
            inspectedNativeRecordCount: inspectedNativeRecordCount
        )
        guard records.count <= inspectedNativeRecordCount else {
            throw FSEventObservationValidationError.copiedCountExceedsInspected(
                copied: records.count,
                inspected: inspectedNativeRecordCount
            )
        }

        switch (inspectedNativeRecordCount, eventIDWatermark) {
        case (0, .noInspectedRecords), (1..., .inspected):
            break
        default:
            throw FSEventObservationValidationError.watermarkDoesNotMatchInspectedCount
        }

        switch completeness {
        case .complete:
            guard case .exact(let totalRecordCount) = totalRecordCount else {
                throw FSEventObservationValidationError.completeCaptureRequiresExactTotal
            }
            guard totalRecordCount == inspectedNativeRecordCount,
                records.count == inspectedNativeRecordCount
            else {
                throw FSEventObservationValidationError.completeCaptureDidNotRetainAllRecords
            }
        case .truncated(let reasons):
            guard !reasons.isEmpty else {
                throw FSEventObservationValidationError.truncatedCaptureRequiresReason
            }
        }

        let copiedUTF8ByteCount = try Self.checkedCopiedUTF8ByteCount(records: records)

        self.registration = registration
        self.capturedAt = capturedAt
        self.totalRecordCount = totalRecordCount
        self.inspectedNativeRecordCount = inspectedNativeRecordCount
        self.records = records
        self.copiedUTF8ByteCount = copiedUTF8ByteCount
        self.unionedInspectedFlags = unionedInspectedFlags
        self.eventIDWatermark = eventIDWatermark
        self.completeness = completeness
    }

    private static func validateRecordCounts(
        totalRecordCount: FSEventRecordCount,
        inspectedNativeRecordCount: Int
    ) throws {
        guard inspectedNativeRecordCount >= 0 else {
            throw FSEventObservationValidationError.invalidInspectedNativeRecordCount(
                inspectedNativeRecordCount
            )
        }
        switch totalRecordCount {
        case .exact(let totalRecordCount):
            guard totalRecordCount >= 0 else {
                throw FSEventObservationValidationError.invalidExactTotalRecordCount(
                    totalRecordCount
                )
            }
            guard inspectedNativeRecordCount <= totalRecordCount else {
                throw FSEventObservationValidationError.inspectedCountExceedsTotal(
                    inspected: inspectedNativeRecordCount,
                    total: totalRecordCount
                )
            }
        case .malformed(.nativeArrayUnavailable(let reportedRecordCount)):
            guard reportedRecordCount >= 0 else {
                throw FSEventObservationValidationError.invalidMalformedRecordCount(
                    .nativeArrayUnavailable(reportedRecordCount: reportedRecordCount)
                )
            }
            guard inspectedNativeRecordCount == 0 else {
                throw FSEventObservationValidationError.inspectedCountExceedsMalformedPrefix(
                    inspected: inspectedNativeRecordCount,
                    availablePrefix: 0
                )
            }
        case .malformed(
            .nativeArrayCountMismatch(let reportedRecordCount, let availableRecordCount)
        ):
            try validateCountMismatch(
                reportedRecordCount: reportedRecordCount,
                availableRecordCount: availableRecordCount,
                inspectedNativeRecordCount: inspectedNativeRecordCount
            )
        }
    }

    private static func validateCountMismatch(
        reportedRecordCount: Int,
        availableRecordCount: Int,
        inspectedNativeRecordCount: Int
    ) throws {
        let mismatch = FSEventMalformedRecordCount.nativeArrayCountMismatch(
            reportedRecordCount: reportedRecordCount,
            availableRecordCount: availableRecordCount
        )
        guard reportedRecordCount >= 0, availableRecordCount >= 0 else {
            throw FSEventObservationValidationError.invalidMalformedRecordCount(mismatch)
        }
        guard reportedRecordCount != availableRecordCount else {
            throw FSEventObservationValidationError.malformedCountPayloadIsNotMismatched(
                reported: reportedRecordCount,
                available: availableRecordCount
            )
        }
        let availablePrefix = min(reportedRecordCount, availableRecordCount)
        guard inspectedNativeRecordCount <= availablePrefix else {
            throw FSEventObservationValidationError.inspectedCountExceedsMalformedPrefix(
                inspected: inspectedNativeRecordCount,
                availablePrefix: availablePrefix
            )
        }
    }

    private static func checkedCopiedUTF8ByteCount(
        records: [FSEventRecord]
    ) throws -> Int {
        var copiedUTF8ByteCount = 0
        for record in records {
            let (nextCount, overflow) = copiedUTF8ByteCount.addingReportingOverflow(
                record.path.utf8.count
            )
            guard !overflow else {
                throw FSEventObservationValidationError.copiedByteCountOverflow
            }
            copiedUTF8ByteCount = nextCount
        }
        return copiedUTF8ByteCount
    }
}

enum FSEventPathTreatment: Equatable, Sendable {
    case ordinaryHint
    case rootSentinelIgnored
    case diagnosticOnly
}

struct FSEventRecoveryRequirements: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let continuityRepair = Self(rawValue: 1 << 0)
    static let rootRevalidation = Self(rawValue: 1 << 1)
    static let unsupportedNativeFlags = Self(rawValue: 1 << 2)
}

struct FSEventFlagDisposition: Equatable, Sendable {
    let retainedFlags: FSEventFlags
    let pathTreatment: FSEventPathTreatment
    let recoveryRequirements: FSEventRecoveryRequirements
    let unsupportedRawBits: UInt32

    init(
        retainedFlags: FSEventFlags,
        pathTreatment: FSEventPathTreatment,
        recoveryRequirements: FSEventRecoveryRequirements,
        unsupportedRawBits: UInt32
    ) {
        var effectiveRecoveryRequirements = recoveryRequirements
        if unsupportedRawBits != 0 {
            effectiveRecoveryRequirements.formUnion([
                .continuityRepair,
                .unsupportedNativeFlags,
            ])
        }
        self.retainedFlags = retainedFlags
        self.pathTreatment = pathTreatment
        self.recoveryRequirements = effectiveRecoveryRequirements
        self.unsupportedRawBits = unsupportedRawBits
    }
}

enum FSEventCaptureLimit: Equatable, Sendable {
    case inspectedNativeRecords
    case copiedRecords
    case copiedUTF8Bytes
    case singlePathUTF8Bytes
}

enum FSEventCaptureLimitsValidationError: Error, Equatable {
    case nonPositive(limit: FSEventCaptureLimit, value: Int)
}

struct FSEventCaptureLimits: Equatable, Sendable {
    let maximumInspectedNativeRecords: Int
    let maximumCopiedRecords: Int
    let maximumCopiedUTF8Bytes: Int
    let maximumSinglePathUTF8Bytes: Int

    init(
        maximumInspectedNativeRecords: Int,
        maximumCopiedRecords: Int,
        maximumCopiedUTF8Bytes: Int,
        maximumSinglePathUTF8Bytes: Int
    ) throws {
        let values: [(FSEventCaptureLimit, Int)] = [
            (.inspectedNativeRecords, maximumInspectedNativeRecords),
            (.copiedRecords, maximumCopiedRecords),
            (.copiedUTF8Bytes, maximumCopiedUTF8Bytes),
            (.singlePathUTF8Bytes, maximumSinglePathUTF8Bytes),
        ]
        if let invalidValue = values.first(where: { $0.1 <= 0 }) {
            throw FSEventCaptureLimitsValidationError.nonPositive(
                limit: invalidValue.0,
                value: invalidValue.1
            )
        }

        self.maximumInspectedNativeRecords = maximumInspectedNativeRecords
        self.maximumCopiedRecords = maximumCopiedRecords
        self.maximumCopiedUTF8Bytes = maximumCopiedUTF8Bytes
        self.maximumSinglePathUTF8Bytes = maximumSinglePathUTF8Bytes
    }
}
