import SwiftUI

struct SettingsView: View {
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 13
    @AppStorage("autoRefreshWorktrees") private var autoRefreshWorktrees: Bool = true
    @AppStorage("detachOnClose") private var detachOnClose: Bool = true

    var body: some View {
        TabView {
            GeneralSettingsView(
                autoRefreshWorktrees: $autoRefreshWorktrees,
                detachOnClose: $detachOnClose
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            TerminalSettingsView(
                fontSize: $terminalFontSize
            )
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }

            AgentSettingsView()
                .tabItem {
                    Label("Agents", systemImage: "cpu")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Binding var autoRefreshWorktrees: Bool
    @Binding var detachOnClose: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Auto-refresh worktrees on repo open", isOn: $autoRefreshWorktrees)

                Toggle("Detach from Zellij on tab close (preserve session)", isOn: $detachOnClose)
            }

            Section {
                LabeledContent("Data Location") {
                    Text("~/.agentstudio/")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Reveal in Finder") {
                    let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".agentstudio")
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Terminal Settings

struct TerminalSettingsView: View {
    @Binding var fontSize: Double

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Font Size") {
                    HStack {
                        Slider(value: $fontSize, in: 10...24, step: 1)
                            .frame(width: 150)

                        Text("\(Int(fontSize)) pt")
                            .frame(width: 50, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Zellij") {
                LabeledContent("Config Location") {
                    Text("~/.config/zellij/")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }

                Button("Open Zellij Config") {
                    let url = FileManager.default.homeDirectoryForCurrentUser
                        .appending(path: ".config/zellij")
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Agent Settings

struct AgentSettingsView: View {
    var body: some View {
        Form {
            Section("Installed Agents") {
                ForEach(AgentType.allCases, id: \.self) { agent in
                    HStack {
                        Circle()
                            .fill(agent.color)
                            .frame(width: 8, height: 8)

                        Text(agent.displayName)

                        Spacer()

                        if isAgentInstalled(agent) {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("Not Found", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }

            Section {
                Text("Agents are discovered from your PATH. Install them using their respective installers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func isAgentInstalled(_ agent: AgentType) -> Bool {
        guard agent != .custom else { return true }

        let searchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin"
        ]

        for path in searchPaths {
            let fullPath = "\(path)/\(agent.command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return true
            }
        }

        return false
    }
}
