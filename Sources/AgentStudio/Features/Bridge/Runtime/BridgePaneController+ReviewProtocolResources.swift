import CryptoKit
import Foundation

@MainActor
extension BridgePaneController {
    func commitReviewPackageLoad(
        _ frames: BridgeReviewPackageLoadFrames,
        traceContext: BridgeTraceContext?
    ) async {
        await deliverReviewProtocolFrameBestEffort(.snapshot(frames.snapshotFrame), traceContext: traceContext)
        if let deltaFrame = frames.deltaFrame {
            await deliverReviewProtocolFrameBestEffort(.delta(deltaFrame), traceContext: traceContext)
        }
        paneState.diff.setPackageMetadata(frames.package)
        paneState.diff.setPackageDelta(
            frames.delta
        )
        paneState.diff.setStatus(.ready)
    }

    func deliverReviewProtocolFrameBestEffort(
        _ frame: BridgeReviewProtocolFrame,
        traceContext: BridgeTraceContext?
    ) async {
        do {
            try await dispatchReviewProtocolFrame(frame, traceContext: traceContext)
        } catch {
            paneState.connection.setHealth(.error)
        }
    }

    func deliverReviewProtocolErrorFrame(
        streamId: String,
        generation: Int,
        message: String,
        traceContext: BridgeTraceContext?
    ) async {
        do {
            let encodedFrame = try BridgePushEnvelopeEncoder().encodeIntakeFrame(
                metadata: BridgeIntakeFrameMetadata(
                    kind: .error,
                    streamId: streamId,
                    generation: generation,
                    sequence: consumeNextReviewProtocolSequence(),
                    message: message
                ),
                payload: Data(),
                traceContext: traceContext
            )
            guard canDeliverReviewProtocolIntakeFrames() else {
                pendingReviewProtocolIntakeFrames.append(encodedFrame)
                return
            }
            guard await deliverIntakeFrame(encodedFrame) else {
                throw BridgeProviderFailure.providerFailed(message: "Bridge review protocol intake delivery failed")
            }
        } catch {
            paneState.connection.setHealth(.error)
        }
    }

    func dispatchReviewProtocolFrame(
        _ frame: BridgeReviewProtocolFrame,
        traceContext: BridgeTraceContext?
    ) async throws {
        let payload = try JSONEncoder().encode(frame)
        let encodedFrame = try BridgePushEnvelopeEncoder().encodeIntakeFrame(
            metadata: reviewIntakeFrameMetadata(for: frame),
            payload: payload,
            traceContext: traceContext
        )
        guard canDeliverReviewProtocolIntakeFrames() else {
            pendingReviewProtocolIntakeFrames.append(encodedFrame)
            return
        }
        guard await deliverIntakeFrame(encodedFrame) else {
            throw BridgeProviderFailure.providerFailed(message: "Bridge review protocol intake delivery failed")
        }
    }

    func canDeliverReviewProtocolIntakeFrames() -> Bool {
        isBridgeReady && reviewIntakeReadyStreamId == reviewProtocolStreamId()
    }

    func activateReviewProtocolBodyResources(
        frames: BridgeReviewPackageLoadFrames,
        expectedPackageResourceRevocationRevision: UInt64,
        expectedDeltaResourceRevocationRevision: UInt64
    ) async throws {
        let packageLease = try makeReviewProtocolBodyLease(
            descriptor: frames.snapshotFrame.package.rootDescriptor
        )
        let packageReplaced = await resourceLeaseRegistry.replace(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "review-package",
            leases: [packageLease],
            expectedRevocationRevision: expectedPackageResourceRevocationRevision
        )
        guard packageReplaced else {
            await clearReviewResourceAuthority(resourceKind: "review-package")
            throw BridgeProviderFailure.providerFailed(message: "Invalid bridge review package resource lease")
        }
        let package = frames.package
        await reviewResourceStore.replace(
            packageLease.resource,
            body: BridgeReviewResourceBody(
                mimeType: "application/json",
                byteCount: frames.packageBodyFacts?.byteCount
            ) { chunkByteCount, receive in
                try await BridgeReviewJSONResourceEmitter.emitPackage(
                    package,
                    chunkByteCount: chunkByteCount,
                    receive: receive
                )
            })

        guard let deltaFrame = frames.deltaFrame, let delta = frames.delta else {
            await clearReviewResourceAuthority(
                resourceKind: "review-delta",
                revokeAuthority: false
            )
            return
        }
        let deltaLease = try makeReviewProtocolBodyLease(
            descriptor: deltaFrame.operationsDescriptor
        )
        let deltaReplaced = await resourceLeaseRegistry.replace(
            paneId: paneId,
            protocolId: "review",
            resourceKind: "review-delta",
            leases: [deltaLease],
            expectedRevocationRevision: expectedDeltaResourceRevocationRevision
        )
        guard deltaReplaced else {
            await clearReviewResourceAuthority(resourceKind: "review-delta")
            throw BridgeProviderFailure.providerFailed(message: "Invalid bridge review delta resource lease")
        }
        await reviewResourceStore.replace(
            deltaLease.resource,
            body: BridgeReviewResourceBody(
                mimeType: "application/json",
                byteCount: frames.deltaBodyFacts?.byteCount
            ) { chunkByteCount, receive in
                try await BridgeReviewJSONResourceEmitter.emitDeltaOperations(
                    delta.operations,
                    chunkByteCount: chunkByteCount,
                    receive: receive
                )
            })
    }

    func makeReviewProtocolBodyLease(
        descriptor: BridgeAttachedResourceDescriptor
    ) throws -> BridgeTransportResourceLease {
        guard
            let resource = BridgeTransportResourceURL.parse(
                descriptor.descriptor.resourceUrl,
                allowedResourceKindsByProtocol: BridgeResourceProtocolRegistry.reviewViewerAllowedResourceKinds
            ),
            resource.opaqueId == descriptor.descriptor.descriptorId,
            resource.opaqueId == descriptor.ref.descriptorId,
            descriptor.descriptor.content.maxBytes >= 1
        else {
            throw BridgeProviderFailure.providerFailed(message: "Invalid bridge review protocol body descriptor")
        }
        return BridgeTransportResourceLease(
            paneId: paneId,
            descriptorId: resource.opaqueId,
            resource: resource,
            maxBytes: descriptor.descriptor.content.maxBytes
        )
    }

    @discardableResult
    func revokeReviewResourceAuthoritySynchronously(resourceKind: String) -> UInt64 {
        resourceLeaseRegistry.revokeSynchronously(paneId: paneId, protocolId: "review", resourceKind: resourceKind)
        return reviewResourceRevocationRevision(resourceKind: resourceKind)
    }

    func clearReviewResourceAuthority(resourceKind: String, revokeAuthority: Bool = true) async {
        await reviewResourceStore.reset(protocolId: "review", resourceKind: resourceKind)
        await resourceLeaseRegistry.reset(
            paneId: paneId,
            protocolId: "review",
            resourceKind: resourceKind,
            revokeAuthority: revokeAuthority
        )
    }

    func reviewResourceRevocationRevision(resourceKind: String) -> UInt64 {
        resourceLeaseRegistry.revocationRevision(paneId: paneId, protocolId: "review", resourceKind: resourceKind)
    }

    private func reviewIntakeFrameMetadata(for frame: BridgeReviewProtocolFrame) -> BridgeIntakeFrameMetadata {
        switch frame {
        case .snapshot(let snapshot):
            BridgeIntakeFrameMetadata(
                kind: .snapshot,
                streamId: snapshot.streamId,
                generation: snapshot.generation,
                sequence: snapshot.sequence
            )
        case .delta(let delta):
            BridgeIntakeFrameMetadata(
                kind: .delta,
                streamId: delta.streamId,
                generation: delta.generation,
                sequence: delta.sequence
            )
        case .invalidation(let invalidation):
            BridgeIntakeFrameMetadata(
                kind: .invalidate,
                streamId: invalidation.streamId,
                generation: invalidation.generation,
                sequence: invalidation.sequence
            )
        case .reset(let reset):
            BridgeIntakeFrameMetadata(
                kind: .reset,
                streamId: reset.streamId,
                generation: reset.generation,
                sequence: reset.sequence
            )
        }
    }
}

struct BridgeReviewJSONResourceEmitter {
    private static let bodyFactsChunkByteCount = 64 * 1024

    static func packageBodyFacts(
        _ package: BridgeReviewPackage
    ) async throws -> BridgeReviewProtocolBodyResourceFacts {
        let collector = BridgeReviewJSONBodyFactsCollector()
        let emitted = try await emitPackage(
            package,
            chunkByteCount: bodyFactsChunkByteCount
        ) { chunk in
            collector.receive(chunk)
            return true
        }
        guard emitted else {
            throw BridgeProviderFailure.providerFailed(message: "Unable to compute bridge review package facts")
        }
        return collector.facts()
    }

    static func deltaOperationsBodyFacts(
        _ operations: BridgeReviewDelta.Operations
    ) async throws -> BridgeReviewProtocolBodyResourceFacts {
        let collector = BridgeReviewJSONBodyFactsCollector()
        let emitted = try await emitDeltaOperations(
            operations,
            chunkByteCount: bodyFactsChunkByteCount
        ) { chunk in
            collector.receive(chunk)
            return true
        }
        guard emitted else {
            throw BridgeProviderFailure.providerFailed(message: "Unable to compute bridge review delta facts")
        }
        return collector.facts()
    }

    static func emitPackage(
        _ package: BridgeReviewPackage,
        chunkByteCount: Int,
        receive: @escaping BridgeReviewResourceChunkReceiver
    ) async throws -> Bool {
        let writer = BridgeReviewJSONStreamWriter(
            chunkByteCount: chunkByteCount,
            receive: receive
        )
        var properties: [BridgeReviewJSONProperty] = [
            valueProperty("packageId", package.packageId),
            valueProperty("schemaVersion", package.schemaVersion),
            valueProperty("reviewGeneration", package.reviewGeneration),
            valueProperty("revision", package.revision),
            valueProperty("query", package.query),
            valueProperty("baseEndpoint", package.baseEndpoint),
            valueProperty("headEndpoint", package.headEndpoint),
            arrayProperty("orderedItemIds", package.orderedItemIds),
            dictionaryProperty("itemsById", package.itemsById),
            arrayProperty("groups", package.groups),
            valueProperty("summary", package.summary),
            valueProperty("filterState", package.filterState),
            valueProperty("generatedAtUnixMilliseconds", package.generatedAtUnixMilliseconds),
        ]
        if let changesetCluster = package.changesetCluster {
            properties.append(valueProperty("changesetCluster", changesetCluster))
        }
        return try await writer.emitObject(properties)
    }

    static func emitDeltaOperations(
        _ operations: BridgeReviewDelta.Operations,
        chunkByteCount: Int,
        receive: @escaping BridgeReviewResourceChunkReceiver
    ) async throws -> Bool {
        let writer = BridgeReviewJSONStreamWriter(
            chunkByteCount: chunkByteCount,
            receive: receive
        )
        var properties: [BridgeReviewJSONProperty] = [
            arrayProperty("addItems", operations.addItems),
            arrayProperty("updateItems", operations.updateItems),
            arrayProperty("removeItems", operations.removeItems),
            arrayProperty("moveItems", operations.moveItems),
        ]
        if let updateGroups = operations.updateGroups {
            properties.append(arrayProperty("updateGroups", updateGroups))
        }
        if let updateSummary = operations.updateSummary {
            properties.append(valueProperty("updateSummary", updateSummary))
        }
        properties.append(arrayProperty("invalidateContent", operations.invalidateContent))
        return try await writer.emitObject(properties)
    }

    private static func valueProperty<Value: Encodable & Sendable>(
        _ name: String,
        _ value: Value
    ) -> BridgeReviewJSONProperty {
        BridgeReviewJSONProperty(name: name) { writer in
            try await writer.emitEncoded(value)
        }
    }

    private static func arrayProperty<Element: Encodable & Sendable>(
        _ name: String,
        _ values: [Element]
    ) -> BridgeReviewJSONProperty {
        BridgeReviewJSONProperty(name: name) { writer in
            try await writer.emitArray(values)
        }
    }

    private static func dictionaryProperty<Value: Encodable & Sendable>(
        _ name: String,
        _ values: [String: Value]
    ) -> BridgeReviewJSONProperty {
        BridgeReviewJSONProperty(name: name) { writer in
            try await writer.emitDictionary(values)
        }
    }
}

private final class BridgeReviewJSONBodyFactsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var hasher = SHA256()
    private var byteCount = 0

    func receive(_ chunk: Data) {
        lock.withLock {
            hasher.update(data: chunk)
            byteCount += chunk.count
        }
    }

    func facts() -> BridgeReviewProtocolBodyResourceFacts {
        lock.withLock {
            let digest = hasher.finalize()
            let hash = digest.map { String(format: "%02x", $0) }.joined()
            return BridgeReviewProtocolBodyResourceFacts(byteCount: byteCount, sha256Hex: hash)
        }
    }
}

private struct BridgeReviewJSONProperty: Sendable {
    let name: String
    let emitValue: @Sendable (BridgeReviewJSONStreamWriter) async throws -> Bool
}

private struct BridgeReviewJSONStreamWriter: Sendable {
    let chunkByteCount: Int
    let receive: BridgeReviewResourceChunkReceiver

    func emitObject(_ properties: [BridgeReviewJSONProperty]) async throws -> Bool {
        guard try await emitString("{") else { return false }
        for (index, property) in properties.enumerated() {
            if index > 0 {
                guard try await emitString(",") else { return false }
            }
            guard try await emitEncoded(property.name),
                try await emitString(":"),
                try await property.emitValue(self)
            else {
                return false
            }
        }
        return try await emitString("}")
    }

    func emitArray<Element: Encodable>(_ values: [Element]) async throws -> Bool {
        guard try await emitString("[") else { return false }
        for (index, value) in values.enumerated() {
            if index > 0 {
                guard try await emitString(",") else { return false }
            }
            guard try await emitEncoded(value) else { return false }
        }
        return try await emitString("]")
    }

    func emitDictionary<Value: Encodable>(_ values: [String: Value]) async throws -> Bool {
        guard try await emitString("{") else { return false }
        for (index, key) in values.keys.sorted().enumerated() {
            guard let value = values[key] else { continue }
            if index > 0 {
                guard try await emitString(",") else { return false }
            }
            guard try await emitEncoded(key),
                try await emitString(":"),
                try await emitEncoded(value)
            else {
                return false
            }
        }
        return try await emitString("}")
    }

    func emitEncoded<Value: Encodable>(_ value: Value) async throws -> Bool {
        let data = try JSONEncoder().encode(value)
        return try await emitData(data)
    }

    func emitString(_ value: String) async throws -> Bool {
        try await emitData(Data(value.utf8))
    }

    func emitData(_ data: Data) async throws -> Bool {
        var offset = 0
        while offset < data.count {
            let endOffset = min(offset + chunkByteCount, data.count)
            let chunk = data.subdata(in: offset..<endOffset)
            guard try await receive(chunk) else {
                return false
            }
            offset = endOffset
        }
        return true
    }
}
