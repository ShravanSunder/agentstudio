# Session Restore Implementation Spec

> **For:** Implementation agent
> **Approach:** Invisible Zellij (validated)
> **Design Doc:** [session-restore-design.md](./session-restore-design.md)

---

## Quick Context

Agent Studio embeds Ghostty for terminal rendering. Currently, terminals die when app closes. We're adding Zellij as a session daemon so terminals persist.

**How it works:**
1. Agent Studio creates Zellij sessions via CLI (`zellij attach <name> --create-background`)
2. Ghostty surfaces run `zellij attach <name>` as their command
3. Zellij owns the PTY → processes survive app crashes
4. On reboot, restore from checkpoint file

---

## File Structure (What You'll Create)

```
Sources/AgentStudio/
├── Models/
│   ├── ZellijSession.swift      # NEW
│   └── SessionCheckpoint.swift  # NEW
├── Services/
│   ├── ZellijService.swift      # NEW
│   └── SessionManager.swift     # MODIFY (add Zellij integration)
└── Resources/
    └── zellij/                  # NEW (bundled configs)
        ├── invisible.kdl
        └── layouts/
            └── minimal.kdl
```

---

## Step 1: Create Zellij Config Files

### File: `Sources/AgentStudio/Resources/zellij/invisible.kdl`

```kdl
// Invisible Zellij - no UI, all keys pass through
default_mode "locked"
keybinds clear-defaults=true { }
pane_frames false
simplified_ui true
show_startup_tips false
show_release_notes false
session_serialization true
serialize_pane_viewport true
scrollback_lines_to_serialize 10000
mouse_mode false
scroll_buffer_size 50000
```

### File: `Sources/AgentStudio/Resources/zellij/layouts/minimal.kdl`

```kdl
layout {
    pane
}
```

---

## Step 2: Create ZellijSession Model

### File: `Sources/AgentStudio/Models/ZellijSession.swift`

```swift
import Foundation

/// A Zellij session managed by Agent Studio
struct ZellijSession: Codable, Identifiable, Hashable {
    /// Session ID (Zellij session name): "agentstudio--<8-char-uuid>"
    let id: String

    /// Associated project UUID
    let projectId: UUID

    /// Display name (repo name)
    let displayName: String

    /// When created
    let createdAt: Date

    /// Currently running?
    var isRunning: Bool

    /// Tabs in this session
    var tabs: [ZellijTab]

    init(id: String, projectId: UUID, displayName: String, createdAt: Date = Date(), isRunning: Bool = true, tabs: [ZellijTab] = []) {
        self.id = id
        self.projectId = projectId
        self.displayName = displayName
        self.createdAt = createdAt
        self.isRunning = isRunning
        self.tabs = tabs
    }

    /// Generate session ID from project
    static func sessionId(for projectId: UUID) -> String {
        "agentstudio--\(projectId.uuidString.prefix(8).lowercased())"
    }
}

/// A tab within a Zellij session
struct ZellijTab: Codable, Identifiable, Hashable {
    /// Tab index (1-based, from Zellij)
    let id: Int

    /// Tab name (branch name)
    var name: String

    /// Associated worktree UUID
    let worktreeId: UUID

    /// Working directory
    let workingDirectory: URL

    /// Command to re-run on restore (e.g., "claude")
    var restoreCommand: String?

    init(id: Int, name: String, worktreeId: UUID, workingDirectory: URL, restoreCommand: String? = nil) {
        self.id = id
        self.name = name
        self.worktreeId = worktreeId
        self.workingDirectory = workingDirectory
        self.restoreCommand = restoreCommand
    }
}
```

---

## Step 3: Create SessionCheckpoint Model

### File: `Sources/AgentStudio/Models/SessionCheckpoint.swift`

```swift
import Foundation

/// Checkpoint for reboot recovery
struct SessionCheckpoint: Codable {
    let version: Int
    let timestamp: Date
    let sessions: [SessionData]

    struct SessionData: Codable {
        let id: String
        let projectId: UUID
        let displayName: String
        let tabs: [TabData]
    }

    struct TabData: Codable {
        let id: Int
        let name: String
        let worktreeId: UUID
        let workingDirectory: String
        let restoreCommand: String?
    }

    init(sessions: [ZellijSession]) {
        self.version = 1
        self.timestamp = Date()
        self.sessions = sessions.map { session in
            SessionData(
                id: session.id,
                projectId: session.projectId,
                displayName: session.displayName,
                tabs: session.tabs.map { tab in
                    TabData(
                        id: tab.id,
                        name: tab.name,
                        worktreeId: tab.worktreeId,
                        workingDirectory: tab.workingDirectory.path,
                        restoreCommand: tab.restoreCommand
                    )
                }
            )
        }
    }
}
```

---

## Step 4: Create ZellijService

### File: `Sources/AgentStudio/Services/ZellijService.swift`

```swift
import Foundation
import os

private let logger = Logger(subsystem: "com.agentstudio", category: "Zellij")

/// Error types for Zellij operations
enum ZellijError: Error, LocalizedError {
    case notInstalled
    case sessionCreationFailed(String)
    case sessionNotFound(String)
    case tabCreationFailed(String)
    case commandFailed(command: String, stderr: String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Zellij is not installed. Install with: brew install zellij"
        case .sessionCreationFailed(let msg):
            return "Failed to create Zellij session: \(msg)"
        case .sessionNotFound(let name):
            return "Zellij session not found: \(name)"
        case .tabCreationFailed(let msg):
            return "Failed to create tab: \(msg)"
        case .commandFailed(let cmd, let stderr):
            return "Zellij command failed (\(cmd)): \(stderr)"
        }
    }
}

/// Manages Zellij sessions via CLI
@MainActor
final class ZellijService: ObservableObject {
    static let shared = ZellijService()

    /// Active sessions
    @Published private(set) var sessions: [ZellijSession] = []

    /// Path to invisible.kdl config
    private let configPath: URL

    /// Path to minimal.kdl layout
    private let layoutPath: URL

    private init() {
        // Config files are copied to ~/.agentstudio/zellij/ on first run
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio/zellij")
        self.configPath = appSupport.appending(path: "invisible.kdl")
        self.layoutPath = appSupport.appending(path: "layouts/minimal.kdl")
    }

    // MARK: - Setup

    /// Ensure config files exist (call on app launch)
    func ensureConfigFiles() throws {
        let configDir = configPath.deletingLastPathComponent()
        let layoutDir = layoutPath.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: layoutDir, withIntermediateDirectories: true)

        // Copy from bundle if not exists
        if !FileManager.default.fileExists(atPath: configPath.path) {
            if let bundled = Bundle.main.url(forResource: "invisible", withExtension: "kdl", subdirectory: "zellij") {
                try FileManager.default.copyItem(at: bundled, to: configPath)
            } else {
                // Write default
                try Self.invisibleKdl.write(to: configPath, atomically: true, encoding: .utf8)
            }
        }

        if !FileManager.default.fileExists(atPath: layoutPath.path) {
            if let bundled = Bundle.main.url(forResource: "minimal", withExtension: "kdl", subdirectory: "zellij/layouts") {
                try FileManager.default.copyItem(at: bundled, to: layoutPath)
            } else {
                try Self.minimalKdl.write(to: layoutPath, atomically: true, encoding: .utf8)
            }
        }

        logger.info("Zellij config files ready at \(configDir.path)")
    }

    /// Check if Zellij is installed
    func isZellijInstalled() -> Bool {
        let result = runProcess("/usr/bin/which", arguments: ["zellij"])
        return result.exitCode == 0
    }

    // MARK: - Session Lifecycle

    /// Create a new session for a project
    func createSession(for project: Project) async throws -> ZellijSession {
        let sessionId = ZellijSession.sessionId(for: project.id)

        // Check if already exists
        if await sessionExists(sessionId) {
            logger.info("Session \(sessionId) already exists, reusing")
            if let existing = sessions.first(where: { $0.id == sessionId }) {
                return existing
            }
        }

        // Create background session
        let result = runProcess("/opt/homebrew/bin/zellij", arguments: [
            "--config", configPath.path,
            "--layout", layoutPath.path,
            "attach", sessionId,
            "--create-background"
        ])

        if result.exitCode != 0 && !result.stderr.contains("already exists") {
            throw ZellijError.sessionCreationFailed(result.stderr)
        }

        let session = ZellijSession(
            id: sessionId,
            projectId: project.id,
            displayName: project.name
        )

        sessions.append(session)
        logger.info("Created Zellij session: \(sessionId)")

        return session
    }

    /// Destroy a session
    func destroySession(_ session: ZellijSession) async throws {
        let result = runProcess("/opt/homebrew/bin/zellij", arguments: [
            "kill-session", session.id
        ])

        if result.exitCode != 0 && !result.stderr.contains("not found") {
            throw ZellijError.commandFailed(command: "kill-session", stderr: result.stderr)
        }

        sessions.removeAll { $0.id == session.id }
        logger.info("Destroyed Zellij session: \(session.id)")
    }

    /// Check if session exists
    func sessionExists(_ sessionId: String) async -> Bool {
        let result = runProcess("/opt/homebrew/bin/zellij", arguments: ["list-sessions"])
        return result.stdout.contains(sessionId)
    }

    /// List all agentstudio sessions
    func discoverSessions() async -> [String] {
        let result = runProcess("/opt/homebrew/bin/zellij", arguments: ["list-sessions"])
        return result.stdout
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                // Extract session name (first word, before ANSI codes)
                let cleaned = line.replacingOccurrences(of: "\\x1B\\[[0-9;]*m", with: "", options: .regularExpression)
                let name = cleaned.components(separatedBy: .whitespaces).first ?? ""
                return name.hasPrefix("agentstudio--") ? name : nil
            }
    }

    // MARK: - Tab Management

    /// Create a tab for a worktree
    func createTab(in session: ZellijSession, for worktree: Worktree) async throws -> ZellijTab {
        let result = runProcess("/opt/homebrew/bin/zellij", arguments: [
            "--session", session.id,
            "action", "new-tab",
            "--name", worktree.branch,
            "--cwd", worktree.path.path
        ])

        if result.exitCode != 0 {
            throw ZellijError.tabCreationFailed(result.stderr)
        }

        // Get tab count to determine new tab's index
        let tabNames = try await getTabNames(for: session)
        let tabIndex = tabNames.count

        let tab = ZellijTab(
            id: tabIndex,
            name: worktree.branch,
            worktreeId: worktree.id,
            workingDirectory: worktree.path
        )

        // Update session
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].tabs.append(tab)
        }

        logger.info("Created tab '\(worktree.branch)' in session \(session.id)")
        return tab
    }

    /// Close a tab
    func closeTab(_ tab: ZellijTab, in session: ZellijSession) async throws {
        // Switch to tab first, then close
        _ = runProcess("/opt/homebrew/bin/zellij", arguments: [
            "--session", session.id,
            "action", "go-to-tab", String(tab.id)
        ])

        let result = runProcess("/opt/homebrew/bin/zellij", arguments: [
            "--session", session.id,
            "action", "close-tab"
        ])

        if result.exitCode != 0 {
            throw ZellijError.commandFailed(command: "close-tab", stderr: result.stderr)
        }

        // Update session
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].tabs.removeAll { $0.id == tab.id }
        }

        logger.info("Closed tab \(tab.id) in session \(session.id)")
    }

    /// Get tab names for a session
    func getTabNames(for session: ZellijSession) async throws -> [String] {
        let result = runProcess("/opt/homebrew/bin/zellij", arguments: [
            "--session", session.id,
            "action", "query-tab-names"
        ])

        return result.stdout
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    // MARK: - Commands

    /// Get attach command for Ghostty surface
    func attachCommand(for session: ZellijSession) -> String {
        "/opt/homebrew/bin/zellij --config \(configPath.path) attach \(session.id)"
    }

    /// Send text to the focused pane
    func sendText(_ text: String, to session: ZellijSession) async throws {
        let result = runProcess("/opt/homebrew/bin/zellij", arguments: [
            "--session", session.id,
            "action", "write-chars", text
        ])

        if result.exitCode != 0 {
            throw ZellijError.commandFailed(command: "write-chars", stderr: result.stderr)
        }
    }

    // MARK: - Helpers

    private func runProcess(_ path: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return (process.terminationStatus, stdout, stderr)
    }

    // MARK: - Default Configs

    private static let invisibleKdl = """
    default_mode "locked"
    keybinds clear-defaults=true { }
    pane_frames false
    simplified_ui true
    show_startup_tips false
    show_release_notes false
    session_serialization true
    serialize_pane_viewport true
    scrollback_lines_to_serialize 10000
    mouse_mode false
    scroll_buffer_size 50000
    """

    private static let minimalKdl = """
    layout {
        pane
    }
    """
}
```

---

## Step 5: Modify SessionManager

### File: `Sources/AgentStudio/Services/SessionManager.swift`

**Add these properties:**

```swift
// Add to SessionManager class
private let zellijService = ZellijService.shared
private let checkpointURL: URL

// In init(), add:
self.checkpointURL = appSupport.appending(path: "session-checkpoint.json")
```

**Add these methods:**

```swift
// MARK: - Zellij Integration

/// Get or create Zellij session for a project
func getOrCreateSession(for project: Project) async throws -> ZellijSession {
    if let existing = zellijService.sessions.first(where: { $0.projectId == project.id }) {
        return existing
    }
    return try await zellijService.createSession(for: project)
}

/// Get or create Zellij tab for a worktree
func getOrCreateTab(in session: ZellijSession, for worktree: Worktree) async throws -> ZellijTab {
    if let existing = session.tabs.first(where: { $0.worktreeId == worktree.id }) {
        return existing
    }
    return try await zellijService.createTab(in: session, for: worktree)
}

// MARK: - Checkpoint

/// Save checkpoint for reboot recovery
func saveCheckpoint() {
    let checkpoint = SessionCheckpoint(sessions: zellijService.sessions)

    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(checkpoint)
        try data.write(to: checkpointURL, options: .atomic)
        logger.info("Saved session checkpoint")
    } catch {
        logger.error("Failed to save checkpoint: \(error)")
    }
}

/// Restore from checkpoint after reboot
func restoreFromCheckpoint() async {
    guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
        return
    }

    do {
        let data = try Data(contentsOf: checkpointURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let checkpoint = try decoder.decode(SessionCheckpoint.self, from: data)

        for sessionData in checkpoint.sessions {
            // Skip if session already running
            if await zellijService.sessionExists(sessionData.id) {
                continue
            }

            // Find project
            guard let project = projects.first(where: { $0.id == sessionData.projectId }) else {
                continue
            }

            // Recreate session
            let session = try await zellijService.createSession(for: project)

            // Recreate tabs
            for tabData in sessionData.tabs {
                guard let worktree = project.worktrees.first(where: { $0.id == tabData.worktreeId }) else {
                    continue
                }

                var tab = try await zellijService.createTab(in: session, for: worktree)
                tab.restoreCommand = tabData.restoreCommand

                // Re-run command if specified
                if let cmd = tabData.restoreCommand, !cmd.isEmpty {
                    try await zellijService.sendText(cmd + "\n", to: session)
                }
            }
        }

        logger.info("Restored \(checkpoint.sessions.count) sessions from checkpoint")
    } catch {
        logger.error("Failed to restore checkpoint: \(error)")
    }
}
```

**Add logger at top of file:**

```swift
import os

private let logger = Logger(subsystem: "com.agentstudio", category: "SessionManager")
```

---

## Step 6: Modify Ghostty Surface Creation

### File: `Sources/AgentStudio/Ghostty/GhosttySurfaceView.swift`

**Current:** `SurfaceConfiguration` has `command: String?`

**Change surface creation to use Zellij attach:**

In whatever method creates surfaces for tabs, change from:

```swift
// OLD
let config = SurfaceConfiguration(
    workingDirectory: worktree.path.path,
    command: nil  // or shell
)
```

To:

```swift
// NEW
let session = try await sessionManager.getOrCreateSession(for: project)
let _ = try await sessionManager.getOrCreateTab(in: session, for: worktree)

let config = SurfaceConfiguration(
    workingDirectory: worktree.path.path,
    command: ZellijService.shared.attachCommand(for: session)
)
```

---

## Step 7: App Lifecycle Hooks

### File: `Sources/AgentStudio/App/AppDelegate.swift`

**On launch (in `applicationDidFinishLaunching`):**

```swift
// After Ghostty.initialize()
do {
    try ZellijService.shared.ensureConfigFiles()
} catch {
    logger.error("Failed to setup Zellij configs: \(error)")
}

// After sessionManager.load()
Task {
    let runningSessions = await ZellijService.shared.discoverSessions()
    if runningSessions.isEmpty {
        await sessionManager.restoreFromCheckpoint()
    }
}
```

**On quit (in `applicationWillTerminate`):**

```swift
sessionManager.saveCheckpoint()
// Do NOT kill Zellij sessions - they should persist
```

---

## Verification Checklist

After implementation, verify:

- [ ] `zellij list-sessions` shows `agentstudio--*` sessions
- [ ] Ghostty surface shows shell prompt (no Zellij UI visible)
- [ ] Ctrl+C, Ctrl+D, arrow keys work normally
- [ ] Closing Agent Studio leaves Zellij session running
- [ ] Reopening Agent Studio reconnects to existing session
- [ ] After simulated reboot, checkpoint restores sessions

---

## Key Paths Reference

| Item | Path |
|------|------|
| Zellij binary | `/opt/homebrew/bin/zellij` |
| App config dir | `~/.agentstudio/` |
| Zellij config | `~/.agentstudio/zellij/invisible.kdl` |
| Zellij layout | `~/.agentstudio/zellij/layouts/minimal.kdl` |
| Checkpoint file | `~/.agentstudio/session-checkpoint.json` |
| Projects file | `~/.agentstudio/projects.json` |
| State file | `~/.agentstudio/state.json` |

---

## CLI Commands Reference

```bash
# Create background session
zellij --config <config> --layout <layout> attach <name> --create-background

# List sessions
zellij list-sessions

# Kill session
zellij kill-session <name>

# Create tab
zellij --session <name> action new-tab --name <tab-name> --cwd <path>

# Query tab names
zellij --session <name> action query-tab-names

# Close current tab
zellij --session <name> action close-tab

# Write to terminal
zellij --session <name> action write-chars "text"

# Attach (what Ghostty runs)
zellij --config <config> attach <name>
```

---

## Testing Strategy

### Test Architecture Overview

```
Tests/
├── AgentStudioTests/              # Unit + Integration tests (Swift Testing)
│   ├── Services/
│   │   ├── ZellijServiceTests.swift
│   │   └── SessionManagerTests.swift
│   ├── Models/
│   │   ├── ZellijSessionTests.swift
│   │   └── SessionCheckpointTests.swift
│   └── Mocks/
│       ├── MockProcessExecutor.swift
│       └── MockFileSystem.swift
├── AgentStudioIntegrationTests/   # Workflow tests (Swift Testing)
│   └── SessionWorkflowTests.swift
└── AgentStudioUITests/            # Visual tests (XCTest + Peekaboo)
    ├── TerminalRenderingTests.swift
    └── SnapshotTests.swift
```

### Test Types and When to Use Each

| Test Type | Framework | What It Tests | When to Run |
|-----------|-----------|---------------|-------------|
| **Unit** | Swift Testing | Single function/method in isolation | Every commit |
| **Integration** | Swift Testing | Multiple components working together | Every commit |
| **Snapshot** | XCTest + SnapshotTesting | UI layout and appearance | PR reviews |
| **Visual/E2E** | XCTest + Peekaboo | Full app with Ghostty rendering | Before release |

---

### Step T1: Update Package.swift for Testing

Add test targets to `Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentStudio",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentStudio", targets: ["AgentStudio"])
    ],
    dependencies: [
        // For snapshot testing
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "AgentStudio",
            dependencies: ["GhosttyKit"],
            path: "Sources/AgentStudio",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreServices"),
                .linkedLibrary("z"),
                .linkedLibrary("c++")
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "Frameworks/GhosttyKit.xcframework"
        ),
        // Unit + Integration tests
        .testTarget(
            name: "AgentStudioTests",
            dependencies: ["AgentStudio"],
            path: "Tests/AgentStudioTests"
        ),
        // UI + Snapshot tests
        .testTarget(
            name: "AgentStudioUITests",
            dependencies: [
                "AgentStudio",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/AgentStudioUITests"
        )
    ]
)
```

---

### Step T2: Create Protocol for Process Execution (Enables Mocking)

**Why:** ZellijService calls external `zellij` CLI. To unit test without real Zellij, we inject a mock.

### File: `Sources/AgentStudio/Services/ProcessExecutor.swift`

```swift
import Foundation

/// Result of running an external process
struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

/// Protocol for executing external processes (enables mocking in tests)
protocol ProcessExecutor: Sendable {
    func execute(_ path: String, arguments: [String]) async -> ProcessResult
}

/// Real implementation that runs actual processes
struct RealProcessExecutor: ProcessExecutor {
    func execute(_ path: String, arguments: [String]) async -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
```

### Modify ZellijService to Accept Executor

In `ZellijService.swift`, change:

```swift
@MainActor
final class ZellijService: ObservableObject {
    static let shared = ZellijService()

    private let executor: ProcessExecutor

    // Production init
    private init() {
        self.executor = RealProcessExecutor()
        // ... rest of init
    }

    // Test init
    init(executor: ProcessExecutor) {
        self.executor = executor
        // ... rest of init
    }

    // Replace all runProcess() calls with:
    // let result = await executor.execute(path, arguments: args)
}
```

---

### Step T3: Create Mock for Unit Tests

### File: `Tests/AgentStudioTests/Mocks/MockProcessExecutor.swift`

```swift
import Foundation
@testable import AgentStudio

/// Mock process executor for testing
final class MockProcessExecutor: ProcessExecutor, @unchecked Sendable {
    /// Responses keyed by command (e.g., "zellij list-sessions")
    var responses: [String: ProcessResult] = [:]

    /// Record of all executed commands
    private(set) var executedCommands: [[String]] = []

    func execute(_ path: String, arguments: [String]) async -> ProcessResult {
        executedCommands.append([path] + arguments)

        // Build key from command name + first few args
        let cmdName = URL(fileURLWithPath: path).lastPathComponent
        let key = ([cmdName] + arguments).joined(separator: " ")

        if let response = responses[key] {
            return response
        }

        // Check for partial matches (useful for session-specific commands)
        for (pattern, response) in responses {
            if key.contains(pattern) {
                return response
            }
        }

        // Default: command not mocked
        return ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Command not mocked: \(key)"
        )
    }

    /// Helper to set up a successful response
    func mockSuccess(_ command: String, stdout: String = "") {
        responses[command] = ProcessResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    /// Helper to set up a failure response
    func mockFailure(_ command: String, stderr: String) {
        responses[command] = ProcessResult(exitCode: 1, stdout: "", stderr: stderr)
    }

    /// Reset state between tests
    func reset() {
        responses.removeAll()
        executedCommands.removeAll()
    }
}
```

---

### Step T4: Write Unit Tests for ZellijService

### File: `Tests/AgentStudioTests/Services/ZellijServiceTests.swift`

```swift
import Testing
import Foundation
@testable import AgentStudio

@Suite("ZellijService Unit Tests")
struct ZellijServiceTests {

    // MARK: - Session Creation

    @Test("Create session succeeds with valid project")
    func createSessionSuccess() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("zellij --config", stdout: "")
        executor.mockSuccess("zellij list-sessions", stdout: "")

        let service = ZellijService(executor: executor)
        let project = Project(
            name: "test-project",
            repoPath: URL(fileURLWithPath: "/tmp/test"),
            worktrees: []
        )

        let session = try await service.createSession(for: project)

        #expect(session.displayName == "test-project")
        #expect(session.id.hasPrefix("agentstudio--"))
        #expect(session.isRunning == true)
        #expect(executor.executedCommands.count >= 1)
    }

    @Test("Create session fails when zellij errors")
    func createSessionFailure() async throws {
        let executor = MockProcessExecutor()
        executor.mockFailure("zellij --config", stderr: "Session creation failed")
        executor.mockSuccess("zellij list-sessions", stdout: "")

        let service = ZellijService(executor: executor)
        let project = Project(
            name: "bad-project",
            repoPath: URL(fileURLWithPath: "/tmp/bad"),
            worktrees: []
        )

        await #expect(throws: ZellijError.self) {
            try await service.createSession(for: project)
        }
    }

    @Test("Create session reuses existing session")
    func createSessionReusesExisting() async throws {
        let executor = MockProcessExecutor()
        let sessionId = "agentstudio--12345678"
        executor.mockSuccess("zellij list-sessions", stdout: "\(sessionId) [Created 1h ago]")

        let service = ZellijService(executor: executor)
        let project = Project(
            id: UUID(uuidString: "12345678-0000-0000-0000-000000000000")!,
            name: "existing",
            repoPath: URL(fileURLWithPath: "/tmp/existing"),
            worktrees: []
        )

        // Should not call create if session exists
        let session = try await service.createSession(for: project)

        #expect(session.id == sessionId)
        // Verify no attach --create-background was called
        let createCalls = executor.executedCommands.filter { $0.contains("--create-background") }
        #expect(createCalls.isEmpty)
    }

    // MARK: - Tab Management

    @Test("Create tab adds to session")
    func createTabSuccess() async throws {
        let executor = MockProcessExecutor()
        executor.mockSuccess("zellij --session", stdout: "")
        executor.mockSuccess("zellij action query-tab-names", stdout: "Tab #1\nfeature-branch")

        let service = ZellijService(executor: executor)
        let session = ZellijSession(
            id: "agentstudio--test",
            projectId: UUID(),
            displayName: "test"
        )
        let worktree = Worktree(
            path: URL(fileURLWithPath: "/tmp/worktree"),
            branch: "feature-branch",
            isMain: false
        )

        let tab = try await service.createTab(in: session, for: worktree)

        #expect(tab.name == "feature-branch")
        #expect(tab.worktreeId == worktree.id)
    }

    // MARK: - Session Discovery

    @Test("Discover sessions filters to agentstudio prefix")
    func discoverSessionsFilters() async {
        let executor = MockProcessExecutor()
        executor.mockSuccess("zellij list-sessions", stdout: """
            agentstudio--abc123 [Created 1h ago]
            my-personal-session [Created 2h ago]
            agentstudio--def456 [Created 30m ago]
            random-session [Created 1d ago]
            """)

        let service = ZellijService(executor: executor)
        let sessions = await service.discoverSessions()

        #expect(sessions.count == 2)
        #expect(sessions.contains("agentstudio--abc123"))
        #expect(sessions.contains("agentstudio--def456"))
        #expect(!sessions.contains("my-personal-session"))
    }

    // MARK: - Attach Command

    @Test("Attach command includes config path")
    func attachCommandFormat() async throws {
        let executor = MockProcessExecutor()
        let service = ZellijService(executor: executor)
        let session = ZellijSession(
            id: "agentstudio--test",
            projectId: UUID(),
            displayName: "test"
        )

        let command = service.attachCommand(for: session)

        #expect(command.contains("zellij"))
        #expect(command.contains("--config"))
        #expect(command.contains("invisible.kdl"))
        #expect(command.contains("attach"))
        #expect(command.contains("agentstudio--test"))
    }
}
```

---

### Step T5: Write Integration Tests

### File: `Tests/AgentStudioTests/SessionWorkflowTests.swift`

```swift
import Testing
import Foundation
@testable import AgentStudio

@Suite("Session Workflow Integration Tests")
struct SessionWorkflowTests {

    @Test("Full session lifecycle: create → add tabs → checkpoint → restore")
    func fullSessionLifecycle() async throws {
        let executor = MockProcessExecutor()

        // Mock all the commands in the workflow
        executor.mockSuccess("zellij list-sessions", stdout: "")
        executor.mockSuccess("zellij --config", stdout: "")
        executor.mockSuccess("zellij --session", stdout: "")
        executor.mockSuccess("zellij action query-tab-names", stdout: "main\nfeature-a")

        let service = ZellijService(executor: executor)

        // 1. Create project and session
        let project = Project(
            name: "workflow-test",
            repoPath: URL(fileURLWithPath: "/tmp/workflow"),
            worktrees: [
                Worktree(path: URL(fileURLWithPath: "/tmp/workflow"), branch: "main", isMain: true),
                Worktree(path: URL(fileURLWithPath: "/tmp/workflow-feature"), branch: "feature-a", isMain: false)
            ]
        )

        let session = try await service.createSession(for: project)
        #expect(session.isRunning)

        // 2. Add tabs for worktrees
        for worktree in project.worktrees {
            _ = try await service.createTab(in: session, for: worktree)
        }

        #expect(service.sessions.first?.tabs.count == 2)

        // 3. Create checkpoint
        let checkpoint = SessionCheckpoint(sessions: service.sessions)
        #expect(checkpoint.sessions.count == 1)
        #expect(checkpoint.sessions.first?.tabs.count == 2)

        // 4. Verify checkpoint can be encoded/decoded
        let encoder = JSONEncoder()
        let data = try encoder.encode(checkpoint)

        let decoder = JSONDecoder()
        let restored = try decoder.decode(SessionCheckpoint.self, from: data)

        #expect(restored.sessions.count == checkpoint.sessions.count)
        #expect(restored.sessions.first?.tabs.count == checkpoint.sessions.first?.tabs.count)
    }

    @Test("Session persists after simulated app restart")
    func sessionPersistsAfterRestart() async throws {
        let executor = MockProcessExecutor()

        // First "run" - create session
        executor.mockSuccess("zellij list-sessions", stdout: "")
        executor.mockSuccess("zellij --config", stdout: "")

        let service1 = ZellijService(executor: executor)
        let project = Project(name: "persist-test", repoPath: URL(fileURLWithPath: "/tmp/persist"), worktrees: [])
        let session = try await service1.createSession(for: project)

        // Simulate app quit (just save checkpoint)
        let checkpoint = SessionCheckpoint(sessions: service1.sessions)

        // Second "run" - session should be discovered
        executor.mockSuccess("zellij list-sessions", stdout: "\(session.id) [Created 1m ago]")

        let service2 = ZellijService(executor: executor)
        let discovered = await service2.discoverSessions()

        #expect(discovered.contains(session.id))
    }
}
```

---

### Step T6: Write Model Tests

### File: `Tests/AgentStudioTests/Models/ZellijSessionTests.swift`

```swift
import Testing
import Foundation
@testable import AgentStudio

@Suite("ZellijSession Model Tests")
struct ZellijSessionTests {

    @Test("Session ID generation is deterministic")
    func sessionIdDeterministic() {
        let uuid = UUID(uuidString: "12345678-90ab-cdef-1234-567890abcdef")!

        let id1 = ZellijSession.sessionId(for: uuid)
        let id2 = ZellijSession.sessionId(for: uuid)

        #expect(id1 == id2)
        #expect(id1 == "agentstudio--12345678")
    }

    @Test("Session ID uses lowercase")
    func sessionIdLowercase() {
        let uuid = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
        let id = ZellijSession.sessionId(for: uuid)

        #expect(id == "agentstudio--abcdef12")
    }

    @Test("Session encodes and decodes correctly")
    func sessionCodable() throws {
        let session = ZellijSession(
            id: "agentstudio--test",
            projectId: UUID(),
            displayName: "Test Project",
            tabs: [
                ZellijTab(id: 1, name: "main", worktreeId: UUID(), workingDirectory: URL(fileURLWithPath: "/tmp"))
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ZellijSession.self, from: data)

        #expect(decoded.id == session.id)
        #expect(decoded.displayName == session.displayName)
        #expect(decoded.tabs.count == 1)
    }
}

@Suite("SessionCheckpoint Model Tests")
struct SessionCheckpointTests {

    @Test("Checkpoint version is set correctly")
    func checkpointVersion() {
        let checkpoint = SessionCheckpoint(sessions: [])
        #expect(checkpoint.version == 1)
    }

    @Test("Checkpoint timestamp is recent")
    func checkpointTimestamp() {
        let before = Date()
        let checkpoint = SessionCheckpoint(sessions: [])
        let after = Date()

        #expect(checkpoint.timestamp >= before)
        #expect(checkpoint.timestamp <= after)
    }
}
```

---

### Step T7: Visual Tests with Peekaboo

**When to use:** Verify Ghostty renders correctly, no visual regressions in UI.

### File: `Tests/AgentStudioUITests/TerminalRenderingTests.swift`

```swift
import XCTest

/// Visual tests using Peekaboo for screenshot verification
/// Run manually before releases: `swift test --filter AgentStudioUITests`
final class TerminalRenderingTests: XCTestCase {

    let peekabooPath = "/opt/homebrew/bin/peekaboo"
    let screenshotDir = "/tmp/agentstudio-test-screenshots"

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(
            atPath: screenshotDir,
            withIntermediateDirectories: true
        )
    }

    /// Capture screenshot using Peekaboo CLI
    func captureScreenshot(name: String) throws -> URL {
        let outputPath = "\(screenshotDir)/\(name).png"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: peekabooPath)
        process.arguments = [
            "image",
            "--mode", "window",
            "--app", "Agent Studio",
            "--retina",
            "--path", outputPath
        ]

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "Peekaboo screenshot failed")

        return URL(fileURLWithPath: outputPath)
    }

    /// Visual test: Terminal shows shell prompt
    func testTerminalShowsPrompt() throws {
        // Launch app (assumes it's built)
        let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.agentstudio" }
        XCTAssertNotNil(app, "Agent Studio must be running for visual tests")

        // Wait for terminal to initialize
        Thread.sleep(forTimeInterval: 2.0)

        // Capture screenshot
        let screenshot = try captureScreenshot(name: "terminal-prompt")

        // Verify file exists and has content
        let data = try Data(contentsOf: screenshot)
        XCTAssertGreaterThan(data.count, 1000, "Screenshot should have content")

        // Manual verification: inspect screenshot at path
        print("📸 Screenshot saved: \(screenshot.path)")
        print("   Verify: Terminal shows shell prompt, no Zellij UI visible")
    }

    /// Visual test: No Zellij chrome visible
    func testNoZellijChromeVisible() throws {
        let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.agentstudio" }
        XCTAssertNotNil(app, "Agent Studio must be running")

        Thread.sleep(forTimeInterval: 1.0)

        let screenshot = try captureScreenshot(name: "no-zellij-chrome")

        print("📸 Screenshot saved: \(screenshot.path)")
        print("   Verify: No tab bar, no status bar, no pane frames from Zellij")
    }

    /// Visual test: Multiple tabs render correctly
    func testMultipleTabsRender() throws {
        // This test assumes multiple tabs are open
        let screenshot = try captureScreenshot(name: "multiple-tabs")

        print("📸 Screenshot saved: \(screenshot.path)")
        print("   Verify: Agent Studio tab bar shows tabs, Ghostty content renders")
    }
}
```

---

### Step T8: Snapshot Tests for UI Components

### File: `Tests/AgentStudioUITests/SnapshotTests.swift`

```swift
import XCTest
import SnapshotTesting
@testable import AgentStudio

/// Snapshot tests for UI components
/// These catch visual regressions automatically
final class SnapshotTests: XCTestCase {

    override func setUpWithError() throws {
        // First run creates reference snapshots
        // Subsequent runs compare against references
        // isRecording = true  // Uncomment to update snapshots
    }

    func testSidebarView() {
        let projects = [
            Project(name: "project-alpha", repoPath: URL(fileURLWithPath: "/tmp/alpha"), worktrees: [
                Worktree(path: URL(fileURLWithPath: "/tmp/alpha"), branch: "main", isMain: true),
                Worktree(path: URL(fileURLWithPath: "/tmp/alpha-feature"), branch: "feature-x", isMain: false)
            ]),
            Project(name: "project-beta", repoPath: URL(fileURLWithPath: "/tmp/beta"), worktrees: [])
        ]

        let view = SidebarView(projects: projects)

        assertSnapshot(of: view, as: .image(size: CGSize(width: 250, height: 400)))
    }

    func testTabBarView() {
        let tabs = [
            OpenTab(worktreeId: UUID(), projectId: UUID(), order: 0),
            OpenTab(worktreeId: UUID(), projectId: UUID(), order: 1),
            OpenTab(worktreeId: UUID(), projectId: UUID(), order: 2)
        ]

        let view = TabBarView(tabs: tabs, activeTabId: tabs[1].id)

        assertSnapshot(of: view, as: .image(size: CGSize(width: 600, height: 40)))
    }

    func testEmptyStateView() {
        let view = EmptyStateView()

        assertSnapshot(of: view, as: .image(size: CGSize(width: 400, height: 300)))
    }
}
```

---

### Test Commands Reference

```bash
# Run all unit tests
swift test --filter AgentStudioTests

# Run specific test suite
swift test --filter ZellijServiceTests

# Run integration tests
swift test --filter SessionWorkflowTests

# Run UI/snapshot tests (requires app to be built)
swift test --filter AgentStudioUITests

# Update snapshots (when UI intentionally changes)
swift test --filter SnapshotTests -- -D RECORD_SNAPSHOTS

# Run tests with verbose output
swift test -v

# Generate test coverage report
swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/AgentStudioPackageTests.xctest/Contents/MacOS/AgentStudioPackageTests \
    -instr-profile=.build/debug/codecov/default.profdata
```

---

### Peekaboo CLI Reference

```bash
# Install Peekaboo
brew install steipete/tap/peekaboo

# Capture full screen
peekaboo image --mode screen --retina --path screenshot.png

# Capture specific app window
peekaboo image --mode window --app "Agent Studio" --retina --path window.png

# Capture with AI analysis (for debugging)
peekaboo image --mode window --app "Agent Studio" --analyze --path analyzed.png

# List UI elements (for accessibility testing)
peekaboo see --app "Agent Studio" --json-output

# Run test sequence from file
peekaboo run .peekaboo.json
```

---

### Testing Checklist

**Before PR:**
- [ ] All unit tests pass (`swift test --filter AgentStudioTests`)
- [ ] Integration tests pass (`swift test --filter SessionWorkflowTests`)
- [ ] No snapshot test failures (or snapshots updated intentionally)

**Before Release:**
- [ ] Visual tests pass with Peekaboo
- [ ] Manual verification of screenshots
- [ ] Test on clean macOS install (no prior Zellij sessions)

**CI/CD Integration:**
```yaml
# Example GitHub Actions
test:
  runs-on: macos-14
  steps:
    - uses: actions/checkout@v4
    - name: Install Zellij
      run: brew install zellij
    - name: Run Unit Tests
      run: swift test --filter AgentStudioTests
    - name: Run Integration Tests
      run: swift test --filter SessionWorkflowTests
```

---

### Test File Checklist

After implementing tests, you should have:

```
Tests/
├── AgentStudioTests/
│   ├── Mocks/
│   │   └── MockProcessExecutor.swift       ✓
│   ├── Models/
│   │   └── ZellijSessionTests.swift        ✓
│   └── Services/
│       ├── ZellijServiceTests.swift        ✓
│       └── SessionWorkflowTests.swift      ✓
└── AgentStudioUITests/
    ├── TerminalRenderingTests.swift        ✓
    └── SnapshotTests.swift                 ✓
```
