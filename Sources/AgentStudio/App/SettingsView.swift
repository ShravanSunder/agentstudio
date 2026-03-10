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

            WebviewSettingsView()
                .tabItem {
                    Label("Webview", systemImage: "globe")
                }
        }
        .frame(width: 450, height: 380)
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
                        .font(.system(size: AppStyle.textBase, design: .monospaced))
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
                        .font(.system(size: AppStyle.textBase, design: .monospaced))
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

// MARK: - Webview Settings

struct WebviewSettingsView: View {
    @State private var newFavoriteURL: String = ""
    @State private var newFavoriteTitle: String = ""
    @State private var isAddingFavorite = false

    private var history: URLHistoryService { .shared }

    var body: some View {
        Form {
            Section("Favorites") {
                ForEach(history.favorites) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.system(size: AppStyle.textSm))
                            Text(entry.url.absoluteString)
                                .font(.system(size: AppStyle.textXs))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button {
                            history.removeFavorite(url: entry.url)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: AppStyle.textXs))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isAddingFavorite {
                    VStack(spacing: 6) {
                        TextField("Title", text: $newFavoriteTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: AppStyle.textSm))

                        TextField("URL (e.g. https://example.com)", text: $newFavoriteURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: AppStyle.textSm))

                        HStack {
                            Spacer()
                            Button("Cancel") {
                                isAddingFavorite = false
                                newFavoriteURL = ""
                                newFavoriteTitle = ""
                            }
                            Button("Add") {
                                let normalized = WebviewPaneController.normalizeURLString(newFavoriteURL)
                                if let url = URL(string: normalized) {
                                    history.addFavorite(url: url, title: newFavoriteTitle)
                                }
                                isAddingFavorite = false
                                newFavoriteURL = ""
                                newFavoriteTitle = ""
                            }
                            .disabled(newFavoriteURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Button("Add Favorite") {
                        isAddingFavorite = true
                    }
                }
            }

            Section("History") {
                Text("History older than 2 weeks is automatically removed.")
                    .font(.system(size: AppStyle.textXs))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(history.entries.count) entries")
                        .font(.system(size: AppStyle.textXs))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Clear All History") {
                        history.clearHistory()
                    }
                    .disabled(history.entries.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
