struct BridgeTelemetryRuntimePolicy: Equatable, Sendable {
    let isDebugBuild: Bool

    static var live: Self {
        #if DEBUG
            Self(isDebugBuild: true)
        #else
            Self(isDebugBuild: false)
        #endif
    }

    var allowsTelemetry: Bool {
        isDebugBuild
    }
}
