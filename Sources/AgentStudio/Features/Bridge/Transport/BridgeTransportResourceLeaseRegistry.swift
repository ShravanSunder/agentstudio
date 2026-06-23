import Foundation

private final class BridgeTransportResourceLeaseAuthorityGate: @unchecked Sendable {
    private struct RevocationKey: Hashable {
        let paneId: UUID
        let protocolId: String?
        let resourceKind: String?

        func matches(resource: BridgeTransportResourceURL, paneId: UUID) -> Bool {
            guard self.paneId == paneId else { return false }
            guard protocolId.map({ resource.protocolId == $0 }) ?? true else { return false }
            guard resourceKind.map({ resource.resourceKind == $0 }) ?? true else { return false }
            return true
        }
    }

    private let lock = NSLock()
    private var revokedKeys: Set<RevocationKey> = []

    func revoke(paneId: UUID, protocolId: String?, resourceKind: String?) {
        lock.withLock {
            _ = revokedKeys.insert(RevocationKey(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind))
        }
    }

    func authorize(paneId: UUID, protocolId: String, resourceKind: String) {
        lock.withLock {
            revokedKeys = revokedKeys.filter { key in
                guard key.paneId == paneId else { return true }
                guard key.protocolId.map({ $0 == protocolId }) ?? true else { return true }
                guard key.resourceKind.map({ $0 == resourceKind }) ?? true else { return true }
                return false
            }
        }
    }

    func isRevoked(resource: BridgeTransportResourceURL, paneId: UUID) -> Bool {
        lock.withLock {
            revokedKeys.contains { key in
                key.matches(resource: resource, paneId: paneId)
            }
        }
    }
}

struct BridgeTransportResourceLease: Equatable, Sendable {
    let paneId: UUID
    let descriptorId: String
    let resource: BridgeTransportResourceURL
    let maxBytes: Int?

    init(
        paneId: UUID,
        descriptorId: String,
        resource: BridgeTransportResourceURL,
        maxBytes: Int? = nil
    ) {
        self.paneId = paneId
        self.descriptorId = descriptorId
        self.resource = resource
        self.maxBytes = maxBytes
    }
}

actor BridgeTransportResourceLeaseRegistry {
    private var leasesByCanonicalURL: [String: BridgeTransportResourceLease] = [:]
    private let authorityGate = BridgeTransportResourceLeaseAuthorityGate()

    nonisolated func revokeSynchronously(paneId: UUID, protocolId: String? = nil, resourceKind: String? = nil) {
        authorityGate.revoke(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
    }

    @discardableResult
    func register(
        _ resource: BridgeTransportResourceURL,
        paneId: UUID,
        descriptorId: String? = nil,
        maxBytes: Int? = nil
    ) -> Bool {
        register(
            BridgeTransportResourceLease(
                paneId: paneId,
                descriptorId: descriptorId ?? resource.opaqueId,
                resource: resource,
                maxBytes: maxBytes
            ))
    }

    @discardableResult
    func register(_ lease: BridgeTransportResourceLease) -> Bool {
        guard lease.descriptorId == lease.resource.opaqueId,
            lease.maxBytes.map({ $0 >= 0 }) ?? true
        else {
            return false
        }
        authorityGate.authorize(
            paneId: lease.paneId,
            protocolId: lease.resource.protocolId,
            resourceKind: lease.resource.resourceKind
        )
        leasesByCanonicalURL[lease.resource.canonicalURL] = lease
        return true
    }

    func revoke(_ resource: BridgeTransportResourceURL) {
        leasesByCanonicalURL.removeValue(forKey: resource.canonicalURL)
    }

    func reset(
        paneId: UUID,
        protocolId: String? = nil,
        resourceKind: String? = nil,
        generation: Int? = nil,
        revision: Int? = nil,
        cursor: String? = nil
    ) {
        authorityGate.revoke(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
        leasesByCanonicalURL = leasesByCanonicalURL.filter { _, lease in
            guard lease.paneId == paneId else { return true }
            guard protocolId.map({ lease.resource.protocolId == $0 }) ?? true else { return true }
            guard resourceKind.map({ lease.resource.resourceKind == $0 }) ?? true else { return true }
            guard generation.map({ lease.resource.generation == $0 }) ?? true else { return true }
            guard revision.map({ lease.resource.revision == $0 }) ?? true else { return true }
            guard cursor.map({ lease.resource.cursor == $0 }) ?? true else { return true }
            return false
        }
    }

    @discardableResult
    func replace(
        paneId: UUID,
        protocolId: String,
        resourceKind: String,
        leases: [BridgeTransportResourceLease]
    ) -> Bool {
        for lease in leases {
            guard lease.paneId == paneId,
                lease.resource.protocolId == protocolId,
                lease.resource.resourceKind == resourceKind,
                lease.descriptorId == lease.resource.opaqueId,
                lease.maxBytes.map({ $0 >= 0 }) ?? true
            else {
                return false
            }
        }
        authorityGate.authorize(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
        leasesByCanonicalURL = leasesByCanonicalURL.filter { _, lease in
            !(lease.paneId == paneId
                && lease.resource.protocolId == protocolId
                && lease.resource.resourceKind == resourceKind)
        }
        for lease in leases {
            leasesByCanonicalURL[lease.resource.canonicalURL] = lease
        }
        return true
    }

    func contains(_ resource: BridgeTransportResourceURL, paneId: UUID, contentLength: Int? = nil) -> Bool {
        guard !authorityGate.isRevoked(resource: resource, paneId: paneId) else {
            return false
        }
        guard let lease = leasesByCanonicalURL[resource.canonicalURL] else {
            return false
        }
        guard lease.paneId == paneId,
            lease.descriptorId == resource.opaqueId,
            lease.resource == resource
        else {
            return false
        }
        guard let contentLength, let maxBytes = lease.maxBytes else {
            return true
        }
        return contentLength <= maxBytes
    }
}
