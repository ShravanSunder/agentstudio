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

    @Test("pane rows omit Space while retaining conditional numbered hints")
    func paneRowsOmitSpaceWhileRetainingConditionalNumberedHints() throws {
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
        fixture.materializer.setShowsKeyboardHints(true)
        #expect(firstCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "1")
        #expect(secondCell.hostingView.rootView.slot.keyboardPresentation.shortcutDisplay?.value == "2")
    }

    @Test("pane and worktree rows omit Space while retaining trailing number stamps")
    func paneAndWorktreeRowsOmitSpaceWhileRetainingTrailingNumberStamps() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../..")
            .standardizedFileURL
        let paneRowSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift"
            ),
            encoding: .utf8
        )
        let worktreeRowSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift"
            ),
            encoding: .utf8
        )

        #expect(paneRowSource.components(separatedBy: "RepoExplorerPaneRowContent(").count - 1 == 2)
        #expect(!paneRowSource.contains("SidebarShortcutHint(LocalActionSpec.previewPaneShortcutDisplay)"))
        #expect(!worktreeRowSource.contains("LocalActionSpec.previewPaneShortcutDisplay"))
        #expect(worktreeRowSource.contains(".sidebarShortcutHint("))
        #expect(worktreeRowSource.contains("alignment: .trailing"))
    }

    @Test("pane rows preserve numbered hints and recency at supported widths")
    func paneRowsPreserveNumberedHintsAndRecencyAtSupportedWidths() throws {
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
            try verifyNumberStampLayout(at: width, artifactDirectory: artifactDirectory)
        }
    }

    @Test("trailing number overlay replaces and restores the pinned row action without reflow")
    func worktreeNumberOverlayDisablesAndRestoresPinnedAction() throws {
        for width in [CGFloat(250), CGFloat(320)] {
            try verifyWorktreeNumberOverlay(at: width)
        }
    }

    private func verifyWorktreeNumberOverlay(at width: CGFloat) throws {
        let fixture = RepoExplorerListKeyboardFixture(windowWidth: width)
        defer { fixture.close() }
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let row = navigationWorktreeRow(
            groupID: "repo",
            repositoryID: repositoryID,
            worktreeID: worktreeID
        )
        _ = try fixture.apply(
            snapshot: RepoExplorerMaterializationSnapshot(rows: [row]),
            generation: 1
        )
        let table = try #require(firstRepoExplorerKeyboardDescendant(NSTableView.self, in: fixture.host))
        let cell = try #require(
            table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? RepoExplorerTableRowCell
        )
        let pinDisposition = try fixture.enablePinPresentation(
            repositoryID: repositoryID,
            worktreeID: worktreeID
        )
        guard case .accepted(let reboundRowCount) = pinDisposition else {
            Issue.record("Current mounted row must accept pin command presentation")
            return
        }
        #expect(reboundRowCount == 1)
        fixture.window.makeKeyAndOrderFront(nil)
        fixture.window.layoutIfNeeded()
        table.layoutSubtreeIfNeeded()
        let baselineCellHeight = cell.frame.height
        let baselineFittingSize = cell.hostingView.fittingSize
        try verifyPinnedActionReplacement(
            at: width,
            repositoryID: repositoryID,
            worktreeID: worktreeID
        )

        fixture.materializer.setShowsKeyboardHints(true)
        fixture.window.layoutIfNeeded()
        table.layoutSubtreeIfNeeded()
        let bitmap = try captureBitmap(in: cell.hostingView)
        try writeBitmap(
            bitmap,
            to: URL(fileURLWithPath: "tmp/sidekick-work/worktree-overlay-\(Int(width)).png")
        )
        let shortcutGlyphBounds = try #require(trailingDarkGlyphBounds(in: bitmap))
        let titleGlyphBounds = try #require(primaryTitleGlyphBounds(in: bitmap))

        #expect(cell.frame.height == baselineCellHeight)
        #expect(cell.hostingView.fittingSize == baselineFittingSize)
        #expect(abs(shortcutGlyphBounds.midY - titleGlyphBounds.midY) <= 4)
        #expect(shortcutGlyphBounds.maxX <= CGFloat(bitmap.pixelsWide))
    }

    private func verifyPinnedActionReplacement(
        at width: CGFloat,
        repositoryID: UUID,
        worktreeID: UUID
    ) throws {
        let pinRequest = try #require(
            RepoExplorerWorktreeCommandPresentation.requests(
                worktreeId: worktreeID,
                repoId: repositoryID,
                isPinned: false,
                showsPinnedControl: true
            ).first { $0.command == .pinRepo && $0.surface == .inlineControl }
        )
        let pinPresentation = try #require(
            RepoExplorerCommandPresentation.presentedCommand(
                for: pinRequest,
                snapshot: RepoExplorerCommandPresentationSnapshot(
                    generation: 1,
                    results: [pinRequest: true]
                )
            )
        )
        var pinPressCount = 0
        let pinHost = NSHostingView(
            rootView: worktreeRowContent(
                pinPresentation: pinPresentation,
                shortcutDisplay: nil,
                onTogglePinned: { pinPressCount += 1 }
            )
        )
        pinHost.frame = NSRect(x: 0, y: 0, width: width, height: 80)
        let pinWindow = NSWindow(
            contentRect: pinHost.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        pinWindow.isReleasedWhenClosed = false
        pinWindow.contentView = pinHost
        pinWindow.makeKeyAndOrderFront(nil)
        defer {
            pinWindow.orderOut(nil)
            pinWindow.close()
        }
        pinHost.layoutSubtreeIfNeeded()
        pinHost.frame.size.height = pinHost.fittingSize.height
        pinWindow.setContentSize(pinHost.frame.size)
        pinHost.layoutSubtreeIfNeeded()
        let pinBitmap = try captureBitmap(in: pinHost)
        let pinGlyphBounds = try #require(trailingRenderedBounds(in: pinBitmap))
        let pinPixelScale = CGFloat(pinBitmap.pixelsWide) / pinHost.bounds.width
        let pinControlPoint = NSPoint(
            x: pinGlyphBounds.midX / pinPixelScale,
            y: pinGlyphBounds.midY / pinPixelScale
        )
        try click(pinControlPoint, in: pinHost, window: pinWindow)
        #expect(pinPressCount == 1)
        pinHost.rootView = worktreeRowContent(
            pinPresentation: pinPresentation,
            shortcutDisplay: ShortcutDisplayText(value: "1"),
            onTogglePinned: { pinPressCount += 1 }
        )
        pinHost.layoutSubtreeIfNeeded()
        #expect(
            SidebarTrailingActionVisibility(shortcutDisplay: ShortcutDisplayText(value: "1"))
                .accessibilityHidden
        )
        try click(pinControlPoint, in: pinHost, window: pinWindow)
        #expect(pinPressCount == 1)

        pinHost.rootView = worktreeRowContent(
            pinPresentation: pinPresentation,
            shortcutDisplay: nil,
            onTogglePinned: { pinPressCount += 1 }
        )
        pinHost.layoutSubtreeIfNeeded()
        #expect(!SidebarTrailingActionVisibility(shortcutDisplay: nil).accessibilityHidden)
        try click(pinControlPoint, in: pinHost, window: pinWindow)
        #expect(pinPressCount == 2)
    }

    private func worktreeRowContent(
        pinPresentation: RepoExplorerPresentedCommand,
        shortcutDisplay: ShortcutDisplayText?,
        onTogglePinned: @escaping () -> Void
    ) -> RepoExplorerWorktreeRowContent {
        RepoExplorerWorktreeRowContent(
            octiconLoader: makeRepoExplorerTestOcticonLoader(),
            checkoutTitle: "A deliberately long repository title proving the trailing slot",
            branchName: "main",
            checkoutIconKind: .mainCheckout,
            iconColor: .accentColor,
            branchStatus: .unknown,
            showsPinnedControl: true,
            pinnedCommandPresentation: pinPresentation,
            onTogglePinned: onTogglePinned,
            shortcutDisplay: shortcutDisplay
        )
    }

    private func verifyNumberStampLayout(at width: CGFloat, artifactDirectory: URL) throws {
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
        let associatedBaselineFittingSize = associatedCell.hostingView.fittingSize
        let unassociatedBaselineFittingSize = unassociatedCell.hostingView.fittingSize

        fixture.materializer.setShowsKeyboardHints(true)
        fixture.window.layoutIfNeeded()
        table.layoutSubtreeIfNeeded()
        let associatedBitmap = try captureBitmap(in: associatedCell.hostingView)
        let unassociatedBitmap = try captureBitmap(in: unassociatedCell.hostingView)
        let associatedRowRect = table.rect(ofRow: 0)
        let unassociatedRowRect = table.rect(ofRow: 1)

        #expect(associatedCell.frame.height == associatedBaselineHeight)
        #expect(unassociatedCell.frame.height == unassociatedBaselineHeight)
        #expect(associatedCell.hostingView.fittingSize == associatedBaselineFittingSize)
        #expect(unassociatedCell.hostingView.fittingSize == unassociatedBaselineFittingSize)
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

    private func trailingDarkGlyphBounds(in bitmap: NSBitmapImageRep) -> CGRect? {
        var bounds: CGRect?
        let xStart = max(0, bitmap.pixelsWide - 112)
        for y in 0..<bitmap.pixelsHigh {
            for x in xStart..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.redComponent < 0.8,
                    color.greenComponent < 0.8,
                    color.blueComponent < 0.8,
                    color.alphaComponent > 0.5
                else { continue }
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return bounds
    }

    private func trailingRenderedBounds(in bitmap: NSBitmapImageRep) -> CGRect? {
        var bounds: CGRect?
        let xStart = max(0, bitmap.pixelsWide - 56)
        for y in 0..<bitmap.pixelsHigh {
            for x in xStart..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.2 else {
                    continue
                }
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return bounds
    }

    private func primaryTitleGlyphBounds(in bitmap: NSBitmapImageRep) -> CGRect? {
        var bounds: CGRect?
        let xStart = min(bitmap.pixelsWide, 72)
        let xEnd = max(xStart, bitmap.pixelsWide - 112)
        for y in 0..<(bitmap.pixelsHigh / 2) {
            for x in xStart..<xEnd {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                    color.redComponent > 0.8,
                    color.greenComponent > 0.8,
                    color.blueComponent > 0.8,
                    color.alphaComponent > 0.5
                else { continue }
                let pixel = CGRect(x: x, y: y, width: 1, height: 1)
                bounds = bounds.map { $0.union(pixel) } ?? pixel
            }
        }
        return bounds
    }

    private func click(_ point: NSPoint, in view: NSView, window: NSWindow) throws {
        let windowPoint = view.convert(point, to: nil)
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(
                try #require(
                    NSEvent.mouseEvent(
                        with: eventType,
                        location: windowPoint,
                        modifierFlags: [],
                        timestamp: 0,
                        windowNumber: window.windowNumber,
                        context: nil,
                        eventNumber: eventType == .leftMouseDown ? 1 : 2,
                        clickCount: 1,
                        pressure: eventType == .leftMouseDown ? 1 : 0
                    )
                )
            )
        }
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
