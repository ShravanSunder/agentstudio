import AppKit
import SwiftUI
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer pane chip overflow", .serialized)
struct RepoExplorerPaneChipOverflowTests {
    @Test("the row drops sync before changes as the available width shrinks")
    func detailLevelsKeepRequiredChips() throws {
        #expect(RepoExplorerPaneChipDetailLevel.full.showsSync)
        #expect(RepoExplorerPaneChipDetailLevel.full.showsChanges)
        #expect(!RepoExplorerPaneChipDetailLevel.withoutSync.showsSync)
        #expect(RepoExplorerPaneChipDetailLevel.withoutSync.showsChanges)
        #expect(!RepoExplorerPaneChipDetailLevel.summaryOnly.showsSync)
        #expect(!RepoExplorerPaneChipDetailLevel.summaryOnly.showsChanges)

        let wide = try renderedColor(at: 350)
        let middle = try renderedColor(at: 250)
        let narrow = try renderedColor(at: 150)
        #expect(wide.redComponent > wide.greenComponent + 0.3)
        #expect(middle.greenComponent > middle.redComponent + 0.3)
        #expect(narrow.blueComponent > narrow.redComponent + 0.3)
    }

    private func renderedColor(at width: CGFloat) throws -> NSColor {
        let view = RepoExplorerPaneChipOverflow { level in
            Rectangle()
                .fill(color(for: level))
                .frame(width: requiredWidth(for: level), height: 20)
        }
        .frame(width: width, height: 20, alignment: .leading)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 20)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.colorAt(x: 5, y: 10)?.usingColorSpace(.deviceRGB))
    }

    private func requiredWidth(for level: RepoExplorerPaneChipDetailLevel) -> CGFloat {
        switch level {
        case .full: 300
        case .withoutSync: 200
        case .summaryOnly: 100
        }
    }

    private func color(for level: RepoExplorerPaneChipDetailLevel) -> Color {
        switch level {
        case .full: Color(nsColor: .systemRed)
        case .withoutSync: Color(nsColor: .systemGreen)
        case .summaryOnly: Color(nsColor: .systemBlue)
        }
    }
}
