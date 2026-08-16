import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane product File metadata publication ordering")
struct FileMetadataPublicationOrderingTests {
    @Test("published descriptor immediately authorizes its content read plan")
    func publishedDescriptorImmediatelyAuthorizesContentReadPlan() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let updatedSnapshot = try fixture.updatedSnapshot(from: openSnapshot)
        let observation = ImmediateFileContentReadPlanObservation()

        // Act
        try await source.update(
            subscription: updatedSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            guard case .descriptorReady(let ready) = event,
                case .available(let descriptor) = ready.payload.availability
            else { return }
            let request = try fixture.contentRequest(descriptor: descriptor)
            await observation.record(
                await source.contentReadPlan(
                    for: request,
                    productAdmission: fixture.productAdmission.context
                ) != nil
            )
        }

        // Assert
        #expect(await observation.wasImmediatelyAuthorized == true)
    }

    @Test("failed descriptor publication revokes its content read plan")
    func failedDescriptorPublicationRevokesContentReadPlan() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let updatedSnapshot = try fixture.updatedSnapshot(from: openSnapshot)
        let observation = ImmediateFileContentReadPlanObservation()

        // Act
        do {
            try await source.update(
                subscription: updatedSnapshot,
                productAdmission: fixture.productAdmission.context
            ) { event in
                guard case .descriptorReady(let ready) = event,
                    case .available(let descriptor) = ready.payload.availability
                else { return }
                await observation.record(descriptor)
                throw DescriptorPublicationTestError.expectedEmissionFailure
            }
            Issue.record("Expected descriptor publication to fail")
        } catch DescriptorPublicationTestError.expectedEmissionFailure {
            // Expected.
        }

        // Assert
        let descriptor = try #require(await observation.descriptor)
        let request = try fixture.contentRequest(descriptor: descriptor)
        let readPlan = await source.contentReadPlan(
            for: request,
            productAdmission: fixture.productAdmission.context
        )
        #expect(readPlan == nil)
    }
}

private actor ImmediateFileContentReadPlanObservation {
    private(set) var descriptor: BridgeProductFileContentDescriptor?
    private(set) var wasImmediatelyAuthorized = false

    func record(_ wasAuthorized: Bool) {
        wasImmediatelyAuthorized = wasAuthorized
    }

    func record(_ descriptor: BridgeProductFileContentDescriptor) {
        self.descriptor = descriptor
    }
}

private enum DescriptorPublicationTestError: Error {
    case expectedEmissionFailure
}
