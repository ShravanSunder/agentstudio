import AgentStudioAppIPC
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("IPC continuity persistence lane", .serialized)
struct IPCContinuityPersistenceLaneTests {
    @Test("final fence overtakes a held registration before SQLite and FIFO revoke leaves no active row")
    func finalFencePreventsHeldRegistrationFromPersisting() async throws {
        let fixture = try IPCContinuityPersistenceFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let barrier = PersistenceRegistrationBarrier()
        let continuityPort = ClosureCredentialContinuityPort(
            register: { credential, remainsEligible in
                await barrier.holdBeforeWrite()
                return try await repository.registerPaneCredential(
                    credential.repositoryCredential,
                    if: remainsEligible
                )
            },
            revokeAll: { paneID in
                try await repository.revokeAllPaneCredentials(paneID: paneID)
            }
        )
        let lane = AgentStudioIPCCredentialPersistenceLane(continuityPort: continuityPort)
        let registry = makeRegistry()
        let paneID = UUIDv7.generate()
        let otherPaneCredential = makeIssuedCredential(paneID: UUIDv7.generate(), byte: 0x33)
        try await repository.registerPaneCredential(otherPaneCredential.repositoryCredential)
        let credential = makeIssuedCredential(paneID: paneID, byte: 0x22)
        try registry.registerIssuedPaneCredential(credential)

        schedule(credential, registry: registry, lane: lane)
        await barrier.waitUntilHeld()
        registry.finalRevokePane(paneID)
        lane.enqueueFinalRevoke(paneID: paneID)
        barrier.release()
        #expect(await lane.drain().failedOperationCount == 0)
        #expect(continuityPort.registrationCallCount == 1)

        #expect(try await repository.paneCredentials(paneID: paneID).isEmpty)
        #expect(
            try await repository.paneCredentials(paneID: otherPaneCredential.paneID)
                == [otherPaneCredential.repositoryCredential])
    }

    @Test("registration after final fence is refused and cannot enqueue SQL")
    func registrationAfterFinalFenceIsRefused() async throws {
        let fixture = try IPCContinuityPersistenceFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let lane = AgentStudioIPCCredentialPersistenceLane(continuityPort: repository)
        let registry = makeRegistry()
        let paneID = UUIDv7.generate()
        registry.finalRevokePane(paneID)
        lane.enqueueFinalRevoke(paneID: paneID)

        #expect(throws: AgentStudioIPCIssuedCredentialRegistrationError.paneFinalRevoked) {
            try registry.registerIssuedPaneCredential(makeIssuedCredential(paneID: paneID))
        }
        #expect(await lane.drain().failedOperationCount == 0)
        #expect(try await repository.paneCredentials(paneID: paneID).isEmpty)
    }

    @Test("captured candidate final-fenced before enqueue never reaches continuity port")
    func capturedCandidateFinalFencedBeforeEnqueueIsExcludedFromSubmission() async throws {
        let registry = makeRegistry()
        let credential = makeIssuedCredential()
        try registry.registerIssuedPaneCredential(credential)
        let continuityPort = CountingCredentialContinuityPort()
        let lane = AgentStudioIPCCredentialPersistenceLane(continuityPort: continuityPort)
        let capturedCandidate = try #require(registry.issuedCredentialCandidates().first)

        registry.finalRevokePane(credential.paneID)
        schedule(capturedCandidate, registry: registry, lane: lane)
        let drainResult = await lane.drain()

        #expect(drainResult.failedOperationCount == 0)
        #expect(continuityPort.registrationCallCount == 0)
    }

    @Test("failed registration remains eligible for the next owned snapshot")
    func failedRegistrationRetriesOnlyAtNextSnapshot() async throws {
        let fixture = try IPCContinuityPersistenceFixture()
        defer { fixture.removeFiles() }
        let repository = try await fixture.makePreparedRepository()
        let failure = OneShotPersistenceFailure()
        let continuityPort = ClosureCredentialContinuityPort(
            register: { credential, remainsEligible in
                if failure.consumeFailure() { throw PersistenceFixtureError.injectedWriteFailure }
                return try await repository.registerPaneCredential(
                    credential.repositoryCredential,
                    if: remainsEligible
                )
            },
            revokeAll: { paneID in
                try await repository.revokeAllPaneCredentials(paneID: paneID)
            }
        )
        let lane = AgentStudioIPCCredentialPersistenceLane(continuityPort: continuityPort)
        let registry = makeRegistry()
        let credential = makeIssuedCredential()
        try registry.registerIssuedPaneCredential(credential)

        schedule(credential, registry: registry, lane: lane)
        #expect(await lane.drain().failedOperationCount == 1)
        #expect(await lane.drain().failedOperationCount == 0)
        #expect(try await repository.paneCredentials(paneID: credential.paneID).isEmpty)

        schedule(credential, registry: registry, lane: lane)
        #expect(await lane.drain().failedOperationCount == 0)
        #expect(
            try await repository.paneCredentials(paneID: credential.paneID)
                == [credential.repositoryCredential])
    }
}

extension AgentStudioIPCIssuedPaneCredential {
    fileprivate var repositoryCredential: IPCPaneCredential {
        IPCPaneCredential(
            paneID: paneID,
            workspaceID: workspaceID,
            credentialRecordID: credentialRecordID,
            verifierSHA256: verifierSHA256,
            status: .registered
        )
    }
}

extension AgentStudioIPCPrincipalRegistry {
    fileprivate func registerIssuedPaneCredential(_ credential: AgentStudioIPCIssuedPaneCredential) throws {
        try registerIssuedPaneCredential(
            paneID: credential.paneID,
            workspaceID: credential.workspaceID,
            credentialRecordID: credential.credentialRecordID,
            verifierSHA256: credential.verifierSHA256
        )
    }
}

private func makeIssuedCredential(
    paneID: UUID = UUIDv7.generate(),
    workspaceID: UUID = UUIDv7.generate(),
    recordID: UUID = UUIDv7.generate(),
    byte: UInt8 = 0xA5
) -> AgentStudioIPCIssuedPaneCredential {
    .init(
        paneID: paneID,
        workspaceID: workspaceID,
        credentialRecordID: recordID,
        verifierSHA256: Data(repeating: byte, count: 32)
    )
}

private func makeRegistry() -> AgentStudioIPCPrincipalRegistry {
    AgentStudioIPCPrincipalRegistry(
        runtimeId: UUIDv7.generate(),
        credentialResolver: PersistenceFixtureCredentialResolver(),
        canonicalPaneMembership: { _, _ in true }
    )
}

private func schedule(
    _ credential: AgentStudioIPCIssuedPaneCredential,
    registry: AgentStudioIPCPrincipalRegistry,
    lane: AgentStudioIPCCredentialPersistenceLane
) {
    lane.enqueueRegistration(
        credential,
        remainsEligible: { registry.registrationRemainsEligible(credential) },
        didPersist: { registry.markIssuedCredentialDurable(recordID: credential.credentialRecordID) }
    )
}

private final class ClosureCredentialContinuityPort: AgentStudioIPCCredentialContinuityPort,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let register:
        @Sendable (
            AgentStudioIPCIssuedPaneCredential,
            @escaping @Sendable () -> Bool
        ) async throws -> Bool
    private let revokeAll: @Sendable (UUID) async throws -> Void
    private var storedRegistrationCallCount = 0

    init(
        register:
            @escaping @Sendable (
                AgentStudioIPCIssuedPaneCredential,
                @escaping @Sendable () -> Bool
            ) async throws -> Bool,
        revokeAll: @escaping @Sendable (UUID) async throws -> Void
    ) {
        self.register = register
        self.revokeAll = revokeAll
    }

    var registrationCallCount: Int { lock.withLock { storedRegistrationCallCount } }

    func registerIssuedPaneCredential(
        _ credential: AgentStudioIPCIssuedPaneCredential,
        if remainsEligible: @escaping @Sendable () -> Bool
    ) async throws -> Bool {
        lock.withLock { storedRegistrationCallCount += 1 }
        return try await register(credential, remainsEligible)
    }

    func revokeAllPaneCredentials(paneID: UUID) async throws {
        try await revokeAll(paneID)
    }
}

private final class CountingCredentialContinuityPort: AgentStudioIPCCredentialContinuityPort,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedRegistrationCallCount = 0

    var registrationCallCount: Int { lock.withLock { storedRegistrationCallCount } }

    func registerIssuedPaneCredential(
        _: AgentStudioIPCIssuedPaneCredential,
        if _: @escaping @Sendable () -> Bool
    ) async throws -> Bool {
        lock.withLock { storedRegistrationCallCount += 1 }
        return true
    }

    func revokeAllPaneCredentials(paneID _: UUID) async throws {}
}

private actor PersistenceFixtureCredentialResolver: AgentStudioIPCCredentialResolving {
    func resolveCredential(
        _: AgentStudioIPCSubjectToken,
        serverRuntimeID _: UUID
    ) async throws -> AgentStudioIPCCredentialResolution {
        throw AgentStudioIPCAuthenticationError(reason: .unauthenticated)
    }
}

private final class PersistenceRegistrationBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var didReachBarrier = false
    private var didRelease = false

    func holdBeforeWrite() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                didReachBarrier = true
                heldContinuation?.resume()
                heldContinuation = nil
                guard !didRelease else { return true }
                releaseContinuation = continuation
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func waitUntilHeld() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard !didReachBarrier else { return true }
                heldContinuation = continuation
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }

    func release() {
        lock.withLock {
            didRelease = true
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }
}

private final class OneShotPersistenceFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true

    func consumeFailure() -> Bool {
        lock.withLock {
            defer { shouldFail = false }
            return shouldFail
        }
    }
}

private struct IPCContinuityPersistenceFixture {
    let rootDirectory: URL
    let localDatabaseURL: URL
    let coreDatabaseURL: URL

    init() throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-ipc-persistence-\(UUIDv7.generate())")
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
            throw PersistenceFixtureError.databasePreparationFailed
        }
        guard case .ready = await datastore.prepareOptionalApplicationLocalSchema() else {
            throw PersistenceFixtureError.databasePreparationFailed
        }
        try await datastore.saveWorkspaceSnapshotBundle(
            WorkspaceSQLiteSaveBundle(
                workspace: .init(id: UUIDv7.generate(), name: "IPC persistence lane tests")
            )
        )
        return IPCContinuityRepository(datastore: datastore)
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}

private enum PersistenceFixtureError: Error {
    case databasePreparationFailed
    case injectedWriteFailure
}
