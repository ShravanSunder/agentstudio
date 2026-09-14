import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@Suite("IPC continuity credential repository")
struct IPCContinuityRepositoryTests {
    @Test("unprepared credential storage does not open another database")
    func unpreparedCredentialStorageDoesNotOpenAnotherDatabase() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let generation = UUIDv7.generate()
        let verifier = Data(repeating: 0xA5, count: 32)

        let unpreparedRepository = IPCContinuityRepository(datastore: fixture.makeDatastore())
        await #expect(throws: WorkspaceSQLiteDatastoreError.databasesNotPrepared) {
            try await unpreparedRepository.persistPreparedPaneCredential(
                paneID: paneID,
                workspaceID: workspaceID,
                generation: generation,
                verifier: verifier
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.localDatabaseURL.path))
    }

    @Test("prepared pane credentials activate idempotently and revoked candidates cannot activate")
    func preparedPaneCredentialLifecycleUsesPreparedApplicationLocalDatabase() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let generation = UUIDv7.generate()
        let verifier = Data(repeating: 0xA5, count: 32)
        let cancelledPaneID = UUIDv7.generate()
        let cancelledGeneration = UUIDv7.generate()

        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        try await repository.persistPreparedPaneCredential(
            paneID: paneID,
            workspaceID: workspaceID,
            generation: generation,
            verifier: verifier
        )
        #expect(
            try await repository.credential(for: paneID, generation: generation)?.status == .prepared
        )
        try await repository.activatePreparedPaneCredential(paneID: paneID, generation: generation)
        try await repository.activatePreparedPaneCredential(paneID: paneID, generation: generation)
        let activeCredential = try #require(
            try await repository.credential(for: paneID, generation: generation)
        )
        #expect(activeCredential.status == .active)
        #expect(activeCredential.workspaceID == workspaceID)
        #expect(activeCredential.generation == generation)
        #expect(activeCredential.verifier == verifier)

        try await repository.persistPreparedPaneCredential(
            paneID: cancelledPaneID,
            workspaceID: workspaceID,
            generation: cancelledGeneration,
            verifier: verifier
        )
        try await repository.revokePreparedPaneCredential(
            paneID: cancelledPaneID,
            generation: cancelledGeneration
        )
        #expect(
            try await repository.credential(for: cancelledPaneID, generation: cancelledGeneration)?.status
                == .revoked
        )
        await #expect(throws: IPCContinuityRepositoryError.cannotActivateRevokedCredential) {
            try await repository.activatePreparedPaneCredential(
                paneID: cancelledPaneID,
                generation: cancelledGeneration
            )
        }
    }

    @Test("prepared candidate identity is idempotent only for identical immutable intent")
    func preparedCandidateIdentityRejectsConflictingIntentWithoutReplacement() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let generation = UUIDv7.generate()
        let verifier = Data(repeating: 0xA5, count: 32)
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        try await repository.persistPreparedPaneCredential(
            paneID: paneID, workspaceID: workspaceID, generation: generation, verifier: verifier
        )
        try await repository.persistPreparedPaneCredential(
            paneID: paneID, workspaceID: workspaceID, generation: generation, verifier: verifier
        )
        await #expect(throws: IPCContinuityRepositoryError.conflictingPreparedCredential) {
            try await repository.persistPreparedPaneCredential(
                paneID: paneID, workspaceID: UUIDv7.generate(), generation: generation, verifier: verifier
            )
        }
        await #expect(throws: IPCContinuityRepositoryError.conflictingPreparedCredential) {
            try await repository.persistPreparedPaneCredential(
                paneID: paneID, workspaceID: workspaceID, generation: generation,
                verifier: Data(repeating: 0x5A, count: 32)
            )
        }
        let retained = try #require(try await repository.credential(for: paneID, generation: generation))
        #expect(retained.workspaceID == workspaceID)
        #expect(retained.verifier == verifier)
        #expect(retained.status == .prepared)
    }

    @Test("revocation changes only the exact prepared pane generation")
    func revokePreparedCredentialLeavesSiblingGenerationAndActiveCredentialUntouched() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let firstGeneration = UUIDv7.generate()
        let secondGeneration = UUIDv7.generate()
        let verifier = Data(repeating: 0xA5, count: 32)
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        try await repository.persistPreparedPaneCredential(
            paneID: paneID, workspaceID: workspaceID, generation: firstGeneration, verifier: verifier
        )
        try await repository.persistPreparedPaneCredential(
            paneID: paneID, workspaceID: workspaceID, generation: secondGeneration, verifier: verifier
        )
        try await repository.revokePreparedPaneCredential(paneID: paneID, generation: firstGeneration)
        #expect(try await repository.credential(for: paneID, generation: firstGeneration)?.status == .revoked)
        #expect(try await repository.credential(for: paneID, generation: secondGeneration)?.status == .prepared)
        try await repository.activatePreparedPaneCredential(paneID: paneID, generation: secondGeneration)
        try await repository.revokePreparedPaneCredential(paneID: paneID, generation: secondGeneration)
        #expect(try await repository.credential(for: paneID, generation: secondGeneration)?.status == .active)
    }

    @Test("invalid verifier length is rejected without a persisted candidate")
    func invalidVerifierLengthDoesNotPersistCredential() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let paneID = UUIDv7.generate()
        let generation = UUIDv7.generate()
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        let repository = IPCContinuityRepository(datastore: datastore)
        await #expect(throws: IPCContinuityRepositoryError.invalidVerifierLength) {
            try await repository.persistPreparedPaneCredential(
                paneID: paneID,
                workspaceID: UUIDv7.generate(),
                generation: generation,
                verifier: Data(repeating: 0xA5, count: 31)
            )
        }
        #expect(try await repository.credential(for: paneID, generation: generation) == nil)
    }

    @Test("active and revoked pane credentials survive prepared datastore reopening")
    func credentialLifecycleSurvivesPreparedDatastoreReopening() async throws {
        let fixture = try IPCContinuityRepositoryFixture()
        defer { fixture.removeFiles() }
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let generation = UUIDv7.generate()
        let cancelledPaneID = UUIDv7.generate()
        let cancelledGeneration = UUIDv7.generate()
        let verifier = Data(repeating: 0xA5, count: 32)
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Database preparation failed")
            return
        }
        try await datastore.saveWorkspaceSnapshotBundle(
            WorkspaceSQLiteSaveBundle(workspace: .init(id: UUIDv7.generate(), name: "IPC continuity proof"))
        )
        let repository = IPCContinuityRepository(datastore: datastore)
        try await repository.persistPreparedPaneCredential(
            paneID: paneID, workspaceID: workspaceID, generation: generation, verifier: verifier
        )
        try await repository.activatePreparedPaneCredential(paneID: paneID, generation: generation)
        try await repository.persistPreparedPaneCredential(
            paneID: cancelledPaneID, workspaceID: workspaceID, generation: cancelledGeneration,
            verifier: verifier
        )
        try await repository.revokePreparedPaneCredential(
            paneID: cancelledPaneID,
            generation: cancelledGeneration
        )

        let reopenedDatastore = fixture.makeDatastore()
        guard case .prepared = await reopenedDatastore.prepareDatabasesForBoot() else {
            Issue.record("Database reopening failed")
            return
        }
        let reopenedRepository = IPCContinuityRepository(datastore: reopenedDatastore)
        let reopenedCredential = try #require(
            try await reopenedRepository.credential(for: paneID, generation: generation)
        )
        #expect(reopenedCredential.status == .active)
        #expect(reopenedCredential.workspaceID == workspaceID)
        #expect(reopenedCredential.verifier == verifier)
        #expect(
            try await reopenedRepository.credential(for: cancelledPaneID, generation: cancelledGeneration)?.status
                == .revoked
        )
    }
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

    func makeDatastore() -> WorkspaceSQLiteDatastoreActor {
        WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
