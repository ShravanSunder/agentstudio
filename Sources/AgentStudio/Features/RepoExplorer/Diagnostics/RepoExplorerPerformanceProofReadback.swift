import AppKit
import Foundation

package struct RepoExplorerNativeVisibleProjectionReadback: Equatable, Sendable {
    package let materializationGeneration: UInt64
    package let materializationFingerprint: UInt64
    package let expectedVisibleFingerprint: UInt64
    package let actualVisibleFingerprint: UInt64
    package let visibleRowCount: Int
    package let actualBoundRowCount: Int

    package static func matching(
        materializationGeneration: UInt64,
        materializationFingerprint: UInt64,
        visibleFingerprint: UInt64,
        visibleRowCount: Int
    ) -> Self {
        Self(
            materializationGeneration: materializationGeneration,
            materializationFingerprint: materializationFingerprint,
            expectedVisibleFingerprint: visibleFingerprint,
            actualVisibleFingerprint: visibleFingerprint,
            visibleRowCount: visibleRowCount,
            actualBoundRowCount: visibleRowCount
        )
    }

    package func matches(
        materializationGeneration: UInt64,
        materializationFingerprint: UInt64
    ) -> Bool {
        self.materializationGeneration == materializationGeneration
            && self.materializationFingerprint == materializationFingerprint
            && expectedVisibleFingerprint == actualVisibleFingerprint
            && visibleRowCount == actualBoundRowCount
            && visibleRowCount > 0
    }

    @MainActor
    package static func capture(in tableView: NSTableView) -> Self? {
        guard let stamp = ExpectedStamp(rawValue: tableView.accessibilityIdentifier()) else {
            return nil
        }
        let visibleRange = tableView.rows(in: tableView.enclosingScrollView?.documentVisibleRect ?? tableView.bounds)
        guard visibleRange.location != NSNotFound, visibleRange.length == stamp.visibleRowCount else {
            return nil
        }
        var actualLabels: [String] = []
        actualLabels.reserveCapacity(visibleRange.length)
        for rowIndex in visibleRange.location..<NSMaxRange(visibleRange) {
            guard let rowView = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false),
                let label = rowView.accessibilityLabel()
            else { continue }
            actualLabels.append(label)
        }
        return Self(
            materializationGeneration: stamp.materializationGeneration,
            materializationFingerprint: stamp.materializationFingerprint,
            expectedVisibleFingerprint: stamp.expectedVisibleFingerprint,
            actualVisibleFingerprint: fingerprint(actualLabels),
            visibleRowCount: stamp.visibleRowCount,
            actualBoundRowCount: actualLabels.count
        )
    }

    @MainActor
    static func stampExpectedVisibleProjection(
        in tableView: NSTableView,
        snapshot: RepoExplorerMaterializationSnapshot,
        materializationGeneration: UInt64
    ) {
        let visibleRange = tableView.rows(in: tableView.enclosingScrollView?.documentVisibleRect ?? tableView.bounds)
        guard visibleRange.location != NSNotFound, visibleRange.length > 0 else {
            tableView.setAccessibilityIdentifier(nil)
            return
        }
        let upperBound = min(NSMaxRange(visibleRange), snapshot.rows.count)
        guard visibleRange.location < upperBound else {
            tableView.setAccessibilityIdentifier(nil)
            return
        }
        let labels = (visibleRange.location..<upperBound).map {
            RepoExplorerMaterializedRowView.accessibilityLabel(for: snapshot.rows[$0])
        }
        let stamp = ExpectedStamp(
            materializationGeneration: materializationGeneration,
            materializationFingerprint: RepoExplorerMaterializationFingerprint.make(snapshot: snapshot).rawValue,
            expectedVisibleFingerprint: fingerprint(labels),
            visibleRowCount: labels.count
        )
        tableView.setAccessibilityIdentifier(stamp.rawValue)
    }

    private static func fingerprint(_ values: [String]) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for value in values {
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            hash ^= 0xff
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private struct ExpectedStamp {
        let materializationGeneration: UInt64
        let materializationFingerprint: UInt64
        let expectedVisibleFingerprint: UInt64
        let visibleRowCount: Int

        init(
            materializationGeneration: UInt64,
            materializationFingerprint: UInt64,
            expectedVisibleFingerprint: UInt64,
            visibleRowCount: Int
        ) {
            self.materializationGeneration = materializationGeneration
            self.materializationFingerprint = materializationFingerprint
            self.expectedVisibleFingerprint = expectedVisibleFingerprint
            self.visibleRowCount = visibleRowCount
        }

        init?(rawValue: String?) {
            guard let rawValue else { return nil }
            let fields = rawValue.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count == 5, fields[0] == "repo-explorer-proof",
                let generation = UInt64(fields[1]), let materialization = UInt64(fields[2]),
                let visible = UInt64(fields[3]), let rowCount = Int(fields[4]), rowCount > 0
            else { return nil }
            self.init(
                materializationGeneration: generation,
                materializationFingerprint: materialization,
                expectedVisibleFingerprint: visible,
                visibleRowCount: rowCount
            )
        }

        var rawValue: String {
            "repo-explorer-proof:\(materializationGeneration):\(materializationFingerprint):\(expectedVisibleFingerprint):\(visibleRowCount)"
        }
    }
}

package struct RepoExplorerPerformanceProofReadback: Equatable, Sendable {
    package enum FocusDisposition: String, Equatable, Sendable {
        case filterFocused = "filter_focused"
        case notFocused = "not_focused"
    }

    package enum AccessibilityDisposition: String, Equatable, Sendable {
        case ready
        case unavailable
    }

    package let semanticGeneration: Int
    package let acknowledgedRevision: UInt64
    package let visibleGeneration: UInt64
    package let representedRowCount: Int
    package let materializationFingerprint: UInt64
    package let inactiveRepositoryHeaderCount: Int
    package let suppressedRepositoryFactRowCount: Int
    package let updatingRepositoryHeaderCount: Int
    package let groupingMode: RepoExplorerGroupingMode
    package let query: String
    package let isDemanded: Bool
    package let presentationIsReady: Bool
    package let focusDisposition: FocusDisposition
    package let accessibilityDisposition: AccessibilityDisposition

    package init(
        semanticGeneration: Int,
        acknowledgedRevision: UInt64,
        visibleGeneration: UInt64,
        representedRowCount: Int,
        materializationFingerprint: UInt64 = 0,
        inactiveRepositoryHeaderCount: Int = 0,
        suppressedRepositoryFactRowCount: Int = 0,
        updatingRepositoryHeaderCount: Int = 0,
        groupingMode: RepoExplorerGroupingMode,
        query: String,
        isDemanded: Bool,
        presentationIsReady: Bool,
        focusDisposition: FocusDisposition,
        accessibilityDisposition: AccessibilityDisposition
    ) {
        self.semanticGeneration = semanticGeneration
        self.acknowledgedRevision = acknowledgedRevision
        self.visibleGeneration = visibleGeneration
        self.representedRowCount = representedRowCount
        self.materializationFingerprint = materializationFingerprint
        self.inactiveRepositoryHeaderCount = inactiveRepositoryHeaderCount
        self.suppressedRepositoryFactRowCount = suppressedRepositoryFactRowCount
        self.updatingRepositoryHeaderCount = updatingRepositoryHeaderCount
        self.groupingMode = groupingMode
        self.query = query
        self.isDemanded = isDemanded
        self.presentationIsReady = presentationIsReady
        self.focusDisposition = focusDisposition
        self.accessibilityDisposition = accessibilityDisposition
    }

    package var queryIsEmpty: Bool { query.isEmpty }
}
