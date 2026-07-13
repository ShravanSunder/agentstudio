import CoreServices
import Foundation

enum DarwinFSEventObservationCaptureRejection: Equatable, Sendable {
    case leaseIdentityExhausted
    case closing
    case callbackAuthority(FilesystemObservationCallbackAuthorityRejection)
    case mailbox(FilesystemObservationCallbackMailboxRejection)
    case invalidReportedEventCount(Int)
    case invalidObservation(FSEventObservationValidationError)
}

enum DarwinFSEventObservationCaptureResult: Sendable {
    case admitted(
        offer: FilesystemObservationOffer,
        admission: FilesystemObservationCallbackAdmissionResult
    )
    case ignoredEmptyCallback
    case rejected(DarwinFSEventObservationCaptureRejection)
}

struct DarwinFSEventNativeCallbackInput {
    let capturedAt: ContinuousClock.Instant
    let reportedEventCount: Int
    let eventPaths: UnsafeMutableRawPointer?
    let eventFlags: UnsafeBufferPointer<FSEventStreamEventFlags>
    let eventIDs: UnsafeBufferPointer<FSEventStreamEventId>
}

final class DarwinFSEventObservationAdapter: @unchecked Sendable {
    let controlBlock: FSEventRegistrationControlBlock
    private let callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort

    init(
        controlBlock: FSEventRegistrationControlBlock,
        callbackAdmissionPort: FilesystemObservationCallbackAdmissionPort
    ) {
        self.controlBlock = controlBlock
        self.callbackAdmissionPort = callbackAdmissionPort
    }

    func capture(
        input: DarwinFSEventNativeCallbackInput
    ) -> DarwinFSEventObservationCaptureResult {
        let callbackLease: FSEventCallbackLease
        switch controlBlock.acquireCallbackLease() {
        case .acquired(let lease): callbackLease = lease
        case .leaseIdentityExhausted: return .rejected(.leaseIdentityExhausted)
        case .closing: return .rejected(.closing)
        }
        defer { _ = callbackLease.release() }

        return callbackAdmissionPort.admit(
            using: callbackLease,
            preflight: FilesystemObservationCallbackPreflight(
                captureLimits: controlBlock.captureLimits
            )
        ) {
            DarwinFSEventObservationCapture.makeOffer(
                controlBlock: self.controlBlock,
                input: input
            )
        }
    }
}

/// Bounded native callback capture for the dormant W1b observation adapter.
///
/// This type does not publish to the legacy `FSEventStreamClient` batch stream.
/// It acquires one generation-bound callback lease, inspects only the bounded
/// native prefix, copies only within the independent record and byte limits,
/// and admits the opaque offer to the generation mailbox before releasing its
/// callback lease.
enum DarwinFSEventObservationCapture {
    enum OfferResult: Sendable {
        case offer(FilesystemObservationOffer)
        case ignoredEmptyCallback
        case rejected(DarwinFSEventObservationCaptureRejection)
    }
    private enum BoundedPathCapture {
        case path(String, utf8ByteCount: Int)
        case exceedsLimit(FSEventCaptureTruncation)
        case conversionFailed
    }

    private struct NativeShape {
        let pathArray: CFArray?
        let totalRecordCount: FSEventRecordCount
        let availableNativePrefixCount: Int
        let initialTruncation: FSEventCaptureTruncation
    }

    private struct CapturedObservationComponents {
        let registration: FSEventRegistrationToken
        let capturedAt: ContinuousClock.Instant
        let totalRecordCount: FSEventRecordCount
        let inspectedNativeRecordCount: Int
        let records: [FSEventRecord]
        let unionedInspectedFlags: FSEventFlags
        let eventIDWatermark: FSEventIDWatermark
        let truncation: FSEventCaptureTruncation
    }

    private enum RecoveryAccumulator {
        case authoritative
        case recovery(FilesystemRecoveryEvidence)

        mutating func require(_ evidence: FilesystemRecoveryEvidence) {
            switch self {
            case .authoritative:
                self = .recovery(evidence)
            case .recovery(let retained):
                self = .recovery(retained.unioning(evidence))
            }
        }
    }

    private static let knownFlagMask: UInt32 = [
        FSEventFlags.mustScanSubdirectories,
        .userDropped,
        .kernelDropped,
        .eventIDsWrapped,
        .historyDone,
        .rootChanged,
        .mount,
        .unmount,
        .itemCreated,
        .itemRemoved,
        .itemInodeMetadataModified,
        .itemRenamed,
        .itemModified,
        .itemFinderInfoModified,
        .itemOwnershipChanged,
        .itemXattrModified,
        .itemIsFile,
        .itemIsDirectory,
        .itemIsSymbolicLink,
        .ownEvent,
        .itemIsHardlink,
        .itemIsLastHardlink,
        .itemCloned,
    ].reduce(0) { $0 | $1.rawValue }

    fileprivate static func makeOffer(
        controlBlock: FSEventRegistrationControlBlock,
        input: DarwinFSEventNativeCallbackInput
    ) -> OfferResult {
        guard input.reportedEventCount >= 0 else {
            return .rejected(.invalidReportedEventCount(input.reportedEventCount))
        }
        guard input.reportedEventCount > 0 else { return .ignoredEmptyCallback }
        let nativeShape = makeNativeShape(input: input)
        return inspectNativePrefix(
            controlBlock: controlBlock,
            input: input,
            nativeShape: nativeShape,
            eventFlags: input.eventFlags,
            eventIDs: input.eventIDs
        )
    }

    private static func makeNativeShape(
        input: DarwinFSEventNativeCallbackInput
    ) -> NativeShape {
        let pathArray: CFArray?
        if let eventPaths = input.eventPaths {
            pathArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
        } else {
            pathArray = nil
        }
        let availablePathCount = pathArray.map(CFArrayGetCount) ?? 0
        let availableRecordCount = min(
            availablePathCount,
            input.eventFlags.count,
            input.eventIDs.count
        )
        let totalRecordCount: FSEventRecordCount
        if pathArray == nil {
            totalRecordCount = .malformed(
                .nativeArrayUnavailable(reportedRecordCount: input.reportedEventCount)
            )
        } else if availableRecordCount != input.reportedEventCount {
            totalRecordCount = .malformed(
                .nativeArrayCountMismatch(
                    reportedRecordCount: input.reportedEventCount,
                    availableRecordCount: availableRecordCount
                )
            )
        } else {
            totalRecordCount = .exact(input.reportedEventCount)
        }

        var truncation: FSEventCaptureTruncation = []
        if case .malformed = totalRecordCount {
            truncation.insert(.malformedNativeShape)
        }
        return NativeShape(
            pathArray: pathArray,
            totalRecordCount: totalRecordCount,
            availableNativePrefixCount: min(input.reportedEventCount, availableRecordCount),
            initialTruncation: truncation
        )
    }

    private static func inspectNativePrefix(
        controlBlock: FSEventRegistrationControlBlock,
        input: DarwinFSEventNativeCallbackInput,
        nativeShape: NativeShape,
        eventFlags: UnsafeBufferPointer<FSEventStreamEventFlags>,
        eventIDs: UnsafeBufferPointer<FSEventStreamEventId>
    ) -> OfferResult {
        let inspectedNativeRecordCount = min(
            nativeShape.availableNativePrefixCount,
            controlBlock.captureLimits.maximumInspectedNativeRecords
        )
        var truncation = nativeShape.initialTruncation
        if nativeShape.availableNativePrefixCount > inspectedNativeRecordCount {
            truncation.insert(.inspectedRecordLimitReached)
        }

        var records: [FSEventRecord] = []
        records.reserveCapacity(
            min(inspectedNativeRecordCount, controlBlock.captureLimits.maximumCopiedRecords)
        )
        var unionedInspectedFlags: FSEventFlags = []
        var copiedUTF8ByteCount = 0
        var recovery = RecoveryAccumulator.authoritative
        var firstEventID: UInt64?
        var lastEventID: UInt64?

        for index in 0..<inspectedNativeRecordCount {
            let nativeFlags = FSEventFlags(rawValue: UInt32(eventFlags[index]))
            let eventID = UInt64(eventIDs[index])
            unionedInspectedFlags.formUnion(nativeFlags)
            if firstEventID == nil { firstEventID = eventID }
            lastEventID = eventID
            joinRecovery(for: nativeFlags, into: &recovery)

            guard records.count < controlBlock.captureLimits.maximumCopiedRecords else {
                truncation.insert(.copiedRecordLimitReached)
                continue
            }
            guard
                let pathArray = nativeShape.pathArray,
                let rawPath = CFArrayGetValueAtIndex(pathArray, index)
            else {
                truncation.insert(.pathConversionFailed)
                continue
            }
            let remainingCopiedUTF8ByteCapacity =
                controlBlock.captureLimits.maximumCopiedUTF8Bytes - copiedUTF8ByteCount
            guard remainingCopiedUTF8ByteCapacity > 0 else {
                truncation.insert(.copiedByteLimitReached)
                continue
            }
            let singlePathUTF8ByteLimit =
                controlBlock.captureLimits.maximumSinglePathUTF8Bytes
            let conversionUTF8ByteLimit = min(
                singlePathUTF8ByteLimit,
                remainingCopiedUTF8ByteCapacity
            )
            let exceededLimitReason: FSEventCaptureTruncation =
                remainingCopiedUTF8ByteCapacity < singlePathUTF8ByteLimit
                ? .copiedByteLimitReached
                : .singlePathByteLimitReached
            switch captureBoundedPath(
                rawPath,
                maximumUTF8Bytes: conversionUTF8ByteLimit,
                exceededLimitReason: exceededLimitReason
            ) {
            case .conversionFailed:
                truncation.insert(.pathConversionFailed)
                continue
            case .exceedsLimit(let reason):
                truncation.insert(reason)
                continue
            case .path(let path, let pathByteCount):
                let (nextCopiedByteCount, overflow) = copiedUTF8ByteCount.addingReportingOverflow(
                    pathByteCount
                )
                guard !overflow else {
                    truncation.insert(.checkedArithmeticFailed)
                    continue
                }
                guard nextCopiedByteCount <= controlBlock.captureLimits.maximumCopiedUTF8Bytes
                else {
                    truncation.insert(.copiedByteLimitReached)
                    continue
                }
                copiedUTF8ByteCount = nextCopiedByteCount
                records.append(FSEventRecord(path: path, flags: nativeFlags, eventID: eventID))
            }
        }

        let eventIDWatermark = makeEventIDWatermark(
            firstEventID: firstEventID,
            lastEventID: lastEventID
        )
        if !truncation.isEmpty {
            recovery.require(.callbackCaptureTruncation)
        }
        return makeOffer(
            CapturedObservationComponents(
                registration: controlBlock.registration,
                capturedAt: input.capturedAt,
                totalRecordCount: nativeShape.totalRecordCount,
                inspectedNativeRecordCount: inspectedNativeRecordCount,
                records: records,
                unionedInspectedFlags: unionedInspectedFlags,
                eventIDWatermark: eventIDWatermark,
                truncation: truncation
            ),
            recovery: recovery
        )
    }

    private static func makeEventIDWatermark(
        firstEventID: UInt64?,
        lastEventID: UInt64?
    ) -> FSEventIDWatermark {
        guard let firstEventID, let lastEventID else { return .noInspectedRecords }
        return .inspected(first: firstEventID, last: lastEventID)
    }

    private static func captureBoundedPath(
        _ rawPath: UnsafeRawPointer,
        maximumUTF8Bytes: Int,
        exceededLimitReason: FSEventCaptureTruncation
    ) -> BoundedPathCapture {
        let nativeObject = unsafeBitCast(rawPath, to: CFTypeRef.self)
        guard CFGetTypeID(nativeObject) == CFStringGetTypeID() else {
            return .conversionFailed
        }
        let nativeString = unsafeBitCast(rawPath, to: CFString.self)
        let utf16Length = CFStringGetLength(nativeString)
        guard utf16Length <= maximumUTF8Bytes else {
            return .exceedsLimit(exceededLimitReason)
        }
        guard utf16Length > 0 else { return .path("", utf8ByteCount: 0) }

        let maximumEncodingBytes: Int
        let encodingCapacity = utf16Length.multipliedReportingOverflow(by: 3)
        if encodingCapacity.overflow {
            maximumEncodingBytes = maximumUTF8Bytes
        } else {
            maximumEncodingBytes = min(maximumUTF8Bytes, encodingCapacity.partialValue)
        }
        var boundedUTF8Bytes = [UInt8](repeating: 0, count: maximumEncodingBytes)
        var usedByteCount = 0
        let convertedUTF16Length = boundedUTF8Bytes.withUnsafeMutableBufferPointer { buffer in
            CFStringGetBytes(
                nativeString,
                CFRange(location: 0, length: utf16Length),
                CFStringEncoding(CFStringBuiltInEncodings.UTF8.rawValue),
                0,
                false,
                buffer.baseAddress,
                buffer.count,
                &usedByteCount
            )
        }
        guard convertedUTF16Length == utf16Length else {
            return .exceedsLimit(exceededLimitReason)
        }
        guard
            let path = String(
                bytes: boundedUTF8Bytes.prefix(usedByteCount),
                encoding: .utf8
            )
        else {
            return .conversionFailed
        }
        return .path(path, utf8ByteCount: usedByteCount)
    }

    private static func joinRecovery(
        for flags: FSEventFlags,
        into recovery: inout RecoveryAccumulator
    ) {
        let continuityFlags: FSEventFlags = [
            .mustScanSubdirectories,
            .userDropped,
            .kernelDropped,
            .eventIDsWrapped,
        ]
        if !flags.isDisjoint(with: continuityFlags) {
            recovery.require(.continuityLoss)
        }
        let rootIdentityFlags: FSEventFlags = [.rootChanged, .mount, .unmount]
        if !flags.isDisjoint(with: rootIdentityFlags) {
            recovery.require(.rootIdentityRevalidation)
        }
        if flags.rawValue & ~knownFlagMask != 0 {
            recovery.require(.continuityLoss)
            recovery.require(.unsupportedNativeFlags)
        }
    }

    private static func makeOffer(
        _ components: CapturedObservationComponents,
        recovery: RecoveryAccumulator
    ) -> OfferResult {
        let completeness: FSEventCaptureCompleteness =
            components.truncation.isEmpty ? .complete : .truncated(components.truncation)
        do {
            let observation = try FSEventObservation(
                registration: components.registration,
                capturedAt: components.capturedAt,
                totalRecordCount: components.totalRecordCount,
                inspectedNativeRecordCount: components.inspectedNativeRecordCount,
                records: components.records,
                unionedInspectedFlags: components.unionedInspectedFlags,
                eventIDWatermark: components.eventIDWatermark,
                completeness: completeness
            )
            switch recovery {
            case .authoritative:
                return .offer(.authoritative(observation))
            case .recovery(let evidence):
                return .offer(.requiresRecovery(observation, evidence: evidence))
            }
        } catch let validationError as FSEventObservationValidationError {
            return .rejected(.invalidObservation(validationError))
        } catch {
            preconditionFailure("FSEventObservation exposes only typed validation failures")
        }
    }
}
