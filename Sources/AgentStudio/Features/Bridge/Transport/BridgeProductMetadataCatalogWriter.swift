import Foundation

enum BridgeProductMetadataCatalogWriterError: Error, Equatable {
    case encodedEntryBytesExceeded
    case entryCountExceeded
    case entryDoesNotFitMetadataFrame
    case frameObservationFailed
    case frameQueueReset
    case frameRejected(BridgeProductProducerEnqueueRejection)
}

struct BridgeProductMetadataCatalogWriteResult: Equatable, Sendable {
    let entryCount: Int
    let frameCount: Int
    let windowCount: Int
}

struct BridgeProductMetadataCatalogWriter<Entry>: Sendable
where Entry: Codable & Equatable & Sendable {
    typealias Transfer = BridgeProductMetadataCatalogTransfer<Entry>

    func write<MetadataFrame: Encodable>(
        entries: [Entry],
        catalogRevision: Int,
        transferID: String,
        makeProspectiveMetadataFrame: (Transfer) throws -> MetadataFrame,
        enqueue: (Transfer) async throws -> BridgeProductProducerEnqueueResult,
        waitUntilObserved: (Int) async -> Bool
    ) async throws -> BridgeProductMetadataCatalogWriteResult {
        let phases = try preflight(
            entries: entries,
            catalogRevision: catalogRevision,
            transferID: transferID,
            makeProspectiveMetadataFrame: makeProspectiveMetadataFrame
        )
        for phase in phases {
            let enqueueResult = try await enqueue(phase)
            let sequence: Int
            switch enqueueResult {
            case .enqueued(let frame):
                sequence = frame.sequence
            case .queueReset:
                throw BridgeProductMetadataCatalogWriterError.frameQueueReset
            case .rejected(let rejection):
                throw BridgeProductMetadataCatalogWriterError.frameRejected(rejection)
            }
            guard await waitUntilObserved(sequence) else {
                throw BridgeProductMetadataCatalogWriterError.frameObservationFailed
            }
        }
        let windowCount = phases.count { $0.windowOrdinal != nil }
        return .init(
            entryCount: entries.count,
            frameCount: phases.count,
            windowCount: windowCount
        )
    }

    func preflight<MetadataFrame: Encodable>(
        entries: [Entry],
        catalogRevision: Int,
        transferID: String,
        makeProspectiveMetadataFrame: (Transfer) throws -> MetadataFrame
    ) throws -> [Transfer] {
        guard entries.count <= BridgeProductMetadataCatalogCapacity.maximumEntryCount else {
            throw BridgeProductMetadataCatalogWriterError.entryCountExceeded
        }
        let encodedEntryByteCounts = try encodedEntryByteCounts(entries)
        let begin = Transfer.begin(
            transferID: transferID,
            catalogRevision: catalogRevision,
            expectedEntryCount: entries.count
        )
        try validateFrameFits(begin, makeProspectiveMetadataFrame: makeProspectiveMetadataFrame)

        var phases = [begin]
        var entryIndex = 0
        var windowOrdinal = 0
        while entryIndex < entries.count {
            let upperBound = prospectiveWindowUpperBound(
                startingAt: entryIndex,
                encodedEntryByteCounts: encodedEntryByteCounts
            )
            guard upperBound > entryIndex else {
                throw BridgeProductMetadataCatalogWriterError.entryDoesNotFitMetadataFrame
            }
            let acceptedEndIndex = try largestFittingWindowEndIndex(
                entries: entries,
                range: (entryIndex + 1)...upperBound,
                transferID: transferID,
                catalogRevision: catalogRevision,
                windowOrdinal: windowOrdinal,
                makeProspectiveMetadataFrame: makeProspectiveMetadataFrame
            )
            guard let acceptedEndIndex else {
                throw BridgeProductMetadataCatalogWriterError.entryDoesNotFitMetadataFrame
            }
            phases.append(
                .window(
                    transferID: transferID,
                    catalogRevision: catalogRevision,
                    windowOrdinal: windowOrdinal,
                    entries: Array(entries[entryIndex..<acceptedEndIndex])
                )
            )
            entryIndex = acceptedEndIndex
            windowOrdinal += 1
        }

        let commit = Transfer.commit(
            transferID: transferID,
            catalogRevision: catalogRevision,
            windowCount: windowOrdinal,
            entryCount: entries.count
        )
        try validateFrameFits(commit, makeProspectiveMetadataFrame: makeProspectiveMetadataFrame)
        phases.append(commit)
        return phases
    }

    private func encodedEntryByteCounts(_ entries: [Entry]) throws -> [Int] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var totalEncodedEntryBytes = 0
        var encodedEntryByteCounts: [Int] = []
        encodedEntryByteCounts.reserveCapacity(entries.count)
        for entry in entries {
            let encodedEntryByteCount = try encoder.encode(entry).count
            let (newTotal, overflowed) = totalEncodedEntryBytes.addingReportingOverflow(
                encodedEntryByteCount
            )
            guard !overflowed,
                newTotal <= BridgeProductMetadataCatalogCapacity.maximumEncodedEntryBytes
            else {
                throw BridgeProductMetadataCatalogWriterError.encodedEntryBytesExceeded
            }
            totalEncodedEntryBytes = newTotal
            encodedEntryByteCounts.append(encodedEntryByteCount)
        }
        return encodedEntryByteCounts
    }

    private func prospectiveWindowUpperBound(
        startingAt startIndex: Int,
        encodedEntryByteCounts: [Int]
    ) -> Int {
        var upperBound = startIndex
        var encodedEntryBytesWithSeparators = 0
        while upperBound < encodedEntryByteCounts.count {
            let separatorByteCount = upperBound == startIndex ? 0 : 1
            let prospectiveByteCount =
                encodedEntryBytesWithSeparators
                + separatorByteCount
                + encodedEntryByteCounts[upperBound]
            guard prospectiveByteCount <= BridgeProductWireContract.maximumMetadataFrameBytes else {
                break
            }
            encodedEntryBytesWithSeparators = prospectiveByteCount
            upperBound += 1
        }
        return upperBound
    }

    private func largestFittingWindowEndIndex<MetadataFrame: Encodable>(
        entries: [Entry],
        range: ClosedRange<Int>,
        transferID: String,
        catalogRevision: Int,
        windowOrdinal: Int,
        makeProspectiveMetadataFrame: (Transfer) throws -> MetadataFrame
    ) throws -> Int? {
        var lowerBound = range.lowerBound
        var upperBound = range.upperBound
        var acceptedEndIndex: Int?
        let startIndex = range.lowerBound - 1
        while lowerBound <= upperBound {
            let candidateEndIndex = lowerBound + ((upperBound - lowerBound) / 2)
            let candidate = Transfer.window(
                transferID: transferID,
                catalogRevision: catalogRevision,
                windowOrdinal: windowOrdinal,
                entries: Array(entries[startIndex..<candidateEndIndex])
            )
            if try frameFits(
                candidate,
                makeProspectiveMetadataFrame: makeProspectiveMetadataFrame
            ) {
                acceptedEndIndex = candidateEndIndex
                lowerBound = candidateEndIndex + 1
            } else {
                upperBound = candidateEndIndex - 1
            }
        }
        return acceptedEndIndex
    }

    private func validateFrameFits<MetadataFrame: Encodable>(
        _ transfer: Transfer,
        makeProspectiveMetadataFrame: (Transfer) throws -> MetadataFrame
    ) throws {
        guard
            try frameFits(
                transfer,
                makeProspectiveMetadataFrame: makeProspectiveMetadataFrame
            )
        else {
            throw BridgeProductMetadataCatalogWriterError.entryDoesNotFitMetadataFrame
        }
    }

    private func frameFits<MetadataFrame: Encodable>(
        _ transfer: Transfer,
        makeProspectiveMetadataFrame: (Transfer) throws -> MetadataFrame
    ) throws -> Bool {
        do {
            _ = try BridgeProductMetadataFrameCodec.encodeJSONBody(
                makeProspectiveMetadataFrame(transfer)
            )
            return true
        } catch let error as BridgeProductFrameCodecError {
            switch error {
            case .invalidFrame:
                return false
            case .invalidConfiguration, .truncatedFrame:
                throw error
            }
        }
    }
}
