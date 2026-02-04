// TabStatus.swift
// AgentStudio
//
// State machine definition for tab lifecycle within a session.

import Foundation

// MARK: - Tab Status

/// State of a tab within a Zellij session.
enum TabStatus: MachineState, Codable, Equatable, Sendable {
    case unknown                    // Loaded from checkpoint, not verified
    case verifying                  // Checking if tab exists
    case verified                   // Confirmed exists in Zellij
    case missing                    // Not found, needs creation
    case creating                   // Creation in progress
    case active                     // Currently attached/in use
    case failed(reason: String)     // Creation failed
    case unsupported                // Backend doesn't support tabs

    // MARK: - MachineState Protocol

    typealias Event = TabEvent
    typealias Effect = TabEffect

    func handle(_ event: TabEvent) -> Transition<TabStatus, TabEffect>? {
        switch (self, event) {

        // ═══════════════════════════════════════════════════════════════
        // UNKNOWN → Start verification or disable
        // ═══════════════════════════════════════════════════════════════
        case (.unknown, .startVerification(let sessionId)):
            return .to(.verifying)
                .emitting(.queryTabExists(sessionId: sessionId))

        case (.unknown, .disable):
            return .to(.unsupported)

        case (.unknown, .found(let tabId)):
            // Direct transition if we already know it exists
            return .to(.verified)
                .emitting(.updateTabId(tabId))

        // ═══════════════════════════════════════════════════════════════
        // VERIFYING → Verification results
        // ═══════════════════════════════════════════════════════════════
        case (.verifying, .found(let tabId)):
            return .to(.verified)
                .emitting(.updateTabId(tabId))

        case (.verifying, .notFound):
            return .to(.missing)

        // ═══════════════════════════════════════════════════════════════
        // MISSING → Create tab
        // ═══════════════════════════════════════════════════════════════
        case (.missing, .startCreation(let sessionId, let worktreeId)):
            return .to(.creating)
                .emitting(.createTab(sessionId: sessionId, worktreeId: worktreeId))

        // ═══════════════════════════════════════════════════════════════
        // CREATING → Creation results
        // ═══════════════════════════════════════════════════════════════
        case (.creating, .createSucceeded(let tabId)):
            return .to(.verified)
                .emitting(
                    .updateTabId(tabId),
                    .notifyReady(tabId: tabId)
                )

        case (.creating, .createFailed(let reason)):
            return .to(.failed(reason: reason))
                .emitting(.notifyFailed(reason: reason))

        // ═══════════════════════════════════════════════════════════════
        // VERIFIED → Activation / deactivation
        // ═══════════════════════════════════════════════════════════════
        case (.verified, .activate):
            return .to(.active)

        case (.verified, .closed):
            return .to(.missing)

        // ═══════════════════════════════════════════════════════════════
        // ACTIVE → Deactivation / closure
        // ═══════════════════════════════════════════════════════════════
        case (.active, .deactivate):
            return .to(.verified)

        case (.active, .closed):
            return .to(.missing)

        // ═══════════════════════════════════════════════════════════════
        // FAILED → Retry creation
        // ═══════════════════════════════════════════════════════════════
        case (.failed, .startCreation(let sessionId, let worktreeId)):
            return .to(.creating)
                .emitting(.createTab(sessionId: sessionId, worktreeId: worktreeId))

        // ═══════════════════════════════════════════════════════════════
        // UNSUPPORTED → No transitions (terminal)
        // ═══════════════════════════════════════════════════════════════

        // ═══════════════════════════════════════════════════════════════
        // Default → No valid transition
        // ═══════════════════════════════════════════════════════════════
        default:
            return nil
        }
    }
}

// MARK: - Tab Events

/// Events that can be sent to a tab state machine.
enum TabEvent: Sendable, Equatable {
    // Verification events
    case startVerification(sessionId: String)
    case found(tabId: Int)
    case notFound

    // Creation events
    case startCreation(sessionId: String, worktreeId: UUID)
    case createSucceeded(tabId: Int)
    case createFailed(reason: String)

    // Lifecycle events
    case activate
    case deactivate
    case closed

    // Special events
    case disable
}

// MARK: - Tab Effects

/// Side effects produced by tab state transitions.
enum TabEffect: Sendable, Equatable {
    case queryTabExists(sessionId: String)
    case createTab(sessionId: String, worktreeId: UUID)
    case updateTabId(Int)
    case notifyReady(tabId: Int)
    case notifyFailed(reason: String)
}

// MARK: - Convenience

extension TabStatus {
    /// Whether the tab is ready for use.
    var isReady: Bool {
        switch self {
        case .verified, .active:
            return true
        default:
            return false
        }
    }

    /// Whether the tab needs creation.
    var needsCreation: Bool {
        switch self {
        case .missing, .failed:
            return true
        default:
            return false
        }
    }

    /// Whether the tab is in a terminal state.
    var isTerminal: Bool {
        switch self {
        case .unsupported:
            return true
        default:
            return false
        }
    }

    /// Human-readable description of the status.
    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .verifying:
            return "Verifying..."
        case .verified:
            return "Ready"
        case .missing:
            return "Missing"
        case .creating:
            return "Creating..."
        case .active:
            return "Active"
        case .failed(let reason):
            return "Failed: \(reason)"
        case .unsupported:
            return "Unsupported"
        }
    }
}
