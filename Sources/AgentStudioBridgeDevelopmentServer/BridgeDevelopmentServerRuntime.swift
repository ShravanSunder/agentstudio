import AgentStudioBridge
import AgentStudioCore
import ServiceLifecycle

actor BridgeDevelopmentServerRuntime {
    private let coreComposition: BridgeDevelopmentServerCoreComposition
    private let host: BridgeDevelopmentProductHost
    private let observation: BridgeDevelopmentSeededWorktreeObservation
    private var detectedRuntimeTerminal = false
    private var isReady = false
    private var isShutdown = false

    init(
        coreComposition: BridgeDevelopmentServerCoreComposition,
        host: BridgeDevelopmentProductHost,
        observation: BridgeDevelopmentSeededWorktreeObservation
    ) {
        self.coreComposition = coreComposition
        self.host = host
        self.observation = observation
    }

    func start() async throws {
        try await observation.start { [weak self] terminal in
            await self?.handleDetectedRuntimeTerminal(terminal)
        }
        guard !detectedRuntimeTerminal, !isShutdown else { return }
        isReady = true
    }

    func healthIsReady() -> Bool {
        isReady && !detectedRuntimeTerminal && !isShutdown
    }

    func shutdown() async throws {
        guard !isShutdown else { return }
        isShutdown = true
        isReady = false
        await observation.stopFactAdmissionAndDrainRouting()
        await host.shutdown()
        await observation.shutdownSources()
        try await coreComposition.shutdown()
    }

    private func handleDetectedRuntimeTerminal(
        _: FSEventStreamRuntimeTerminal
    ) async {
        guard !detectedRuntimeTerminal, !isShutdown else { return }
        detectedRuntimeTerminal = true
        isReady = false
        await host.handleObservedWorktreeTerminal()
    }
}

struct BridgeDevelopmentServerRuntimeShutdownService: Service {
    let runtime: BridgeDevelopmentServerRuntime

    func run() async throws {
        try? await gracefulShutdown()
        try await runtime.shutdown()
    }
}
