import AgentStudioAppIPC
import AgentStudioInfrastructure
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("IPC continuity credential repository", .serialized)
struct IPCContinuityRepositoryTests {
    @Test("pane registration is idempotent only for identical immutable intent")
    func paneRegistrationIsImmutableAndIdempotent() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let credential = makePaneCredential()
        try await repository.registerPaneCredential(credential)
        try await repository.registerPaneCredential(credential)
        let conflicting = IPCPaneCredential(
            paneID: credential.paneID,
            workspaceID: UUIDv7.generate(),
            credentialRecordID: credential.credentialRecordID,
            verifierSHA256: credential.verifierSHA256,
            status: .registered
        )
        await #expect(throws: IPCContinuityRepositoryError.conflictingCredentialRecord) {
            try await repository.registerPaneCredential(conflicting)
        }
        let conflictingVerifier = IPCPaneCredential(
            paneID: credential.paneID,
            workspaceID: credential.workspaceID,
            credentialRecordID: credential.credentialRecordID,
            verifierSHA256: Data(repeating: 0xB6, count: 32),
            status: .registered
        )
        await #expect(throws: IPCContinuityRepositoryError.conflictingCredentialRecord) {
            try await repository.registerPaneCredential(conflictingVerifier)
        }
        #expect(try await repository.paneCredentials(paneID: credential.paneID) == [credential])
    }

    @Test("invalid verifier length is rejected without writing a row")
    func invalidVerifierLengthDoesNotPersist() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let credential = makePaneCredential(verifier: Data(repeating: 0xA5, count: 31))

        await #expect(throws: IPCContinuityRepositoryError.invalidVerifierLength) {
            try await repository.registerPaneCredential(credential)
        }
        #expect(try await repository.paneCredentials(paneID: credential.paneID).isEmpty)
    }

    @Test("two records for one pane coexist and revoke-all isolates another pane")
    func additivePaneRecordsRevokeTogether() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let first = makePaneCredential(paneID: paneID, workspaceID: workspaceID, byte: 0x11)
        let second = makePaneCredential(paneID: paneID, workspaceID: workspaceID, byte: 0x22)
        let other = makePaneCredential(byte: 0x33)
        try await repository.registerPaneCredential(first)
        try await repository.registerPaneCredential(second)
        try await repository.registerPaneCredential(other)
        try await repository.revokeAllPaneCredentials(paneID: paneID)
        #expect(try await repository.paneCredentials(paneID: paneID).map(\.status) == [.revoked, .revoked])
        #expect(try await repository.paneCredentials(paneID: other.paneID) == [other])
    }

    @Test("exact verifier lookup rejects ambiguous matches")
    func verifierLookupIsExactAndFailClosed() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let sharedVerifier = Data(repeating: 0x44, count: 32)
        let first = makePaneCredential(verifier: sharedVerifier)
        let second = makePaneCredential(verifier: sharedVerifier)
        try await repository.registerPaneCredential(first)
        #expect(try await repository.credential(matchingVerifier: sharedVerifier) == .pane(first))
        try await repository.registerPaneCredential(second)
        await #expect(throws: IPCContinuityRepositoryError.ambiguousVerifier) {
            _ = try await repository.credential(matchingVerifier: sharedVerifier)
        }
    }

    @Test("ambiguous durable verifier becomes controlled unauthenticated resolution")
    func resolverMapsAmbiguousVerifierToUnauthenticated() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let token = AgentStudioIPCSubjectToken(rawValue: "ambiguous-durable-token")
        let verifier = Data(SHA256.hash(data: Data(token.rawValue.utf8)))
        try await repository.registerPaneCredential(makePaneCredential(verifier: verifier))
        try await repository.registerPaneCredential(makePaneCredential(verifier: verifier))
        let resolver = IPCContinuityCredentialResolver(repository: repository)

        await #expect(throws: AgentStudioIPCAuthenticationError(reason: .unauthenticated)) {
            _ = try await resolver.resolveCredential(token, serverRuntimeID: UUIDv7.generate())
        }
    }

    @Test("registered replay after revoke cannot restore a record across reopening")
    func registeredReplayAfterRevokeIsRefused() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let credential = makePaneCredential()
        try await repository.registerPaneCredential(credential)
        try await repository.revokeAllPaneCredentials(paneID: credential.paneID)

        await #expect(throws: IPCContinuityRepositoryError.conflictingCredentialRecord) {
            try await repository.registerPaneCredential(credential)
        }
        let reopened = try await fixture.makePreparedRepository()
        #expect(
            try await reopened.paneCredential(
                paneID: credential.paneID,
                credentialRecordID: credential.credentialRecordID
            )
                == IPCPaneCredential(
                    paneID: credential.paneID,
                    workspaceID: credential.workspaceID,
                    credentialRecordID: credential.credentialRecordID,
                    verifierSHA256: credential.verifierSHA256,
                    status: .revoked
                ))
    }

    @Test("pane records and diagnostic credentials survive datastore reopening")
    func credentialsSurviveReopening() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let pane = makePaneCredential()
        let runtimeID = UUIDv7.generate()
        let generationID = UUIDv7.generate()
        let diagnosticVerifier = Data(repeating: 0x5A, count: 32)
        try await repository.registerPaneCredential(pane)
        try await repository.persistPreparedDiagnosticCredential(
            runtimeID: runtimeID,
            generation: generationID,
            verifier: diagnosticVerifier
        )
        try await repository.activatePreparedDiagnosticCredential(runtimeID: runtimeID, generation: generationID)
        let reopened = try await fixture.makePreparedRepository()
        #expect(
            try await reopened.paneCredential(
                paneID: pane.paneID,
                credentialRecordID: pane.credentialRecordID
            ) == pane)
        #expect(
            try await reopened.credential(matchingVerifier: diagnosticVerifier)
                == .diagnostic(
                    runtimeID: runtimeID,
                    generationID: generationID,
                    verifierSHA256: diagnosticVerifier,
                    status: .active
                ))
    }
}

private func makePaneCredential(
    paneID: UUID = UUIDv7.generate(),
    workspaceID: UUID = UUIDv7.generate(),
    credentialRecordID: UUID = UUIDv7.generate(),
    verifier: Data? = nil,
    byte: UInt8 = 0xA5
) -> IPCPaneCredential {
    IPCPaneCredential(
        paneID: paneID,
        workspaceID: workspaceID,
        credentialRecordID: credentialRecordID,
        verifierSHA256: verifier ?? Data(repeating: byte, count: 32),
        status: .registered
    )
}

private struct IPCContinuityRepositoryFixture {
    let rootDirectory: URL
    let localDatabaseURL: URL
    let coreDatabaseURL: URL

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-ipc-continuity-\(UUIDv7.generate())")
        localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func makePreparedRepository() async throws -> IPCContinuityRepository {
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            throw IPCContinuityRepositoryFixtureError.databasePreparationFailed
        }
        try await datastore.saveWorkspaceSnapshotBundle(
            WorkspaceSQLiteSaveBundle(
                workspace: .init(id: UUIDv7.generate(), name: "IPC continuity repository tests")
            )
        )
        return IPCContinuityRepository(datastore: datastore)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private enum IPCContinuityRepositoryFixtureError: Error {
    case databasePreparationFailed
}
