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

    private struct ResourceRevocationKey: Hashable {
        let paneId: UUID
        let protocolId: String
        let resourceKind: String
        let canonicalURL: String

        init(resource: BridgeTransportResourceURL, paneId: UUID) {
            self.paneId = paneId
            protocolId = resource.protocolId
            resourceKind = resource.resourceKind
            canonicalURL = resource.canonicalURL
        }

        func matches(resource: BridgeTransportResourceURL, paneId: UUID) -> Bool {
            self.paneId == paneId && canonicalURL == resource.canonicalURL
        }

        func matches(paneId: UUID, protocolId: String, resourceKind: String) -> Bool {
            self.paneId == paneId && self.protocolId == protocolId && self.resourceKind == resourceKind
        }
    }

    private let lock = NSLock()
    private var revokedKeys: Set<RevocationKey> = []
    private var revokedResourceKeys: Set<ResourceRevocationKey> = []
    private var revocationRevisionByKey: [RevocationKey: UInt64] = [:]

    func revoke(paneId: UUID, protocolId: String?, resourceKind: String?) {
        lock.withLock {
            let key = RevocationKey(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
            _ = revokedKeys.insert(key)
            revocationRevisionByKey[key, default: 0] += 1
        }
    }

    func revoke(resource: BridgeTransportResourceURL, paneId: UUID) {
        lock.withLock {
            let resourceKey = ResourceRevocationKey(resource: resource, paneId: paneId)
            _ = revokedResourceKeys.insert(resourceKey)
            let revisionKey = RevocationKey(
                paneId: paneId,
                protocolId: resource.protocolId,
                resourceKind: resource.resourceKind
            )
            revocationRevisionByKey[revisionKey, default: 0] += 1
        }
    }

    func authorize(
        paneId: UUID,
        protocolId: String,
        resourceKind: String,
        expectedRevocationRevision: UInt64? = nil,
        resource: BridgeTransportResourceURL? = nil
    ) -> Bool {
        lock.withLock {
            if let expectedRevocationRevision,
                revocationRevisionLocked(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
                    != expectedRevocationRevision
            {
                return false
            }
            revokedKeys = revokedKeys.filter { key in
                guard key.paneId == paneId else { return true }
                guard key.protocolId.map({ $0 == protocolId }) ?? true else { return true }
                guard key.resourceKind.map({ $0 == resourceKind }) ?? true else { return true }
                return false
            }
            if let resource {
                revokedResourceKeys.remove(
                    ResourceRevocationKey(resource: resource, paneId: paneId)
                )
            } else {
                revokedResourceKeys = revokedResourceKeys.filter { key in
                    !key.matches(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
                }
            }
            return true
        }
    }

    func isRevoked(resource: BridgeTransportResourceURL, paneId: UUID) -> Bool {
        lock.withLock {
            revokedResourceKeys.contains { key in
                key.matches(resource: resource, paneId: paneId)
            }
                || revokedKeys.contains { key in
                    key.matches(resource: resource, paneId: paneId)
                }
        }
    }

    func performWhileNotRevoked(
        resource: BridgeTransportResourceURL,
        paneId: UUID,
        _ operation: () -> Bool
    ) -> Bool {
        lock.withLock {
            guard
                !revokedResourceKeys.contains(where: { key in
                    key.matches(resource: resource, paneId: paneId)
                }),
                !revokedKeys.contains(where: { key in
                    key.matches(resource: resource, paneId: paneId)
                })
            else {
                return false
            }
            return operation()
        }
    }

    func isRevoked(paneId: UUID, protocolId: String, resourceKind: String) -> Bool {
        lock.withLock {
            revokedKeys.contains { key in
                guard key.paneId == paneId else { return false }
                guard key.protocolId.map({ $0 == protocolId }) ?? true else { return false }
                guard key.resourceKind.map({ $0 == resourceKind }) ?? true else { return false }
                return true
            }
        }
    }

    func revocationRevision(paneId: UUID, protocolId: String, resourceKind: String) -> UInt64 {
        lock.withLock {
            revocationRevisionLocked(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
        }
    }

    private func revocationRevisionLocked(paneId: UUID, protocolId: String, resourceKind: String) -> UInt64 {
        revocationRevisionByKey.reduce(0) { partialResult, element in
            let key = element.key
            guard key.paneId == paneId else { return partialResult }
            guard key.protocolId.map({ $0 == protocolId }) ?? true else { return partialResult }
            guard key.resourceKind.map({ $0 == resourceKind }) ?? true else { return partialResult }
            return partialResult &+ element.value
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

    nonisolated func isRevokedSynchronously(
        paneId: UUID,
        protocolId: String,
        resourceKind: String
    ) -> Bool {
        authorityGate.isRevoked(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
    }

    nonisolated func revocationRevision(
        paneId: UUID,
        protocolId: String,
        resourceKind: String
    ) -> UInt64 {
        authorityGate.revocationRevision(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
    }

    @discardableResult
    func register(
        _ resource: BridgeTransportResourceURL,
        paneId: UUID,
        descriptorId: String? = nil,
        maxBytes: Int? = nil,
        expectedRevocationRevision: UInt64
    ) -> Bool {
        register(
            BridgeTransportResourceLease(
                paneId: paneId,
                descriptorId: descriptorId ?? resource.opaqueId,
                resource: resource,
                maxBytes: maxBytes
            ),
            expectedRevocationRevision: expectedRevocationRevision
        )
    }

    @discardableResult
    func register(
        _ lease: BridgeTransportResourceLease,
        expectedRevocationRevision: UInt64
    ) -> Bool {
        guard lease.descriptorId == lease.resource.opaqueId,
            lease.maxBytes.map({ $0 >= 0 }) ?? true
        else {
            return false
        }
        guard
            authorityGate.authorize(
                paneId: lease.paneId,
                protocolId: lease.resource.protocolId,
                resourceKind: lease.resource.resourceKind,
                expectedRevocationRevision: expectedRevocationRevision,
                resource: lease.resource
            )
        else {
            return false
        }
        leasesByCanonicalURL[lease.resource.canonicalURL] = lease
        return true
    }

    func revoke(_ resource: BridgeTransportResourceURL) {
        guard let lease = leasesByCanonicalURL.removeValue(forKey: resource.canonicalURL) else {
            return
        }
        authorityGate.revoke(resource: lease.resource, paneId: lease.paneId)
    }

    func reset(
        paneId: UUID,
        protocolId: String? = nil,
        resourceKind: String? = nil,
        generation: Int? = nil,
        revision: Int? = nil,
        cursor: String? = nil,
        revokeAuthority: Bool = true
    ) {
        if revokeAuthority, generation == nil, revision == nil, cursor == nil {
            authorityGate.revoke(paneId: paneId, protocolId: protocolId, resourceKind: resourceKind)
        }
        let isFilteredReset = generation != nil || revision != nil || cursor != nil
        var retainedLeasesByCanonicalURL: [String: BridgeTransportResourceLease] = [:]
        for (canonicalURL, lease) in leasesByCanonicalURL {
            let shouldRemove =
                lease.paneId == paneId
                && (protocolId.map({ lease.resource.protocolId == $0 }) ?? true)
                && (resourceKind.map({ lease.resource.resourceKind == $0 }) ?? true)
                && (generation.map({ lease.resource.generation == $0 }) ?? true)
                && (revision.map({ lease.resource.revision == $0 }) ?? true)
                && (cursor.map({ lease.resource.cursor == $0 }) ?? true)
            if shouldRemove, revokeAuthority, isFilteredReset {
                authorityGate.revoke(resource: lease.resource, paneId: lease.paneId)
            }
            if !shouldRemove {
                retainedLeasesByCanonicalURL[canonicalURL] = lease
            }
        }
        leasesByCanonicalURL = retainedLeasesByCanonicalURL
    }

    @discardableResult
    func replace(
        paneId: UUID,
        protocolId: String,
        resourceKind: String,
        leases: [BridgeTransportResourceLease],
        expectedRevocationRevision: UInt64
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
        guard
            authorityGate.authorize(
                paneId: paneId,
                protocolId: protocolId,
                resourceKind: resourceKind,
                expectedRevocationRevision: expectedRevocationRevision
            )
        else {
            return false
        }
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
        return containsActiveLease(resource, paneId: paneId, contentLength: contentLength)
    }

    func performWhileLeased(
        _ resource: BridgeTransportResourceURL,
        paneId: UUID,
        contentLength: Int? = nil,
        _ operation: () -> Void
    ) -> Bool {
        authorityGate.performWhileNotRevoked(resource: resource, paneId: paneId) {
            guard containsActiveLease(resource, paneId: paneId, contentLength: contentLength) else {
                return false
            }
            operation()
            return true
        }
    }

    private func containsActiveLease(
        _ resource: BridgeTransportResourceURL,
        paneId: UUID,
        contentLength: Int?
    ) -> Bool {
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
