import AgentStudioAppIPC
import AgentStudioInfrastructure
import CryptoKit
import Foundation
import Security
import os.log

struct PreparedPaneIPCEnvironment: Sendable {
    let paneID: UUID
    let workspaceID: UUID
    let generationID: UUID
    let environmentVariables: [String: String]
}

struct ActivatedPaneIPCEnvironment: Sendable {
    let preparation: PreparedPaneIPCEnvironment
}

enum PaneIPCIdentityOwnerError: Error, Equatable {
    case paneNotInWorkspace
    case invalidRandomByteCount
    case randomBytesUnavailable
}

actor PaneIPCIdentityOwner {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "PaneIPCIdentityOwner")

    private let repository: IPCContinuityRepository
    private let socketURL: URL
    private let spoolDirectory: URL
    private let cliExecutableURL: URL
    private let inheritedEnvironment: [String: String]
    private let canonicalPaneMembership: @MainActor @Sendable (UUID, UUID) -> Bool
    private let randomBytes: @Sendable () throws -> Data
    private let retireServerLease: @Sendable (UUID, UUID, UUID) -> Void

    init(
        repository: IPCContinuityRepository,
        socketURL: URL,
        spoolDirectory: URL,
        cliExecutableURL: URL,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        canonicalPaneMembership: @escaping @MainActor @Sendable (UUID, UUID) -> Bool,
        randomBytes: @escaping @Sendable () throws -> Data = secureRandomBytes,
        retireServerLease: @escaping @Sendable (UUID, UUID, UUID) -> Void
    ) {
        self.repository = repository
        self.socketURL = socketURL
        self.spoolDirectory = spoolDirectory
        self.cliExecutableURL = cliExecutableURL
        self.inheritedEnvironment = inheritedEnvironment
        self.canonicalPaneMembership = canonicalPaneMembership
        self.randomBytes = randomBytes
        self.retireServerLease = retireServerLease
    }

    func prepareEnvironment(paneID: UUID, workspaceID: UUID) async throws -> PreparedPaneIPCEnvironment {
        guard await canonicalPaneMembership(paneID, workspaceID) else {
            throw PaneIPCIdentityOwnerError.paneNotInWorkspace
        }
        let credentialBytes = try randomBytes()
        guard credentialBytes.count == 32 else {
            throw PaneIPCIdentityOwnerError.invalidRandomByteCount
        }
        let rawToken = AgentStudioIPCSubjectToken(rawValue: credentialBytes.base64EncodedString())
        let verifier = Data(SHA256.hash(data: Data(rawToken.rawValue.utf8)))
        let generationID = UUIDv7.generate()
        try await repository.persistPreparedPaneCredential(
            paneID: paneID,
            workspaceID: workspaceID,
            generation: generationID,
            verifier: verifier
        )
        return .init(
            paneID: paneID,
            workspaceID: workspaceID,
            generationID: generationID,
            environmentVariables: makeEnvironment(
                paneID: paneID,
                workspaceID: workspaceID,
                generationID: generationID,
                rawToken: rawToken
            )
        )
    }

    func activateForMount(_ preparation: PreparedPaneIPCEnvironment) async throws -> ActivatedPaneIPCEnvironment {
        try await repository.activatePreparedPaneCredential(
            paneID: preparation.paneID,
            generation: preparation.generationID
        )
        return .init(preparation: preparation)
    }

    func cancelPrepared(_ preparation: PreparedPaneIPCEnvironment) async {
        do {
            try await repository.revokePreparedPaneCredential(
                paneID: preparation.paneID,
                generation: preparation.generationID
            )
        } catch {
            Self.logger.warning("Prepared pane IPC credential cleanup failed")
        }
    }

    func rollbackFailedMount(_ activation: ActivatedPaneIPCEnvironment) async {
        await retireActiveCredential(activation)
    }

    func retire(_ activation: ActivatedPaneIPCEnvironment) async throws {
        let preparation = activation.preparation
        retireServerLease(preparation.paneID, preparation.workspaceID, preparation.generationID)
        try await repository.revokeActivePaneCredential(
            paneID: preparation.paneID,
            generation: preparation.generationID
        )
    }

    private func retireActiveCredential(_ activation: ActivatedPaneIPCEnvironment) async {
        let preparation = activation.preparation
        retireServerLease(preparation.paneID, preparation.workspaceID, preparation.generationID)
        do {
            try await repository.revokeActivePaneCredential(
                paneID: preparation.paneID,
                generation: preparation.generationID
            )
        } catch {
            Self.logger.warning("Active pane IPC credential cleanup failed")
        }
    }

    private func makeEnvironment(
        paneID: UUID,
        workspaceID: UUID,
        generationID: UUID,
        rawToken: AgentStudioIPCSubjectToken
    ) -> [String: String] {
        var environmentVariables = inheritedEnvironment
        let executableDirectory = cliExecutableURL.deletingLastPathComponent().path
        if let inheritedPath = inheritedEnvironment["PATH"], !inheritedPath.isEmpty {
            environmentVariables["PATH"] = "\(executableDirectory):\(inheritedPath)"
        } else {
            environmentVariables["PATH"] = executableDirectory
        }
        environmentVariables["AGENTSTUDIO_PANE_ID"] = paneID.uuidString
        environmentVariables["AGENTSTUDIO_WORKSPACE_ID"] = workspaceID.uuidString
        environmentVariables["AGENTSTUDIO_IPC_SOCKET"] = socketURL.path
        environmentVariables["AGENTSTUDIO_PANE_TOKEN"] = rawToken.rawValue
        environmentVariables["AGENTSTUDIO_IPC_GENERATION_ID"] = generationID.uuidString
        environmentVariables["AGENTSTUDIO_IPC_SPOOL_DIR"] = spoolDirectory.path
        environmentVariables["AGENTSTUDIO_CLI"] = cliExecutableURL.path
        return environmentVariables
    }
}

private func secureRandomBytes() throws -> Data {
    var bytes = Data(count: 32)
    let result = bytes.withUnsafeMutableBytes { buffer in
        SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
    }
    guard result == errSecSuccess else {
        throw PaneIPCIdentityOwnerError.randomBytesUnavailable
    }
    return bytes
}
