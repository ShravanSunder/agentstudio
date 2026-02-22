import Foundation
import SwiftUI

/// A git worktree within a repo
struct Worktree: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: URL
    var branch: String
    var agent: AgentType?
    var status: WorktreeStatus
    var isMainWorktree: Bool

    /// Deterministic identity derived from filesystem path via SHA-256.
    /// Used for zmx session ID segment. Survives reinstall/data loss, breaks on directory move.
    var stableKey: String { StableKey.fromPath(path) }

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        branch: String,
        agent: AgentType? = nil,
        status: WorktreeStatus = .idle,
        isMainWorktree: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
        self.agent = agent
        self.status = status
        self.isMainWorktree = isMainWorktree
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(URL.self, forKey: .path)
        self.branch = try container.decode(String.self, forKey: .branch)
        self.agent = try container.decodeIfPresent(AgentType.self, forKey: .agent)
        self.status = try container.decodeIfPresent(WorktreeStatus.self, forKey: .status) ?? .idle
        self.isMainWorktree = try container.decodeIfPresent(Bool.self, forKey: .isMainWorktree) ?? false
    }
}

// MARK: - Worktree Status

enum WorktreeStatus: String, Codable, CaseIterable {
    case idle  // No agent running
    case running  // Agent actively working
    case pendingReview  // Agent done, checkpoints need review
    case error  // Something went wrong

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
    case claude
    case codex
    case gemini
    case aider
    case custom

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
