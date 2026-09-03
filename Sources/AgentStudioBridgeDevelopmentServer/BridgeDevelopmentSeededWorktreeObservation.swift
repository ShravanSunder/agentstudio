import AgentStudioBridge
import AgentStudioCore
import Foundation

enum BridgeDevelopmentSeededWorktreeObservationError: Error, Equatable {
    case registrationUnavailable(FSEventStreamRegistrationUnavailableReason)
    case runtimeTerminal(FSEventStreamRuntimeTerminal)
}

actor BridgeDevelopmentSeededWorktreeObservation {
    typealias InvalidationSink = @Sendable (BridgePaneWorktreeProductInvalidation) async -> Void
    typealias RuntimeTerminalSink = @Sendable (FSEventStreamRuntimeTerminal) async -> Void

    struct Dependencies {
        let bus: EventBus<RuntimeEnvelope>
        let filesystemActor: FilesystemActor
        let gitWorkingDirectoryProjector: GitWorkingDirectoryProjector

        static func production() -> Self {
            let bus = EventBus<RuntimeEnvelope>(name: "BridgeDevelopmentSeededWorktree")
            return Self(
                bus: bus,
                filesystemActor: FilesystemActor(bus: bus),
                gitWorkingDirectoryProjector: .production(bus: bus)
            )
        }

        init(
            bus: EventBus<RuntimeEnvelope>,
            fseventStreamClient: any FSEventStreamClient,
            gitWorkingTreeProvider: any GitWorkingTreeStatusProvider,
            filesystemDebounceWindow: Duration,
            filesystemMaximumFlushLatency: Duration,
            gitCoalescingWindow: Duration
        ) {
            self.bus = bus
            self.filesystemActor = FilesystemActor(
                bus: bus,
                fseventStreamClient: fseventStreamClient,
                debounceWindow: filesystemDebounceWindow,
                maxFlushLatency: filesystemMaximumFlushLatency
            )
            self.gitWorkingDirectoryProjector = GitWorkingDirectoryProjector(
                bus: bus,
                gitWorkingTreeProvider: gitWorkingTreeProvider,
                coalescingWindow: gitCoalescingWindow,
                pathExistenceProbe: GitWorkingDirectoryProjector.liveRootPathProbe
            )
        }

        private init(
            bus: EventBus<RuntimeEnvelope>,
            filesystemActor: FilesystemActor,
            gitWorkingDirectoryProjector: GitWorkingDirectoryProjector
        ) {
            self.bus = bus
            self.filesystemActor = filesystemActor
            self.gitWorkingDirectoryProjector = gitWorkingDirectoryProjector
        }
    }

    private let dependencies: Dependencies
    private let invalidationSink: InvalidationSink
    private let source: BridgeDevelopmentProductSource
    private let canonicalWorktreeRoot: URL
    private var acceptsRuntimeFacts = false
    private var didShutdownSources = false
    private var didStopFactAdmission = false
    private var detectedRuntimeTerminal: FSEventStreamRuntimeTerminal?
    private var isShutdown = false
    private var isStarted = false
    private var routingTask: Task<Void, Never>?
    private var terminalTask: Task<Void, Never>?

    init(
        source: BridgeDevelopmentProductSource,
        dependencies: Dependencies = .production(),
        invalidationSink: @escaping InvalidationSink
    ) {
        self.source = source
        self.dependencies = dependencies
        self.invalidationSink = invalidationSink
        self.canonicalWorktreeRoot = source.worktreeRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    func start(
        runtimeTerminalSink: @escaping RuntimeTerminalSink = { _ in }
    ) async throws {
        guard !isShutdown, !didStopFactAdmission, !isStarted else { return }
        let stream = await dependencies.bus.subscribe(
            policy: .criticalUnbounded,
            subscriberName: "BridgeDevelopmentSeededWorktreeObservation",
            factInterest: .matching([.worktreeFilesystem, .worktreeGitWorkingDirectory])
        )
        acceptsRuntimeFacts = true
        routingTask = Task { [weak self] in
            for await envelope in stream {
                guard !Task.isCancelled else { break }
                await self?.route(envelope)
            }
        }
        let runtimeTerminals = await dependencies.filesystemActor.runtimeTerminals()
        terminalTask = Task { [weak self] in
            for await terminal in runtimeTerminals {
                guard !Task.isCancelled else { break }
                await self?.handleDetectedRuntimeTerminal(
                    terminal,
                    runtimeTerminalSink: runtimeTerminalSink
                )
                break
            }
        }

        await dependencies.gitWorkingDirectoryProjector.start()
        await dependencies.filesystemActor.start()
        let registrationOutcome = await dependencies.filesystemActor.registerForObservation(
            worktreeId: source.worktreeID,
            repoId: source.repoID,
            rootPath: canonicalWorktreeRoot
        )
        guard registrationOutcome == .observing else {
            await stopAfterFailedStart()
            guard case .unavailable(let reason) = registrationOutcome else { return }
            throw BridgeDevelopmentSeededWorktreeObservationError.registrationUnavailable(reason)
        }
        if let detectedRuntimeTerminal {
            throw BridgeDevelopmentSeededWorktreeObservationError.runtimeTerminal(
                detectedRuntimeTerminal
            )
        }
        isStarted = true

        await dependencies.filesystemActor.setActivity(
            worktreeId: source.worktreeID,
            isActiveInApp: true
        )
        await dependencies.filesystemActor.setActivePaneWorktree(
            worktreeId: source.worktreeID
        )
        await dependencies.gitWorkingDirectoryProjector.setActivity(
            worktreeId: source.worktreeID,
            isActiveInApp: true
        )
        await dependencies.gitWorkingDirectoryProjector.setActivePaneWorktree(
            worktreeId: source.worktreeID
        )
        if let detectedRuntimeTerminal {
            throw BridgeDevelopmentSeededWorktreeObservationError.runtimeTerminal(
                detectedRuntimeTerminal
            )
        }
    }

    func shutdown() async {
        await stopFactAdmissionAndDrainRouting()
        await shutdownSources()
    }

    func stopFactAdmissionAndDrainRouting() async {
        await stopFactAdmissionAndDrainRouting(drainTerminalTask: true)
    }

    private func stopFactAdmissionAndDrainRouting(
        drainTerminalTask: Bool
    ) async {
        guard !didStopFactAdmission else {
            if drainTerminalTask {
                await cancelAndDrainTerminalTask()
            }
            return
        }
        didStopFactAdmission = true
        acceptsRuntimeFacts = false
        if isStarted {
            await dependencies.filesystemActor.setActivePaneWorktree(worktreeId: nil)
            await dependencies.filesystemActor.setActivity(
                worktreeId: source.worktreeID,
                isActiveInApp: false
            )
            await dependencies.gitWorkingDirectoryProjector.setActivePaneWorktree(
                worktreeId: nil
            )
            await dependencies.gitWorkingDirectoryProjector.setActivity(
                worktreeId: source.worktreeID,
                isActiveInApp: false
            )
            await dependencies.filesystemActor.unregister(worktreeId: source.worktreeID)
        }
        await cancelAndDrainRoutingTask()
        if drainTerminalTask {
            await cancelAndDrainTerminalTask()
        }
        isStarted = false
    }

    func shutdownSources() async {
        guard !didShutdownSources else { return }
        didShutdownSources = true
        await dependencies.filesystemActor.shutdown()
        await dependencies.gitWorkingDirectoryProjector.shutdown()
        isShutdown = true
    }

    private func stopAfterFailedStart() async {
        await stopFactAdmissionAndDrainRouting()
        await shutdownSources()
    }

    private func cancelAndDrainRoutingTask() async {
        let task = routingTask
        routingTask = nil
        task?.cancel()
        await task?.value
    }

    private func cancelAndDrainTerminalTask() async {
        let task = terminalTask
        terminalTask = nil
        task?.cancel()
        await task?.value
    }

    private func handleDetectedRuntimeTerminal(
        _ terminal: FSEventStreamRuntimeTerminal,
        runtimeTerminalSink: RuntimeTerminalSink
    ) async {
        detectedRuntimeTerminal = terminal
        await stopFactAdmissionAndDrainRouting(drainTerminalTask: false)
        await runtimeTerminalSink(terminal)
    }

    private func route(_ envelope: RuntimeEnvelope) async {
        guard acceptsRuntimeFacts,
            case .worktree(let worktreeEnvelope) = envelope,
            worktreeEnvelope.repoId == source.repoID,
            worktreeEnvelope.worktreeId == source.worktreeID
        else { return }

        switch worktreeEnvelope.event {
        case .filesystem(.filesChanged(let changeset)):
            guard changeset.repoId == source.repoID,
                changeset.worktreeId == source.worktreeID,
                hasExactRoot(changeset.rootPath)
            else { return }
            await invalidationSink(.filesChanged(changeset))
        case .gitWorkingDirectory(.snapshotChanged(let snapshot)):
            guard snapshot.repoId == source.repoID,
                snapshot.worktreeId == source.worktreeID,
                hasExactRoot(snapshot.rootPath)
            else { return }
            await invalidationSink(
                .statusChanged(
                    GitWorkingTreeStatus(
                        summary: snapshot.summary,
                        branch: snapshot.branch,
                        origin: nil
                    )
                )
            )
        case .filesystem, .gitWorkingDirectory, .forge, .security:
            return
        }
    }

    private func hasExactRoot(_ candidate: URL) -> Bool {
        candidate.standardizedFileURL.resolvingSymlinksInPath() == canonicalWorktreeRoot
    }
}
