import Foundation
import GhosttyKit

// MARK: - Surface Health

/// Health state of a managed surface
enum SurfaceHealth: Equatable {
    case healthy
    case unhealthy(reason: UnhealthyReason)
    case processExited(exitCode: Int32?)
    case dead  // Surface pointer is nil/invalid

    enum UnhealthyReason: Equatable {
        case rendererUnhealthy
        case initializationFailed
        case unknown
    }

    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }

    var canRestart: Bool {
        switch self {
        case .healthy: return false
        case .unhealthy, .processExited, .dead: return true
        }
    }
}

// MARK: - Surface State

/// State of a surface in the lifecycle
enum SurfaceState: Equatable {
    case active(paneId: UUID)  // Attached to a visible container
    case hidden                      // Alive but no container
    case pendingUndo(expiresAt: Date) // In undo stack

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}

// MARK: - Surface Metadata

/// Metadata associated with a managed surface
struct SurfaceMetadata: Codable, Equatable {
    var workingDirectory: URL?
    var command: String?
    var title: String
    var worktreeId: UUID?
    var repoId: UUID?
    var paneId: UUID?
    var createdAt: Date
    var lastActiveAt: Date

    init(
        workingDirectory: URL? = nil,
        command: String? = nil,
        title: String = "Terminal",
        worktreeId: UUID? = nil,
        repoId: UUID? = nil,
        paneId: UUID? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.command = command
        self.title = title
        self.worktreeId = worktreeId
        self.repoId = repoId
        self.paneId = paneId
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }
}

// MARK: - Managed Surface

/// A surface managed by SurfaceManager with lifecycle tracking
struct ManagedSurface {
    let id: UUID
    let surface: Ghostty.SurfaceView
    var metadata: SurfaceMetadata
    var state: SurfaceState
    var health: SurfaceHealth

    init(
        id: UUID = UUID(),
        surface: Ghostty.SurfaceView,
        metadata: SurfaceMetadata,
        state: SurfaceState = .hidden
    ) {
        self.id = id
        self.surface = surface
        self.metadata = metadata
        self.state = state
        self.health = .healthy
    }
}

// MARK: - Undo Entry

/// Entry in the undo stack for closed surfaces
struct SurfaceUndoEntry {
    let surface: ManagedSurface
    let previousPaneAttachmentId: UUID?
    let closedAt: Date
    let expiresAt: Date
    var expirationTask: Task<Void, Never>?
}

// MARK: - Surface Checkpoint

/// Serializable checkpoint for surface state persistence
struct SurfaceCheckpoint: Codable {
    let timestamp: Date
    let surfaces: [SurfaceData]

    struct SurfaceData: Codable {
        let id: UUID
        let metadata: SurfaceMetadata
        let wasActive: Bool
        let paneId: UUID?
    }

    init(from surfaces: [ManagedSurface]) {
        self.timestamp = Date()
        self.surfaces = surfaces.map { managed in
            let paneId: UUID?
            if case .active(let cid) = managed.state {
                paneId = cid
            } else {
                paneId = nil
            }
            return SurfaceData(
                id: managed.id,
                metadata: managed.metadata,
                wasActive: managed.state.isActive,
                paneId: paneId
            )
        }
    }
}

// MARK: - Surface Error

/// Errors that can occur during surface operations
enum SurfaceError: Error, LocalizedError {
    case surfaceNotFound
    case surfaceNotInitialized
    case surfaceDied
    case creationFailed(retries: Int)
    case operationFailed(String)
    case ghosttyNotInitialized

    var errorDescription: String? {
        switch self {
        case .surfaceNotFound:
            return "Surface not found"
        case .surfaceNotInitialized:
            return "Surface not initialized"
        case .surfaceDied:
            return "Surface has stopped responding"
        case .creationFailed(let retries):
            return "Failed to create surface after \(retries) attempts"
        case .operationFailed(let message):
            return "Surface operation failed: \(message)"
        case .ghosttyNotInitialized:
            return "Ghostty is not initialized"
        }
    }
}

// MARK: - Detach Reason

/// Reason for detaching a surface from its container
enum SurfaceDetachReason {
    case hide   // User hid the terminal (keep alive)
    case close  // User closed the tab (undo-able)
    case move   // Moving to different container
}

// MARK: - Surface Lifecycle Delegate

/// Delegate for surface lifecycle events
protocol SurfaceLifecycleDelegate: AnyObject {
    /// Called before a surface is created, allowing modification of config
    func surfaceWillCreate(config: inout Ghostty.SurfaceConfiguration, metadata: SurfaceMetadata)

    /// Called after a surface is created
    func surfaceDidCreate(_ surface: ManagedSurface)

    /// Called before a surface is destroyed
    func surfaceWillDestroy(_ surface: ManagedSurface)

    /// Called when app is about to quit, for checkpoint creation
    func surfaceWillPersist(_ surface: ManagedSurface) -> SurfaceCheckpoint.SurfaceData?
}

// MARK: - Surface Health Delegate

/// Delegate for surface health events
protocol SurfaceHealthDelegate: AnyObject {
    /// Called when a surface's health state changes
    func surface(_ surfaceId: UUID, healthChanged: SurfaceHealth)

    /// Called when a surface encounters an error
    func surface(_ surfaceId: UUID, didEncounterError: SurfaceError)
}

// MARK: - Default Implementations

extension SurfaceLifecycleDelegate {
    func surfaceWillCreate(config: inout Ghostty.SurfaceConfiguration, metadata: SurfaceMetadata) {}
    func surfaceDidCreate(_ surface: ManagedSurface) {}
    func surfaceWillDestroy(_ surface: ManagedSurface) {}
    func surfaceWillPersist(_ surface: ManagedSurface) -> SurfaceCheckpoint.SurfaceData? { nil }
}
