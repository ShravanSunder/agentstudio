import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

#if canImport(Darwin)
    import Darwin
#endif

protocol PaneAgentBootstrapProviding: AnyObject {
    func makePaneBootstrap(
        boundPaneId: String,
        boundWorkspaceId: UUID?,
        approvalAuthority: IPCApprovalAuthority
    ) throws -> AgentStudioIPCPaneBootstrap

    func cancelPaneBootstrap(_ bootstrap: AgentStudioIPCPaneBootstrap)
}

final class AgentStudioPaneAgentBootstrapProvider: PaneAgentBootstrapProviding {
    private let server: AgentStudioAppIPCServer

    init(server: AgentStudioAppIPCServer) {
        self.server = server
    }

    func makePaneBootstrap(
        boundPaneId: String,
        boundWorkspaceId: UUID?,
        approvalAuthority: IPCApprovalAuthority
    ) throws -> AgentStudioIPCPaneBootstrap {
        try server.makePaneBootstrap(
            boundPaneId: boundPaneId,
            boundWorkspaceId: boundWorkspaceId,
            approvalAuthority: approvalAuthority
        )
    }

    func cancelPaneBootstrap(_ bootstrap: AgentStudioIPCPaneBootstrap) {
        server.cancelPaneBootstrap(bootstrap)
    }
}

struct PaneAgentProcessHandle: Equatable, Sendable {
    let processIdentifier: Int32
}

struct PaneAgentSpawnFileAction: Equatable, Sendable {
    let sourceFileDescriptor: Int32
    let targetFileDescriptor: Int32
}

struct PaneAgentSpawnRequest: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let fileActions: [PaneAgentSpawnFileAction]
    let closeAllUnmappedFileDescriptors: Bool
}

protocol PaneAgentProcessSpawning: Sendable {
    func spawn(_ request: PaneAgentSpawnRequest) throws -> PaneAgentProcessHandle
}

enum PaneAgentLaunchError: Error, Equatable {
    case unsupportedPlatform
    case pipeFailed(errnoCode: Int32)
    case spawnAttributeFailed(errnoCode: Int32)
    case spawnFileActionFailed(errnoCode: Int32)
    case spawnFailed(errnoCode: Int32)
}

final class PaneAgentLaunchOwner {
    static let childBootstrapFileDescriptor: Int32 = 3

    private let bootstrapProvider: PaneAgentBootstrapProviding
    private let processSpawner: any PaneAgentProcessSpawning
    private let helperExecutableURL: URL

    init(
        bootstrapProvider: PaneAgentBootstrapProviding,
        processSpawner: any PaneAgentProcessSpawning = PosixPaneAgentProcessSpawner(),
        helperExecutableURL: URL
    ) {
        self.bootstrapProvider = bootstrapProvider
        self.processSpawner = processSpawner
        self.helperExecutableURL = helperExecutableURL
    }

    func launchPaneAgent(
        boundPaneId: UUID,
        boundWorkspaceId: UUID?,
        approvalAuthority: IPCApprovalAuthority = .noApprovalAuthority
    ) throws -> PaneAgentProcessHandle {
        let bootstrap = try bootstrapProvider.makePaneBootstrap(
            boundPaneId: boundPaneId.uuidString,
            boundWorkspaceId: boundWorkspaceId,
            approvalAuthority: approvalAuthority
        )
        do {
            var environment = bootstrap.descriptor.environment.variables
            environment["AGENTSTUDIO_IPC_BOOTSTRAP_FD"] = String(Self.childBootstrapFileDescriptor)
            let fileActions = try makeSpawnFileActions(
                tokenReadFileDescriptor: bootstrap.descriptor.tokenReadFileDescriptor
            )
            defer {
                fileActions.closeStagedFileDescriptors()
            }
            let request = PaneAgentSpawnRequest(
                executableURL: helperExecutableURL,
                arguments: [],
                environment: environment,
                fileActions: fileActions.actions,
                closeAllUnmappedFileDescriptors: true
            )
            let handle = try processSpawner.spawn(request)
            bootstrap.closeTokenReadFileDescriptor()
            return handle
        } catch {
            bootstrapProvider.cancelPaneBootstrap(bootstrap)
            throw error
        }
    }

    private func makeSpawnFileActions(tokenReadFileDescriptor: Int32) throws -> PaneAgentPreparedSpawnFileActions {
        #if canImport(Darwin)
            if tokenReadFileDescriptor != Self.childBootstrapFileDescriptor {
                return PaneAgentPreparedSpawnFileActions(
                    actions: [
                        PaneAgentSpawnFileAction(
                            sourceFileDescriptor: tokenReadFileDescriptor,
                            targetFileDescriptor: Self.childBootstrapFileDescriptor
                        )
                    ],
                    stagedFileDescriptors: []
                )
            }

            let stagedFileDescriptor = fcntl(
                tokenReadFileDescriptor,
                F_DUPFD_CLOEXEC,
                Self.childBootstrapFileDescriptor + 1
            )
            guard stagedFileDescriptor >= 0 else {
                throw PaneAgentLaunchError.spawnFileActionFailed(errnoCode: errno)
            }
            return PaneAgentPreparedSpawnFileActions(
                actions: [
                    PaneAgentSpawnFileAction(
                        sourceFileDescriptor: stagedFileDescriptor,
                        targetFileDescriptor: Self.childBootstrapFileDescriptor
                    )
                ],
                stagedFileDescriptors: [stagedFileDescriptor]
            )
        #else
            throw PaneAgentLaunchError.unsupportedPlatform
        #endif
    }
}

private struct PaneAgentPreparedSpawnFileActions {
    let actions: [PaneAgentSpawnFileAction]
    let stagedFileDescriptors: [Int32]

    func closeStagedFileDescriptors() {
        #if canImport(Darwin)
            for fileDescriptor in stagedFileDescriptors {
                _ = Darwin.close(fileDescriptor)
            }
        #endif
    }
}

struct PosixPaneAgentProcessSpawner: PaneAgentProcessSpawning {
    func spawn(_ request: PaneAgentSpawnRequest) throws -> PaneAgentProcessHandle {
        #if canImport(Darwin)
            var fileActions: posix_spawn_file_actions_t?
            var attr: posix_spawnattr_t?
            guard posix_spawn_file_actions_init(&fileActions) == 0 else {
                throw PaneAgentLaunchError.spawnFileActionFailed(errnoCode: errno)
            }
            defer {
                posix_spawn_file_actions_destroy(&fileActions)
            }
            guard posix_spawnattr_init(&attr) == 0 else {
                throw PaneAgentLaunchError.spawnAttributeFailed(errnoCode: errno)
            }
            defer {
                posix_spawnattr_destroy(&attr)
            }

            if request.closeAllUnmappedFileDescriptors {
                let flags = Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
                let attrResult = posix_spawnattr_setflags(&attr, flags)
                guard attrResult == 0 else {
                    throw PaneAgentLaunchError.spawnAttributeFailed(errnoCode: attrResult)
                }
            }

            for action in request.fileActions {
                let actionResult = posix_spawn_file_actions_adddup2(
                    &fileActions,
                    action.sourceFileDescriptor,
                    action.targetFileDescriptor
                )
                guard actionResult == 0 else {
                    throw PaneAgentLaunchError.spawnFileActionFailed(errnoCode: actionResult)
                }
            }

            let argvValues = [request.executableURL.path] + request.arguments
            let envValues = request.environment
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
            var processIdentifier = pid_t()
            let spawnResult = try withCStringArray(argvValues) { argv in
                try withCStringArray(envValues) { env in
                    posix_spawn(
                        &processIdentifier,
                        request.executableURL.path,
                        &fileActions,
                        &attr,
                        argv,
                        env
                    )
                }
            }
            guard spawnResult == 0 else {
                throw PaneAgentLaunchError.spawnFailed(errnoCode: spawnResult)
            }
            return PaneAgentProcessHandle(processIdentifier: processIdentifier)
        #else
            throw PaneAgentLaunchError.unsupportedPlatform
        #endif
    }

    private func withCStringArray<Result>(
        _ values: [String],
        _ body: ([UnsafeMutablePointer<CChar>?]) throws -> Result
    ) throws -> Result {
        let cStrings = values.map { strdup($0) }
        defer {
            for cString in cStrings {
                free(cString)
            }
        }
        return try body(cStrings + [nil])
    }
}
