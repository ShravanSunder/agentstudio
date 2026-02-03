import Foundation
import SwiftUI

/// A git worktree within a project
struct Worktree: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: URL
    var branch: String
    var agent: AgentType?
    var status: WorktreeStatus
    var isOpen: Bool
    var lastOpened: Date?

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        branch: String,
        agent: AgentType? = nil,
        status: WorktreeStatus = .idle,
        isOpen: Bool = false,
        lastOpened: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
        self.agent = agent
        self.status = status
        self.isOpen = isOpen
        self.lastOpened = lastOpened
    }
}

// MARK: - Worktree Status

enum WorktreeStatus: String, Codable, CaseIterable {
    case idle           // No agent running
    case running        // Agent actively working
    case pendingReview  // Agent done, checkpoints need review
    case error          // Something went wrong

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .pendingReview: return "Pending Review"
        case .error: return "Error"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .running: return .green
        case .pendingReview: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Agent Type

enum AgentType: String, Codable, CaseIterable {
    case claude = "claude"
    case codex = "codex"
    case gemini = "gemini"
    case aider = "aider"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .aider: return "Aider"
        case .custom: return "Custom"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "CC"
        case .codex: return "CX"
        case .gemini: return "GM"
        case .aider: return "AD"
        case .custom: return "?"
        }
    }

    var command: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .aider: return "aider"
        case .custom: return ""
        }
    }

    var color: Color {
        switch self {
        case .claude: return .orange
        case .codex: return .green
        case .gemini: return .blue
        case .aider: return .purple
        case .custom: return .gray
        }
    }
}
