import AppKit
import Foundation

struct ExternalEditorTarget: Equatable, Identifiable {
    enum Resolution: Equatable {
        case resolved(ExternalEditorTarget)
        case bookmarkedEditorNotInstalled
        case noDefaultAvailable
    }

    struct CommandRequest: Equatable {
        let executableURL: URL
        let arguments: [String]
    }

    let id: EditorTargetId
    let title: String
    let bundleIdentifier: String
    let cliFallbacks: [CommandRequest]

    static let cursor = Self(
        id: "cursor",
        title: "Cursor",
        bundleIdentifier: "com.todesktop.230313mzl4w4u92",
        cliFallbacks: [
            .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["cursor", "--reuse-window"]
            )
        ]
    )

    static let vscode = Self(
        id: "vscode",
        title: "VS Code",
        bundleIdentifier: "com.microsoft.VSCode",
        cliFallbacks: [
            .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["code", "--reuse-window"]
            )
        ]
    )

    static let windsurf = Self(
        id: "windsurf",
        title: "Windsurf",
        bundleIdentifier: "com.exafunction.windsurf",
        cliFallbacks: []
    )

    static let antigravity = Self(
        id: "antigravity",
        title: "Antigravity",
        bundleIdentifier: "com.google.antigravity",
        cliFallbacks: []
    )

    static let xcode = Self(
        id: "xcode",
        title: "Xcode",
        bundleIdentifier: "com.apple.dt.Xcode",
        cliFallbacks: []
    )

    static let zed = Self(
        id: "zed",
        title: "Zed",
        bundleIdentifier: "dev.zed.Zed",
        cliFallbacks: []
    )

    static let curatedOrder: [Self] = [
        .cursor,
        .vscode,
        .windsurf,
        .antigravity,
        .xcode,
        .zed,
    ]

    @MainActor
    static func refreshInstalledTargets(
        isInstalled: (String) -> Bool = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        }
    ) -> [Self] {
        curatedOrder.filter { target in
            isInstalled(target.bundleIdentifier)
        }
    }

    static func resolveBookmarkedOrDefault(
        bookmarkedEditorId: EditorTargetId?,
        installedTargets: [Self]
    ) -> Resolution {
        if let bookmarkedEditorId {
            guard let target = installedTargets.first(where: { $0.id == bookmarkedEditorId }) else {
                return .bookmarkedEditorNotInstalled
            }
            return .resolved(target)
        }

        let cursorTarget = installedTargets.first { $0.id == cursor.id }
        let vscodeTarget = installedTargets.first { $0.id == vscode.id }
        if let target = cursorTarget ?? vscodeTarget {
            return .resolved(target)
        }
        return .noDefaultAvailable
    }

    @MainActor
    var iconImage: NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}
