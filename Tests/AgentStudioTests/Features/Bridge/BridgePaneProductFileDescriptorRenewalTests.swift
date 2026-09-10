import AgentStudioCore
import CryptoKit
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge File descriptor renewal after invalidation")
struct BridgePaneProductFileDescriptorRenewalTests {
    @Test("retained interests receive fresh descriptor authority when their file changes")
    func retainedInterestsRenewInvalidatedDescriptor() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let refreshAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground()
        let source = fixture.makeSource()
        let opened = try fixture.openSnapshot()
        try await source.open(
            subscription: opened,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let interests = try fixture.updatedSnapshot(from: opened)
        let initialEvents = ProductFileMetadataEventCollector()
        try await source.update(
            subscription: interests,
            productAdmission: fixture.productAdmission.context
        ) { await initialEvents.append($0) }
        let previousDescriptor = try #require(
            (await initialEvents.events).compactMap(availableRenewalDescriptor).first
        )
        let previousRequest = try fixture.contentRequest(descriptor: previousDescriptor)
        let replacementBytes = Data("replacement content for retained selection\n".utf8)
        try replacementBytes.write(to: fixture.demandedFileURL)

        // Act — isolate production capability from the caller deciding to renew demand.
        let published = try await source.publish(
            changeset: FileChangeset(
                worktreeId: fixture.worktreeId,
                repoId: fixture.repoId,
                rootPath: fixture.rootURL,
                paths: [fixture.demandedPath],
                timestamp: .now,
                batchSeq: 1
            ),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: refreshAdmission.admission
        )
        let staleReadPlan = await source.contentReadPlan(
            for: previousRequest,
            productAdmission: fixture.productAdmission.context
        )
        // The live metadata owner must advance existing demand without a changed interest set.
        let publishedDescriptors = published.compactMap { availableRenewalDescriptor($0.event) }
        #expect(publishedDescriptors.count == 1)
        let renewedEvents = ProductFileMetadataEventCollector()
        try await source.update(
            subscription: interests,
            productAdmission: fixture.productAdmission.context
        ) { await renewedEvents.append($0) }

        // Assert — this explicit-renewal control does not claim automatic recovery.
        let renewedDescriptor = try #require(
            (publishedDescriptors + (await renewedEvents.events).compactMap(availableRenewalDescriptor)).first
        )
        let expectedSha256 = SHA256.hash(data: replacementBytes)
            .map { String(format: "%02x", $0) }.joined()
        #expect(staleReadPlan == nil)
        #expect(renewedDescriptor != previousDescriptor)
        #expect(renewedDescriptor.expectedSha256 == expectedSha256)
        let replacementInInvalidation = published.compactMap { emission -> BridgeProductFileContentDescriptor? in
            guard case .invalidated(let invalidation) = emission.event,
                let replacement = invalidation.replacementDescriptor,
                case .available(let descriptor) = replacement.availability
            else { return nil }
            return descriptor
        }
        #expect(replacementInInvalidation == [renewedDescriptor])
        let renewedRequest = try fixture.contentRequest(descriptor: renewedDescriptor)
        #expect(
            await source.contentReadPlan(
                for: renewedRequest,
                productAdmission: fixture.productAdmission.context
            ) != nil
        )
        print(
            "File renewal diagnostic: changeset descriptors=\(published.compactMap { availableRenewalDescriptor($0.event) }.count), explicit same-interest renewal descriptors=\((await renewedEvents.events).compactMap(availableRenewalDescriptor).count)"
        )
    }
}

private func availableRenewalDescriptor(
    _ event: BridgeProductFileMetadataEvent
) -> BridgeProductFileContentDescriptor? {
    let payload: BridgeProductFileDescriptorReadyPayload?
    switch event {
    case .descriptorReady(let ready): payload = ready.payload
    case .invalidated(let invalidation): payload = invalidation.replacementDescriptor
    default: payload = nil
    }
    guard let payload, case .available(let descriptor) = payload.availability else { return nil }
    return descriptor
}
