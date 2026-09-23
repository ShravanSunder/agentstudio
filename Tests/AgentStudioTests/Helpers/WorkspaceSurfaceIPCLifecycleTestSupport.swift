import Foundation

@testable import AgentStudio

extension WorkspaceSurfaceIPCLifecycle {
    static let testUnavailable = Self(
        environment: { _, _ in [:] },
        invalidatePaneIDs: { _ in },
        finalRevokePaneIDs: { _ in }
    )
}
