import Foundation

struct BridgeSharedReviewContentLocator: Equatable, Sendable {
    let providerIdentity: String
    let contentIdentity: String
    let digest: String
}

struct BridgeSharedReviewDescriptorCore: Equatable, Sendable {
    let itemIdentity: String
    let semanticVersion: String
    let baseLocator: BridgeSharedReviewContentLocator?
    let headLocator: BridgeSharedReviewContentLocator?
}

struct BridgeSharedReviewGroup: Equatable, Sendable {
    let groupIdentity: String
    let orderedItemIdentities: [String]
}

struct BridgeSharedReviewSummary: Equatable, Sendable {
    let filesChanged: Int
    let additions: Int
    let deletions: Int
}

struct BridgeSharedReviewPackageTemplate: Equatable, Sendable {
    let baseEndpoint: BridgeResolvedReviewEndpointKey
    let headEndpoint: BridgeResolvedReviewEndpointKey
    let orderedItemIdentities: [String]
    let descriptorCores: [BridgeSharedReviewDescriptorCore]
    let groups: [BridgeSharedReviewGroup]
    let summary: BridgeSharedReviewSummary
    let retainedByteCount: Int

    var contentLocatorCount: Int {
        descriptorCores.reduce(into: 0) { count, descriptor in
            count += descriptor.baseLocator == nil ? 0 : 1
            count += descriptor.headLocator == nil ? 0 : 1
        }
    }
}
