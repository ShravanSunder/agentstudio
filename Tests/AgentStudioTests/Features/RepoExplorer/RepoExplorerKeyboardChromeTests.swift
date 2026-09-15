import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("Repo Explorer keyboard row chrome", .serialized)
struct RepoExplorerKeyboardChromeTests {
    private struct SpaceChipCapture {
        let width: CGFloat
        let artifactDirectory: URL
        let associatedCell: RepoExplorerTableRowCell
        let associatedRowRect: NSRect
        let associatedBitmap: NSBitmapImageRep
        let unassociatedCell: RepoExplorerTableRowCell
        let unassociatedRowRect: NSRect
        let unassociatedBitmap: NSBitmapImageRep
    }

    @Test("keyboard paint retains row bindings and native layout while updating selected rows")
    func keyboardPaintPreservesContentAndLayout() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let tabID = UUIDv7.generate()
        let paneIDs = [UUIDv7.generate(), UUIDv7.generate()]
        let snapshot = navigationSnapshot(paneIDs.map { .unassociatedPane(paneID: $0, tabID: tabID) })
        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        let table = try #require(firstRepoExplorerKeyboardDescendant(NSTableView.self, in: fixture.host))
        let firstCell = try #require(
            table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )
        let secondCell = try #require(
            table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )
        let firstBinding = firstCell.currentBindingIdentity
        let secondBinding = secondCell.currentBindingIdentity
        let nativeApplyCount = fixture.materializer.nativeTransactionApplyCount
        let layoutPassCount = fixture.materializer.forcedLayoutPassCount
        let frameUpdateCount = fixture.materializer.tableFrameUpdateCount

        fixture.materializer.setShowsKeyboardHints(true)
        #expect(firstCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "1")
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "2")
        try fixture.send(.moveSelectionDown)

        #expect(!firstCell.hostingView.rootView.slot.keyboardPresentation.isSelected)
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.isSelected)
        #expect(table.selectedRow == 1)
        #expect(fixture.window.firstResponder === fixture.host)
        #expect(firstCell.currentBindingIdentity == firstBinding)
        #expect(secondCell.currentBindingIdentity == secondBinding)
        #expect(fixture.materializer.nativeTransactionApplyCount == nativeApplyCount)
        #expect(fixture.materializer.forcedLayoutPassCount == layoutPassCount)
        #expect(fixture.materializer.tableFrameUpdateCount == frameUpdateCount)
        #expect(fixture.recorder.focusedPaneIDs.isEmpty)
        #expect(fixture.recorder.commandRequests.isEmpty)

        fixture.materializer.setShowsKeyboardHints(false)
        #expect(firstCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay == nil)
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay == nil)
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.isSelected)
        #expect(table.selectionHighlightStyle == .none)
    }

    @Test("pane rows always carry Space independently from conditional numbered hints")
    func paneRowsAlwaysCarrySpaceIndependentlyFromConditionalNumberedHints() throws {
        let fixture = RepoExplorerListKeyboardFixture()
        defer { fixture.close() }
        let tabID = UUIDv7.generate()
        let paneIDs = [UUIDv7.generate(), UUIDv7.generate()]
        let snapshot = navigationSnapshot(paneIDs.map { .unassociatedPane(paneID: $0, tabID: tabID) })
        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        let table = try #require(firstRepoExplorerKeyboardDescendant(NSTableView.self, in: fixture.host))
        let firstCell = try #require(
            table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )
        let secondCell = try #require(
            table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )

        #expect(firstCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay == nil)
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay == nil)
        #expect(LocalActionSpec.previewPaneShortcutDisplay.value == "Space")

        fixture.materializer.setShowsKeyboardHints(true)
        #expect(firstCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "1")
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "2")
    }

    @Test("always-visible first Space chip preserves pane rows at supported widths")
    func alwaysVisibleFirstSpaceChipPreservesPaneRowsAtSupportedWidths() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../..")
            .standardizedFileURL
        let artifactDirectory = projectRoot.appending(
            path: "tmp/sidekick-work/s4-fit",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: artifactDirectory,
            withIntermediateDirectories: true
        )

        for width in [CGFloat(250), CGFloat(320)] {
            try verifySpaceChipLayout(at: width, artifactDirectory: artifactDirectory)
        }
    }

    private func verifySpaceChipLayout(at width: CGFloat, artifactDirectory: URL) throws {
        let fixture = RepoExplorerListKeyboardFixture(windowWidth: width)
        defer { fixture.close() }
        let tabID = UUIDv7.generate()
        let richPaneID = UUIDv7.generate()
        let richRow = navigationRichPaneRow(paneID: richPaneID, tabID: tabID)
        let inactiveRow = navigationUnassociatedPaneRow(paneID: UUIDv7.generate(), tabID: tabID)
        let snapshot = RepoExplorerMaterializationSnapshot(rows: [richRow, inactiveRow])
        _ = try fixture.apply(snapshot: snapshot, generation: 1)
        let table = try #require(firstRepoExplorerKeyboardDescendant(NSTableView.self, in: fixture.host))
        let associatedCell = try #require(
            table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )
        let unassociatedCell = try #require(
            table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )

        _ = fixture.materializer.applySelection(rowID: richRow.id, scrollIntoView: false)
        fixture.materializer.setShowsKeyboardHints(false)
        fixture.window.layoutIfNeeded()
        table.layoutSubtreeIfNeeded()
        let associatedBaselineHeight = associatedCell.frame.height
        let unassociatedBaselineHeight = unassociatedCell.frame.height

        fixture.materializer.setShowsKeyboardHints(true)
        fixture.window.layoutIfNeeded()
        table.layoutSubtreeIfNeeded()
        let associatedBitmap = try captureBitmap(in: associatedCell.hostingView)
        let unassociatedBitmap = try captureBitmap(in: unassociatedCell.hostingView)
        let associatedRowRect = table.rect(ofRow: 0)
        let unassociatedRowRect = table.rect(ofRow: 1)

        #expect(associatedCell.frame.height == associatedBaselineHeight)
        #expect(unassociatedCell.frame.height == unassociatedBaselineHeight)
        #expect(associatedRowRect.height == associatedBaselineHeight)
        #expect(unassociatedRowRect.height == unassociatedBaselineHeight)
        #expect(associatedCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "1")
        #expect(unassociatedCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "2")
        try writeSpaceChipArtifacts(
            SpaceChipCapture(
                width: width,
                artifactDirectory: artifactDirectory,
                associatedCell: associatedCell,
                associatedRowRect: associatedRowRect,
                associatedBitmap: associatedBitmap,
                unassociatedCell: unassociatedCell,
                unassociatedRowRect: unassociatedRowRect,
                unassociatedBitmap: unassociatedBitmap
            ))
        if width == 250 {
            try expectCapturedLeadingEdgePreserved(
                at: artifactDirectory.appending(path: "pane-row-250-associated-space-first.png")
            )
        }
        try clickFirstChip(in: table, rowRect: associatedRowRect, window: fixture.window)
        #expect(fixture.recorder.focusedPaneIDs == [richPaneID])
    }

    private func writeSpaceChipArtifacts(_ capture: SpaceChipCapture) throws {
        try writeBitmap(
            capture.associatedBitmap,
            to: capture.artifactDirectory.appending(
                path: "pane-row-\(Int(capture.width))-associated-space-first.png")
        )
        try writeBitmap(
            capture.unassociatedBitmap,
            to: capture.artifactDirectory.appending(
                path: "pane-row-\(Int(capture.width))-unassociated-space-first.png")
        )
        let spaceHintHost = NSHostingView(
            rootView: SidebarShortcutHint(LocalActionSpec.previewPaneShortcutDisplay)
        )
        let bounds = """
            width=\(Int(capture.width))
            associatedCellFrame=\(NSStringFromRect(capture.associatedCell.frame))
            associatedHostingFrame=\(NSStringFromRect(capture.associatedCell.hostingView.frame))
            associatedHostingFittingSize=\(NSStringFromSize(capture.associatedCell.hostingView.fittingSize))
            associatedRowRect=\(NSStringFromRect(capture.associatedRowRect))
            associatedPixels=\(capture.associatedBitmap.pixelsWide)x\(capture.associatedBitmap.pixelsHigh)
            unassociatedCellFrame=\(NSStringFromRect(capture.unassociatedCell.frame))
            unassociatedHostingFrame=\(NSStringFromRect(capture.unassociatedCell.hostingView.frame))
            unassociatedHostingFittingSize=\(NSStringFromSize(capture.unassociatedCell.hostingView.fittingSize))
            unassociatedRowRect=\(NSStringFromRect(capture.unassociatedRowRect))
            unassociatedPixels=\(capture.unassociatedBitmap.pixelsWide)x\(capture.unassociatedBitmap.pixelsHigh)
            spaceHintFittingSize=\(NSStringFromSize(spaceHintHost.fittingSize))
            """
        try bounds.write(
            to: capture.artifactDirectory.appending(path: "pane-row-\(Int(capture.width))-bounds.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func clickFirstChip(in table: NSTableView, rowRect: NSRect, window: NSWindow) throws {
        window.makeKeyAndOrderFront(nil)
        let clickLocation = table.convert(
            NSPoint(
                x: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth
                    + AppStyles.Shell.Sidebar.groupIconTitleSpacing + 8,
                y: rowRect.midY
            ),
            to: nil
        )
        let mouseDown = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: clickLocation,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
        let mouseUp = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: clickLocation,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0
            )
        )
        window.sendEvent(mouseDown)
        window.sendEvent(mouseUp)
    }

    private func captureBitmap(in view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func pixelColorDifference(_ first: NSColor, _ second: NSColor) -> CGFloat {
        abs(first.redComponent - second.redComponent)
            + abs(first.greenComponent - second.greenComponent)
            + abs(first.blueComponent - second.blueComponent)
            + abs(first.alphaComponent - second.alphaComponent)
    }

    private func expectCapturedLeadingEdgePreserved(at artifactURL: URL) throws {
        let data = try Data(contentsOf: artifactURL)
        let capturedBitmap = try #require(NSBitmapImageRep(data: data))
        let verticalMidpoint = capturedBitmap.pixelsHigh / 2
        let transparentOuterEdge = try #require(
            capturedBitmap.colorAt(x: 0, y: verticalMidpoint)?.usingColorSpace(.deviceRGB)
        )
        let selectedRowInterior = try #require(
            capturedBitmap.colorAt(x: 100, y: verticalMidpoint)?.usingColorSpace(.deviceRGB)
        )
        #expect(pixelColorDifference(transparentOuterEdge, selectedRowInterior) > 0.1)
    }

    private func writeBitmap(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }
}
