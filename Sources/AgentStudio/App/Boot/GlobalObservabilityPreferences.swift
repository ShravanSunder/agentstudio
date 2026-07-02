import Foundation

struct GlobalObservabilityPreferences: Equatable, Sendable {
    let enabled: Bool
    let traceTags: String?
    let traceBackend: String?
    let traceFlush: String?
    let otlpEndpoint: String?
}
