import SwiftUI
import SwiftTerm
import AppKit

/// SwiftUI wrapper for SwiftTerm's LocalProcessTerminalView
struct TerminalView: NSViewRepresentable {
    let worktree: Worktree
    let project: Project
    let terminalManager: TerminalManager

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminalManager.createTerminal(for: worktree, in: project)
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Terminal is self-managing once created
        // Future: could handle theme changes, font size changes, etc.
    }
}

// MARK: - Terminal Container

/// Container view that handles terminal lifecycle and provides controls
struct TerminalContainerView: View {
    let worktree: Worktree
    let project: Project
    @ObservedObject var terminalManager: TerminalManager

    @State private var showingAgentPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Terminal header
            TerminalHeaderView(
                worktree: worktree,
                onStartAgent: { showingAgentPicker = true },
                onOpenInCursor: openInCursor
            )

            Divider()

            // Terminal content
            TerminalView(
                worktree: worktree,
                project: project,
                terminalManager: terminalManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showingAgentPicker) {
            AgentPickerView(worktree: worktree, terminalManager: terminalManager)
        }
    }

    private func openInCursor() {
        let cursorURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([worktree.path], withApplicationAt: cursorURL, configuration: config)
    }
}

// MARK: - Terminal Header

struct TerminalHeaderView: View {
    let worktree: Worktree
    let onStartAgent: () -> Void
    let onOpenInCursor: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Path
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                Text(worktree.path.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Status
            if let agent = worktree.agent {
                HStack(spacing: 4) {
                    Circle()
                        .fill(worktree.status.color)
                        .frame(width: 6, height: 6)

                    Text(agent.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Actions
            HStack(spacing: 8) {
                Button(action: onStartAgent) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Start Agent")

                Button(action: onOpenInCursor) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Open in Cursor")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Agent Picker

struct AgentPickerView: View {
    let worktree: Worktree
    let terminalManager: TerminalManager

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAgent: AgentType = .claude
    @State private var prompt: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Start Agent")
                .font(.headline)

            Picker("Agent", selection: $selectedAgent) {
                ForEach(AgentType.allCases, id: \.self) { agent in
                    Text(agent.displayName).tag(agent)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            TextEditor(text: $prompt)
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)

            if prompt.isEmpty {
                Text("Enter a prompt for the agent, or leave empty to start interactive mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start") {
                    startAgent()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedAgent == .custom)
            }
            .padding()
        }
        .frame(width: 400)
        .padding()
    }

    private func startAgent() {
        let command: String
        if prompt.isEmpty {
            command = selectedAgent.command
        } else {
            command = "\(selectedAgent.command) \"\(prompt.replacingOccurrences(of: "\"", with: "\\\""))\""
        }

        terminalManager.sendCommand(to: worktree.id, command: command)
    }
}
