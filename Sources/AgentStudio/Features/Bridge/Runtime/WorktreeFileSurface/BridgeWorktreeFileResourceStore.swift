import Foundation

struct BridgeWorktreeFileResourceBody: Equatable, Sendable {
    let data: Data
    let mimeType: String
}

struct BridgeWorktreeTreeWindowResourceBody: Codable, Equatable, Sendable {
    struct Row: Codable, Equatable, Sendable {
        let path: String
        let kind: String
        let depth: Int
    }

    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let treeSizeFacts: BridgeWorktreeTreeVirtualizedSizeFacts
    let rows: [Row]
}

struct BridgeWorktreeStatusResourceBody: Codable, Equatable, Sendable {
    let source: BridgeWorktreeFileSurfaceSourceIdentity
    let patch: BridgeWorktreeStatusPatch
}

actor BridgeWorktreeFileResourceStore {
    private struct ResourceEntry: Sendable {
        let resource: BridgeTransportResourceURL
        let body: BridgeWorktreeFileResourceBody
    }

    private var entryByCanonicalURL: [String: ResourceEntry] = [:]

    func register(
        _ resource: BridgeTransportResourceURL,
        body: BridgeWorktreeFileResourceBody
    ) {
        entryByCanonicalURL[resource.canonicalURL] = ResourceEntry(resource: resource, body: body)
    }

    func load(_ resource: BridgeTransportResourceURL) -> BridgeWorktreeFileResourceBody? {
        entryByCanonicalURL[resource.canonicalURL]?.body
    }

    func reset(
        protocolId: String? = nil,
        resourceKind: String? = nil,
        generation: Int? = nil,
        cursor: String? = nil
    ) {
        entryByCanonicalURL = entryByCanonicalURL.filter { _, entry in
            let resource = entry.resource
            let shouldRemove =
                (protocolId.map { resource.protocolId == $0 } ?? true)
                && (resourceKind.map { resource.resourceKind == $0 } ?? true)
                && (generation.map { resource.generation == $0 } ?? true)
                && (cursor.map { resource.cursor == $0 } ?? true)
            return !shouldRemove
        }
    }
}
