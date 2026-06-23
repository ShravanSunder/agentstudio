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

    func register(
        _ resource: BridgeTransportResourceURL,
        paneId: UUID,
        descriptorId: String? = nil,
        maxBytes: Int? = nil
    ) {
        register(
            BridgeTransportResourceLease(
                paneId: paneId,
                descriptorId: descriptorId ?? resource.opaqueId,
                resource: resource,
                maxBytes: maxBytes
            ))
    }

    func register(_ lease: BridgeTransportResourceLease) {
        leasesByCanonicalURL[lease.resource.canonicalURL] = lease
    }

    func revoke(_ resource: BridgeTransportResourceURL) {
        leasesByCanonicalURL.removeValue(forKey: resource.canonicalURL)
    }

    func contains(_ resource: BridgeTransportResourceURL, paneId: UUID) -> Bool {
        guard let lease = leasesByCanonicalURL[resource.canonicalURL] else {
            return false
        }
        return lease.paneId == paneId && lease.resource == resource
    }
}
