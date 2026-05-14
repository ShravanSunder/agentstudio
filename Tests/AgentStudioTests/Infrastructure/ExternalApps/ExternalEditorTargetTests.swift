import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ExternalEditorTargetTests {
    @Test
    func installedTargets_preserveCuratedOrder() {
        let installedBundleIds: Set<String> = [
            ExternalEditorTarget.cursor.bundleIdentifier,
            ExternalEditorTarget.antigravity.bundleIdentifier,
            ExternalEditorTarget.xcode.bundleIdentifier,
        ]

        let targets = ExternalEditorTarget.refreshInstalledTargets { bundleIdentifier in
            guard installedBundleIds.contains(bundleIdentifier) else { return nil }
            return URL(fileURLWithPath: "/Applications/\(bundleIdentifier).app")
        }

        #expect(targets.map(\.id) == ["cursor", "antigravity", "xcode"])
    }

    @Test
    func resolveBookmarkedOrDefault_usesExplicitBookmarkWhenInstalled() {
        let targets: [ExternalEditorTarget] = [.windsurf, .vscode]

        let resolved = ExternalEditorTarget.resolveBookmarkedOrDefault(
            bookmarkedEditorId: "vscode",
            installedTargets: targets
        )

        if case .resolved(let target) = resolved {
            #expect(target.id == "vscode")
        } else {
            Issue.record("Expected explicit bookmark resolution")
        }
    }

    @Test
    func resolveBookmarkedOrDefault_reportsMissingBookmarkWhenBookmarkIsMissing() {
        let targets: [ExternalEditorTarget] = [.windsurf, .xcode]

        let resolved = ExternalEditorTarget.resolveBookmarkedOrDefault(
            bookmarkedEditorId: "cursor",
            installedTargets: targets
        )

        #expect(resolved == .bookmarkedEditorNotInstalled)
    }

    @Test
    func resolveBookmarkedOrDefault_withoutBookmark_prefersCursorThenVSCode() {
        let cursorPreferred: [ExternalEditorTarget] = [.windsurf, .cursor, .xcode]
        let vscodePreferred: [ExternalEditorTarget] = [.windsurf, .vscode, .xcode]
        let noDefault: [ExternalEditorTarget] = [.windsurf, .xcode]

        let cursorResolved = ExternalEditorTarget.resolveBookmarkedOrDefault(
            bookmarkedEditorId: nil,
            installedTargets: cursorPreferred
        )
        let vscodeResolved = ExternalEditorTarget.resolveBookmarkedOrDefault(
            bookmarkedEditorId: nil,
            installedTargets: vscodePreferred
        )
        let noDefaultResolved = ExternalEditorTarget.resolveBookmarkedOrDefault(
            bookmarkedEditorId: nil,
            installedTargets: noDefault
        )

        if case .resolved(let target) = cursorResolved {
            #expect(target.id == "cursor")
        } else {
            Issue.record("Expected Cursor default resolution")
        }
        if case .resolved(let target) = vscodeResolved {
            #expect(target.id == "vscode")
        } else {
            Issue.record("Expected VS Code default resolution")
        }
        #expect(noDefaultResolved == .noDefaultAvailable)
    }
}
