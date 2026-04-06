import SwiftUI

struct SettingsView: View {
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 13
    @AppStorage("autoRefreshWorktrees") private var autoRefreshWorktrees: Bool = true
    @AppStorage("detachOnClose") private var detachOnClose: Bool = true
    @AppStorage("backgroundRestorePolicy") private var backgroundRestorePolicyRawValue: String =
        BackgroundRestorePolicy.existingSessionsOnly.rawValue

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
                fontSize: $terminalFontSize,
                backgroundRestorePolicyRawValue: $backgroundRestorePolicyRawValue
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
                    Text(AppDataPaths.displayPath(for: AppDataPaths.rootDirectory()))
                        .foregroundStyle(.secondary)
                        .font(.system(size: AppStyle.textBase, design: .monospaced))
                }

                Button(LocalActionPresentation.revealDataLocationInFinder.presentation.label) {
                    let url = AppDataPaths.rootDirectory()
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
                .help(LocalActionPresentation.revealDataLocationInFinder.presentation.helpText)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Terminal Settings

struct TerminalSettingsView: View {
    @Binding var fontSize: Double
    @Binding var backgroundRestorePolicyRawValue: String

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

            Section("Restore") {
                Picker(
                    "Background Restore",
                    selection: $backgroundRestorePolicyRawValue
                ) {
                    Text("Off").tag(BackgroundRestorePolicy.off.rawValue)
                    Text("Existing Sessions Only").tag(BackgroundRestorePolicy.existingSessionsOnly.rawValue)
                    Text("All Terminal Panes").tag(BackgroundRestorePolicy.allTerminalPanes.rawValue)
                }
                .pickerStyle(.menu)

                Text("Default restores hidden panes only when they already have an existing zmx session.")
                    .font(.system(size: AppStyle.textXs))
                    .foregroundStyle(.secondary)
            }

            Section("Zellij") {
                LabeledContent("Config Location") {
                    Text("~/.config/zellij/")
                        .foregroundStyle(.secondary)
                        .font(.system(size: AppStyle.textBase, design: .monospaced))
                }

                Button(LocalActionPresentation.openZellijConfig.presentation.label) {
                    let url = FileManager.default.homeDirectoryForCurrentUser
                        .appending(path: ".config/zellij")
                    NSWorkspace.shared.open(url)
                }
                .help(LocalActionPresentation.openZellijConfig.presentation.helpText)
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
                            Button(LocalActionPresentation.cancel.presentation.label) {
                                isAddingFavorite = false
                                newFavoriteURL = ""
                                newFavoriteTitle = ""
                            }
                            Button(LocalActionPresentation.add.presentation.label) {
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
                    Button(LocalActionPresentation.addFavorite.presentation.label) {
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

                    Button(LocalActionPresentation.clearAllHistory.presentation.label) {
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
