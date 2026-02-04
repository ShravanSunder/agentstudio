// SessionStatus.swift
// AgentStudio
//
// State machine definition for Zellij session lifecycle.

import Foundation

// MARK: - Session Status

/// State of a session in the registry.
enum SessionStatus: MachineState, Codable, Equatable, Sendable {
    case unknown                            // Loaded from checkpoint, not verified
    case verifying(phase: VerifyPhase)      // Verification in progress
    case alive                              // Confirmed running
    case dead                               // Socket stale, needs resurrection
    case missing                            // No socket, needs creation
    case recovering(action: RecoveryAction) // Recovery in progress
    case orphan                             // Exists in Zellij but not in checkpoint
    case failed(reason: String)             // Unrecoverable error
    case disabled                           // Backend doesn't support sessions

    // MARK: - Nested Types

    enum VerifyPhase: String, Codable, Equatable, Sendable {
        case checkingSocket     // Fast filesystem check
        case tryingAttach       // Attempting IPC connection
    }

    enum RecoveryAction: String, Codable, Equatable, Sendable {
        case resurrecting       // Reviving dead session
        case creating           // Creating new session
    }

    // MARK: - MachineState Protocol

    typealias Event = SessionEvent
    typealias Effect = SessionEffect

    func handle(_ event: SessionEvent) -> Transition<SessionStatus, SessionEffect>? {
        switch (self, event) {

        // ═══════════════════════════════════════════════════════════════
        // UNKNOWN → Start verification
        // ═══════════════════════════════════════════════════════════════
        case (.unknown, .startVerification(let sessionId)):
            return .to(.verifying(phase: .checkingSocket))
                .emitting(.checkSocket(sessionId: sessionId))

        case (.unknown, .disable):
            return .to(.disabled)

        case (.unknown, .markOrphan):
            return .to(.orphan)

        // ═══════════════════════════════════════════════════════════════
        // VERIFYING (checkingSocket) → Socket check results
        // ═══════════════════════════════════════════════════════════════
        case (.verifying(phase: .checkingSocket), .socketFound(let sessionId)):
            return .to(.verifying(phase: .tryingAttach))
                .emitting(.tryAttach(sessionId: sessionId))

        case (.verifying(phase: .checkingSocket), .socketNotFound):
            return .to(.missing)
                .emitting(.log(level: .info, message: "Session socket not found, will create"))

        // ═══════════════════════════════════════════════════════════════
        // VERIFYING (tryingAttach) → Attach results
        // ═══════════════════════════════════════════════════════════════
        case (.verifying(phase: .tryingAttach), .attachSucceeded(let sessionId)):
            return .to(.alive)
                .emitting(
                    .notifyReady(sessionId: sessionId),
                    .scheduleHealthCheck(sessionId: sessionId, delay: 30)
                )

        case (.verifying(phase: .tryingAttach), .attachFailed(let reason)):
            return .to(.dead)
                .emitting(.log(level: .warning, message: "Socket stale: \(reason)"))

        // ═══════════════════════════════════════════════════════════════
        // ALIVE → Runtime events
        // ═══════════════════════════════════════════════════════════════
        case (.alive, .healthCheckPassed(let sessionId)):
            return .to(.alive)
                .emitting(.scheduleHealthCheck(sessionId: sessionId, delay: 30))

        case (.alive, .healthCheckFailed):
            return .to(.dead)
                .emitting(.log(level: .warning, message: "Health check failed"))

        case (.alive, .sessionKilled):
            return .to(.missing)
                .emitting(.log(level: .info, message: "Session killed"))

        // ═══════════════════════════════════════════════════════════════
        // DEAD → Start recovery (resurrection)
        // ═══════════════════════════════════════════════════════════════
        case (.dead, .startRecovery(let sessionId, let projectId)):
            return .to(.recovering(action: .resurrecting))
                .emitting(.resurrect(sessionId: sessionId, projectId: projectId))

        // ═══════════════════════════════════════════════════════════════
        // MISSING → Start recovery (creation)
        // ═══════════════════════════════════════════════════════════════
        case (.missing, .startRecovery(let sessionId, let projectId)):
            return .to(.recovering(action: .creating))
                .emitting(.createSession(sessionId: sessionId, projectId: projectId))

        // ═══════════════════════════════════════════════════════════════
        // RECOVERING → Results
        // ═══════════════════════════════════════════════════════════════
        case (.recovering, .recoverySucceeded(let sessionId)):
            return .to(.alive)
                .emitting(
                    .notifyReady(sessionId: sessionId),
                    .scheduleHealthCheck(sessionId: sessionId, delay: 30)
                )

        case (.recovering(action: .resurrecting), .recoveryFailed(let sessionId, let projectId, _)):
            // Resurrection failed, fall back to creation
            return .to(.recovering(action: .creating))
                .emitting(
                    .log(level: .warning, message: "Resurrection failed, trying creation"),
                    .createSession(sessionId: sessionId, projectId: projectId)
                )

        case (.recovering(action: .creating), .recoveryFailed(_, _, let reason)):
            return .to(.failed(reason: reason))
                .emitting(
                    .notifyFailed(reason: reason),
                    .log(level: .error, message: "Session creation failed: \(reason)")
                )

        // ═══════════════════════════════════════════════════════════════
        // ORPHAN → Can be adopted or killed
        // ═══════════════════════════════════════════════════════════════
        case (.orphan, .adopt(let sessionId)):
            return .to(.verifying(phase: .tryingAttach))
                .emitting(.tryAttach(sessionId: sessionId))

        case (.orphan, .sessionKilled):
            return .to(.missing)

        // ═══════════════════════════════════════════════════════════════
        // FAILED → Can retry
        // ═══════════════════════════════════════════════════════════════
        case (.failed, .startRecovery(let sessionId, let projectId)):
            return .to(.recovering(action: .creating))
                .emitting(.createSession(sessionId: sessionId, projectId: projectId))

        // ═══════════════════════════════════════════════════════════════
        // DISABLED → No transitions (terminal state for non-Zellij backends)
        // ═══════════════════════════════════════════════════════════════

        // ═══════════════════════════════════════════════════════════════
        // Default → No valid transition
        // ═══════════════════════════════════════════════════════════════
        default:
            return nil
        }
    }
}

// MARK: - Session Events

/// Events that can be sent to a session state machine.
enum SessionEvent: Sendable, Equatable {
    // Verification events
    case startVerification(sessionId: String)
    case socketFound(sessionId: String)
    case socketNotFound
    case attachSucceeded(sessionId: String)
    case attachFailed(reason: String)

    // Recovery events
    case startRecovery(sessionId: String, projectId: UUID)
    case recoverySucceeded(sessionId: String)
    case recoveryFailed(sessionId: String, projectId: UUID, reason: String)

    // Runtime events
    case healthCheckPassed(sessionId: String)
    case healthCheckFailed
    case sessionKilled

    // Special events
    case markOrphan
    case adopt(sessionId: String)
    case disable
}

// MARK: - Session Effects

/// Side effects produced by session state transitions.
enum SessionEffect: Sendable, Equatable {
    case checkSocket(sessionId: String)
    case tryAttach(sessionId: String)
    case resurrect(sessionId: String, projectId: UUID)
    case createSession(sessionId: String, projectId: UUID)
    case notifyReady(sessionId: String)
    case notifyFailed(reason: String)
    case scheduleHealthCheck(sessionId: String, delay: TimeInterval)
    case log(level: LogLevel, message: String)

    enum LogLevel: String, Sendable, Equatable {
        case debug
        case info
        case warning
        case error
    }
}

// MARK: - Convenience

extension SessionStatus {
    /// Whether the session is ready for use.
    var isReady: Bool {
        self == .alive
    }

    /// Whether the session needs recovery action.
    var needsRecovery: Bool {
        switch self {
        case .dead, .missing, .failed:
            return true
        default:
            return false
        }
    }

    /// Whether the session is in a terminal state (no automatic recovery possible).
    var isTerminal: Bool {
        switch self {
        case .disabled, .orphan:
            return true
        case .failed:
            return true // Can retry manually
        default:
            return false
        }
    }

    /// Human-readable description of the status.
    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .verifying(let phase):
            switch phase {
            case .checkingSocket:
                return "Checking..."
            case .tryingAttach:
                return "Connecting..."
            }
        case .alive:
            return "Connected"
        case .dead:
            return "Disconnected"
        case .missing:
            return "Not Found"
        case .recovering(let action):
            switch action {
            case .resurrecting:
                return "Restoring..."
            case .creating:
                return "Creating..."
            }
        case .orphan:
            return "Orphan"
        case .failed(let reason):
            return "Failed: \(reason)"
        case .disabled:
            return "Disabled"
        }
    }
}
