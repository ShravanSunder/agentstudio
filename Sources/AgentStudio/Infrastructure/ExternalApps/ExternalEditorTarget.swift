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
    let appIcon: NSImage?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.cliFallbacks == rhs.cliFallbacks
    }

    static let cursor = Self(
        id: "cursor",
        title: "Cursor",
        bundleIdentifier: "com.todesktop.230313mzl4w4u92",
        cliFallbacks: [
            .init(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["cursor", "--reuse-window"]
            )
        ],
        appIcon: nil
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
        ],
        appIcon: nil
    )

    static let windsurf = Self(
        id: "windsurf",
        title: "Windsurf",
        bundleIdentifier: "com.exafunction.windsurf",
        cliFallbacks: [],
        appIcon: nil
    )

    static let antigravity = Self(
        id: "antigravity",
        title: "Antigravity",
        bundleIdentifier: "com.google.antigravity",
        cliFallbacks: [],
        appIcon: nil
    )

    static let xcode = Self(
        id: "xcode",
        title: "Xcode",
        bundleIdentifier: "com.apple.dt.Xcode",
        cliFallbacks: [],
        appIcon: nil
    )

    static let zed = Self(
        id: "zed",
        title: "Zed",
        bundleIdentifier: "dev.zed.Zed",
        cliFallbacks: [],
        appIcon: nil
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
        resolveApplicationURL: (String) -> URL? = { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }
    ) -> [Self] {
        curatedOrder.compactMap { target in
            guard let appURL = resolveApplicationURL(target.bundleIdentifier) else {
                return nil
            }

            return Self(
                id: target.id,
                title: target.title,
                bundleIdentifier: target.bundleIdentifier,
                cliFallbacks: target.cliFallbacks,
                appIcon: NSWorkspace.shared.icon(forFile: appURL.path)
            )
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
}
