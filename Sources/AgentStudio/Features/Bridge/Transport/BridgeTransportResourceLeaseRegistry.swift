import Foundation

actor BridgeTransportResourceLeaseRegistry {
    private var leasedCanonicalURLs: Set<String> = []

    func register(_ resource: BridgeTransportResourceURL) {
        leasedCanonicalURLs.insert(resource.canonicalURL)
    }

    func revoke(_ resource: BridgeTransportResourceURL) {
        leasedCanonicalURLs.remove(resource.canonicalURL)
    }

    func contains(_ resource: BridgeTransportResourceURL) -> Bool {
        leasedCanonicalURLs.contains(resource.canonicalURL)
    }
}
