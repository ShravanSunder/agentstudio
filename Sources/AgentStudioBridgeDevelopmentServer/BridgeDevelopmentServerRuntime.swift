import AgentStudioBridge
import ServiceLifecycle

actor BridgeDevelopmentServerRuntime {
    private let coreComposition: BridgeDevelopmentServerCoreComposition
    private let host: BridgeDevelopmentProductHost
    private let observation: BridgeDevelopmentSeededWorktreeObservation
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
        try await observation.start()
    }

    func shutdown() async throws {
        guard !isShutdown else { return }
        isShutdown = true
        await observation.stopFactAdmissionAndDrainRouting()
        await host.shutdown()
        await observation.shutdownSources()
        try await coreComposition.shutdown()
    }
}

struct BridgeDevelopmentServerRuntimeShutdownService: Service {
    let runtime: BridgeDevelopmentServerRuntime

    func run() async throws {
        try? await gracefulShutdown()
        try await runtime.shutdown()
    }
}
