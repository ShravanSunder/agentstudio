import Foundation

typealias BridgeReviewResourceChunkReceiver = @Sendable (Data) async throws -> Bool

struct BridgeReviewResourceBody: Sendable {
    let byteCount: Int?
    let mimeType: String
    private let emitChunksImplementation:
        @Sendable (Int, @escaping BridgeReviewResourceChunkReceiver) async throws -> Bool

    init(data: Data, mimeType: String) {
        self.byteCount = data.count
        self.mimeType = mimeType
        self.emitChunksImplementation = { chunkByteCount, receive in
            try await emitReviewResourceDataChunks(
                data,
                chunkByteCount: chunkByteCount,
                receive: receive
            )
        }
    }

    init(
        mimeType: String,
        byteCount: Int? = nil,
        emitChunks: @escaping @Sendable (Int, @escaping BridgeReviewResourceChunkReceiver) async throws -> Bool
    ) {
        self.byteCount = byteCount
        self.mimeType = mimeType
        self.emitChunksImplementation = emitChunks
    }

    func emitChunks(
        chunkByteCount: Int,
        receive: @escaping BridgeReviewResourceChunkReceiver
    ) async throws -> Bool {
        try await emitChunksImplementation(chunkByteCount, receive)
    }
}

private func emitReviewResourceDataChunks(
    _ data: Data,
    chunkByteCount: Int,
    receive: BridgeReviewResourceChunkReceiver
) async throws -> Bool {
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

actor BridgeReviewResourceStore {
    private struct ResourceEntry: Sendable {
        let resource: BridgeTransportResourceURL
        let body: BridgeReviewResourceBody
    }

    private var entryByCanonicalURL: [String: ResourceEntry] = [:]

    func register(
        _ resource: BridgeTransportResourceURL,
        body: BridgeReviewResourceBody
    ) {
        entryByCanonicalURL[resource.canonicalURL] = ResourceEntry(resource: resource, body: body)
    }

    func register(
        _ resource: BridgeTransportResourceURL,
        mimeType: String,
        loadData: @escaping @Sendable () throws -> Data
    ) {
        register(
            resource,
            body: BridgeReviewResourceBody(mimeType: mimeType) { chunkByteCount, receive in
                try await emitReviewResourceDataChunks(
                    try loadData(),
                    chunkByteCount: chunkByteCount,
                    receive: receive
                )
            }
        )
    }

    func replace(
        _ resource: BridgeTransportResourceURL,
        body: BridgeReviewResourceBody
    ) {
        reset(protocolId: resource.protocolId, resourceKind: resource.resourceKind)
        register(resource, body: body)
    }

    func replace(
        _ resource: BridgeTransportResourceURL,
        mimeType: String,
        loadData: @escaping @Sendable () throws -> Data
    ) {
        reset(protocolId: resource.protocolId, resourceKind: resource.resourceKind)
        register(resource, mimeType: mimeType, loadData: loadData)
    }

    func metadata(_ resource: BridgeTransportResourceURL) -> BridgeReviewResourceMetadata? {
        guard let entry = entryByCanonicalURL[resource.canonicalURL] else {
            return nil
        }
        return BridgeReviewResourceMetadata(byteCount: entry.body.byteCount, mimeType: entry.body.mimeType)
    }

    func emitChunks(
        _ resource: BridgeTransportResourceURL,
        chunkByteCount: Int,
        receive: @escaping BridgeReviewResourceChunkReceiver
    ) async throws -> Bool? {
        guard let body = entryByCanonicalURL[resource.canonicalURL]?.body else {
            return nil
        }
        return try await body.emitChunks(
            chunkByteCount: chunkByteCount,
            receive: receive
        )
    }

    func reset(
        protocolId: String? = nil,
        resourceKind: String? = nil,
        generation: Int? = nil,
        revision: Int? = nil
    ) {
        entryByCanonicalURL = entryByCanonicalURL.filter { _, entry in
            let resource = entry.resource
            let shouldRemove =
                (protocolId.map { resource.protocolId == $0 } ?? true)
                && (resourceKind.map { resource.resourceKind == $0 } ?? true)
                && (generation.map { resource.generation == $0 } ?? true)
                && (revision.map { resource.revision == $0 } ?? true)
            return !shouldRemove
        }
    }
}

struct BridgeReviewResourceMetadata: Equatable, Sendable {
    let byteCount: Int?
    let mimeType: String
}
