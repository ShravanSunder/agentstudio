import Foundation

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
