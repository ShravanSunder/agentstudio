import AgentStudioAppIPC
import AgentStudioCore
import AgentStudioInfrastructure
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio

@Suite("Pane IPC identity owner")
struct PaneIPCIdentityOwnerTests {
    @Test("preparation validates membership and persists only the token verifier")
    func preparationValidatesMembershipAndPersistsTokenVerifier() async throws {
        let fixture = try PaneIPCIdentityOwnerFixture()
        defer { fixture.removeFiles() }
        let datastore = await fixture.makePreparedDatastore()
        let repository = IPCContinuityRepository(datastore: datastore)
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let rawBytes = Data(repeating: 0xA5, count: 32)
        let owner = makeIdentityOwner(
            repository: repository,
            membership: { candidatePaneID, candidateWorkspaceID in
                candidatePaneID == paneID && candidateWorkspaceID == workspaceID
            },
            rawBytes: rawBytes,
            fixture: fixture
        )

        let preparation = try await owner.prepareEnvironment(paneID: paneID, workspaceID: workspaceID)
        let rawToken = try #require(preparation.environmentVariables["AGENTSTUDIO_PANE_TOKEN"])
        let verifier = Data(SHA256.hash(data: Data(rawToken.utf8)))
        let persisted = try #require(
            try await repository.credential(for: paneID, generation: preparation.generationID)
        )

        #expect(preparation.environmentVariables["AGENTSTUDIO_PANE_ID"] == paneID.uuidString)
        #expect(preparation.environmentVariables["AGENTSTUDIO_WORKSPACE_ID"] == workspaceID.uuidString)
        #expect(preparation.environmentVariables["AGENTSTUDIO_IPC_SOCKET"] == fixture.socketURL.path)
        #expect(preparation.environmentVariables["AGENTSTUDIO_PANE_TOKEN"] == rawBytes.base64EncodedString())
        #expect(
            preparation.environmentVariables["AGENTSTUDIO_IPC_GENERATION_ID"] == preparation.generationID.uuidString)
        #expect(preparation.environmentVariables["AGENTSTUDIO_IPC_SPOOL_DIR"] == fixture.spoolDirectory.path)
        #expect(preparation.environmentVariables["AGENTSTUDIO_CLI"] == fixture.cliExecutableURL.path)
        #expect(
            preparation.environmentVariables["PATH"]
                == "\(fixture.cliExecutableURL.deletingLastPathComponent().path):/usr/bin:/bin"
        )
        #expect(persisted.workspaceID == workspaceID)
        #expect(persisted.generation == preparation.generationID)
        #expect(persisted.status == .prepared)
        #expect(persisted.verifier == verifier)
        #expect(persisted.verifier != Data(rawToken.utf8))
    }

    @Test("preparation refuses a pane outside canonical workspace membership without a row")
    func preparationRejectsNonmemberWithoutPersistingCandidate() async throws {
        let fixture = try PaneIPCIdentityOwnerFixture()
        defer { fixture.removeFiles() }
        let repository = IPCContinuityRepository(datastore: await fixture.makePreparedDatastore())
        let rawBytes = Data(repeating: 0xB4, count: 32)
        let rejectedPaneID = UUIDv7.generate()
        let rejectedWorkspaceID = UUIDv7.generate()
        let expectedRawToken = rawBytes.base64EncodedString()
        let expectedVerifier = Data(SHA256.hash(data: Data(expectedRawToken.utf8)))
        let owner = makeIdentityOwner(
            repository: repository,
            membership: { _, _ in false },
            rawBytes: rawBytes,
            fixture: fixture
        )

        await #expect(throws: PaneIPCIdentityOwnerError.paneNotInWorkspace) {
            _ = try await owner.prepareEnvironment(paneID: rejectedPaneID, workspaceID: rejectedWorkspaceID)
        }
        #expect(try await repository.credential(matchingVerifier: expectedVerifier) == nil)
    }

    @Test("cancellation, rollback, and retirement affect only their exact generation")
    func lifecycleRetiresOnlyTheExactCredentialGeneration() async throws {
        let fixture = try PaneIPCIdentityOwnerFixture()
        defer { fixture.removeFiles() }
        let repository = IPCContinuityRepository(datastore: await fixture.makePreparedDatastore())
        let paneID = UUIDv7.generate()
        let workspaceID = UUIDv7.generate()
        let leaseRecorder = PaneCredentialLeaseRecorder()
        let owner = PaneIPCIdentityOwner(
            repository: repository,
            socketURL: fixture.socketURL,
            spoolDirectory: fixture.spoolDirectory,
            cliExecutableURL: fixture.cliExecutableURL,
            inheritedEnvironment: ["PATH": "/usr/bin:/bin"],
            canonicalPaneMembership: { candidatePaneID, candidateWorkspaceID in
                candidatePaneID == paneID && candidateWorkspaceID == workspaceID
            },
            randomBytes: PaneCredentialByteSequence([
                Data(repeating: 0x01, count: 32),
                Data(repeating: 0x02, count: 32),
                Data(repeating: 0x03, count: 32),
            ]).next,
            retireServerLease: { retiredPaneID, retiredWorkspaceID, retiredGenerationID in
                leaseRecorder.record(
                    paneID: retiredPaneID,
                    workspaceID: retiredWorkspaceID,
                    generationID: retiredGenerationID
                )
            }
        )

        let cancelled = try await owner.prepareEnvironment(paneID: paneID, workspaceID: workspaceID)
        let sibling = try await owner.prepareEnvironment(paneID: paneID, workspaceID: workspaceID)
        await owner.cancelPrepared(cancelled)
        #expect(
            try await repository.credential(for: paneID, generation: cancelled.generationID)?.status == .revoked
        )
        #expect(
            try await repository.credential(for: paneID, generation: sibling.generationID)?.status == .prepared
        )

        let activated = try await owner.activateForMount(sibling)
        await owner.rollbackFailedMount(activated)
        #expect(
            try await repository.credential(for: paneID, generation: sibling.generationID)?.status == .revoked
        )
        #expect(
            leaseRecorder.calls == [.init(paneID: paneID, workspaceID: workspaceID, generationID: sibling.generationID)]
        )

        let retained = try await owner.prepareEnvironment(paneID: paneID, workspaceID: workspaceID)
        let retainedActivation = try await owner.activateForMount(retained)
        try await owner.retire(retainedActivation)
        #expect(
            try await repository.credential(for: paneID, generation: retained.generationID)?.status == .revoked
        )
        #expect(
            leaseRecorder.calls == [
                .init(paneID: paneID, workspaceID: workspaceID, generationID: sibling.generationID),
                .init(paneID: paneID, workspaceID: workspaceID, generationID: retained.generationID),
            ]
        )
    }

    private func makeIdentityOwner(
        repository: IPCContinuityRepository,
        membership: @escaping @MainActor @Sendable (UUID, UUID) -> Bool,
        rawBytes: Data,
        fixture: PaneIPCIdentityOwnerFixture
    ) -> PaneIPCIdentityOwner {
        PaneIPCIdentityOwner(
            repository: repository,
            socketURL: fixture.socketURL,
            spoolDirectory: fixture.spoolDirectory,
            cliExecutableURL: fixture.cliExecutableURL,
            inheritedEnvironment: ["PATH": "/usr/bin:/bin"],
            canonicalPaneMembership: membership,
            randomBytes: { rawBytes },
            retireServerLease: { _, _, _ in }
        )
    }
}

private struct PaneIPCIdentityOwnerFixture {
    let rootDirectory: URL
    let localDatabaseURL: URL
    let coreDatabaseURL: URL
    let socketURL: URL
    let spoolDirectory: URL
    let cliExecutableURL: URL

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-pane-ipc-identity-\(UUIDv7.generate())")
        localDatabaseURL = rootDirectory.appending(path: "local.sqlite")
        coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")
        socketURL = rootDirectory.appending(path: "agentstudio.sock")
        spoolDirectory = rootDirectory.appending(path: "spool/v2", directoryHint: .isDirectory)
        cliExecutableURL = rootDirectory.appending(path: "AgentStudio.app/Contents/MacOS/agentstudio")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func makePreparedDatastore() async -> WorkspaceSQLiteDatastoreActor {
        let datastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            fatalError("Pane IPC identity test database preparation failed")
        }
        return datastore
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private final class PaneCredentialLeaseRecorder: @unchecked Sendable {
    struct Call: Equatable {
        let paneID: UUID
        let workspaceID: UUID
        let generationID: UUID
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    func record(paneID: UUID, workspaceID: UUID, generationID: UUID) {
        lock.withLock {
            recordedCalls.append(.init(paneID: paneID, workspaceID: workspaceID, generationID: generationID))
        }
    }
}

private final class PaneCredentialByteSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Data]

    init(_ values: [Data]) {
        self.values = values
    }

    func next() throws -> Data {
        try lock.withLock {
            guard !values.isEmpty else { throw PaneIPCIdentityOwnerError.randomBytesUnavailable }
            return values.removeFirst()
        }
    }
}
