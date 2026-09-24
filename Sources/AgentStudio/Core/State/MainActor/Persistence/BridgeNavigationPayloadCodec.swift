import Foundation

/// One persisted `local_bridge_navigation` row: the SQLite row projection of a
/// receiver's navigation record. Live atom values are never the row type.
package struct BridgeNavigationRow: Equatable, Sendable {
    package let receiver: BridgeReceiver
    package let payloadVersion: Int
    package let payloadJSON: String

    package init(receiver: BridgeReceiver, payloadVersion: Int, payloadJSON: String) {
        self.receiver = receiver
        self.payloadVersion = payloadVersion
        self.payloadJSON = payloadJSON
    }
}

package enum BridgeNavigationPayloadCodecError: Error, Equatable, Sendable {
    case unsupportedPayloadVersion(Int)
    case malformedPayload
    case invalidDocumentLocation(field: String)
    case duplicateDocumentLocation
    case duplicateMember
    case selectedDocumentNotInInventory
}

/// Versioned JSON codec between `BridgeNavigationRecord` and its row payload.
///
/// The payload holds navigation memory only — never file bodies, native
/// handles, cached readiness or the derived protected member. Decoding fails
/// closed with a field-tagged error rather than guessing; callers default only
/// the affected receiver.
package enum BridgeNavigationPayloadCodec {
    package static let currentPayloadVersion = 1

    package static func encodeRow(
        _ record: BridgeNavigationRecord,
        for receiver: BridgeReceiver
    ) throws -> BridgeNavigationRow {
        let payload = PayloadV1(record: record)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw BridgeNavigationPayloadCodecError.malformedPayload
        }
        return BridgeNavigationRow(receiver: receiver, payloadVersion: currentPayloadVersion, payloadJSON: json)
    }

    package static func decodeRecord(from row: BridgeNavigationRow) throws -> BridgeNavigationRecord {
        guard row.payloadVersion == currentPayloadVersion else {
            throw BridgeNavigationPayloadCodecError.unsupportedPayloadVersion(row.payloadVersion)
        }
        let payload: PayloadV1
        do {
            payload = try JSONDecoder().decode(PayloadV1.self, from: Data(row.payloadJSON.utf8))
        } catch {
            throw BridgeNavigationPayloadCodecError.malformedPayload
        }
        return try payload.record()
    }

    // MARK: - Payload v1

    private struct PayloadV1: Codable {
        struct OpenedDocument: Codable {
            let canonicalPath: String
            let provenance: Provenance?
        }

        struct Provenance: Codable {
            let repoId: UUID
            let worktreeId: UUID
            let relativePath: String
        }

        struct FilesFilter: Codable {
            enum Kind: String, Codable {
                case allMembers
                case member
                case openedDocuments
            }

            let kind: Kind
            let worktreeId: UUID?
        }

        struct ReviewSelection: Codable {
            enum Kind: String, Codable {
                case unselected
                case member
                case importedUnavailable
            }

            let kind: Kind
            let worktreeId: UUID?
            let importedVariant: BridgeImportedReviewQuery.Variant.RawValue?
            let importedPayloadJSON: String?
        }

        struct ReviewComparison: Codable {
            let worktreeId: UUID
            let comparison: WorkspaceBaseline
        }

        let openedDocuments: [OpenedDocument]
        let memberWorktreeIds: [UUID]
        let filesFilter: FilesFilter
        let selectedFilesDocument: String?
        let reviewSelection: ReviewSelection
        let surface: BridgeNavigationSurface.RawValue
        let reviewComparisons: [ReviewComparison]

        init(record: BridgeNavigationRecord) {
            openedDocuments = record.openedDocuments.map { document in
                OpenedDocument(
                    canonicalPath: document.location.canonicalPath,
                    provenance: document.provenance.map {
                        Provenance(repoId: $0.repoId, worktreeId: $0.worktreeId, relativePath: $0.relativePath)
                    }
                )
            }
            memberWorktreeIds = record.memberWorktreeIds
            switch record.filesFilter {
            case .allMembers:
                filesFilter = FilesFilter(kind: .allMembers, worktreeId: nil)
            case .member(let worktreeId):
                filesFilter = FilesFilter(kind: .member, worktreeId: worktreeId)
            case .openedDocuments:
                filesFilter = FilesFilter(kind: .openedDocuments, worktreeId: nil)
            }
            selectedFilesDocument = record.selectedFilesDocument?.canonicalPath
            switch record.reviewSelection {
            case .unselected:
                reviewSelection = ReviewSelection(
                    kind: .unselected, worktreeId: nil, importedVariant: nil, importedPayloadJSON: nil)
            case .member(let worktreeId):
                reviewSelection = ReviewSelection(
                    kind: .member, worktreeId: worktreeId, importedVariant: nil, importedPayloadJSON: nil)
            case .importedUnavailable(let query):
                reviewSelection = ReviewSelection(
                    kind: .importedUnavailable,
                    worktreeId: nil,
                    importedVariant: query.variant.rawValue,
                    importedPayloadJSON: query.originalPayloadJSON
                )
            }
            surface = record.surface.rawValue
            reviewComparisons = record.reviewComparisonsByWorktreeId
                .sorted { $0.key.uuidString < $1.key.uuidString }
                .map { ReviewComparison(worktreeId: $0.key, comparison: $0.value) }
        }

        func record() throws -> BridgeNavigationRecord {
            var seenLocations = Set<BridgeDocumentLocation>()
            let documents = try openedDocuments.map { stored -> BridgeOpenedDocument in
                guard let location = BridgeDocumentLocation(canonicalPath: stored.canonicalPath) else {
                    throw BridgeNavigationPayloadCodecError.invalidDocumentLocation(field: "openedDocuments")
                }
                guard seenLocations.insert(location).inserted else {
                    throw BridgeNavigationPayloadCodecError.duplicateDocumentLocation
                }
                return BridgeOpenedDocument(
                    location: location,
                    provenance: stored.provenance.map {
                        BridgeKnownWorktreeProvenance(
                            repoId: $0.repoId,
                            worktreeId: $0.worktreeId,
                            relativePath: $0.relativePath
                        )
                    }
                )
            }
            guard Set(memberWorktreeIds).count == memberWorktreeIds.count else {
                throw BridgeNavigationPayloadCodecError.duplicateMember
            }
            let selected: BridgeDocumentLocation?
            if let selectedFilesDocument {
                guard let location = BridgeDocumentLocation(canonicalPath: selectedFilesDocument) else {
                    throw BridgeNavigationPayloadCodecError.invalidDocumentLocation(field: "selectedFilesDocument")
                }
                guard seenLocations.contains(location) else {
                    throw BridgeNavigationPayloadCodecError.selectedDocumentNotInInventory
                }
                selected = location
            } else {
                selected = nil
            }
            guard let decodedSurface = BridgeNavigationSurface(rawValue: surface) else {
                throw BridgeNavigationPayloadCodecError.malformedPayload
            }
            return BridgeNavigationRecord(
                openedDocuments: documents,
                memberWorktreeIds: memberWorktreeIds,
                filesFilter: try decodedFilesFilter(),
                selectedFilesDocument: selected,
                reviewSelection: try decodedReviewSelection(),
                surface: decodedSurface,
                reviewComparisonsByWorktreeId: Dictionary(
                    reviewComparisons.map { ($0.worktreeId, $0.comparison) },
                    uniquingKeysWith: { _, last in last }
                )
            )
        }

        private func decodedFilesFilter() throws -> BridgeFilesFilter {
            switch filesFilter.kind {
            case .allMembers:
                return .allMembers
            case .openedDocuments:
                return .openedDocuments
            case .member:
                guard let worktreeId = filesFilter.worktreeId else {
                    throw BridgeNavigationPayloadCodecError.malformedPayload
                }
                return .member(worktreeId: worktreeId)
            }
        }

        private func decodedReviewSelection() throws -> BridgeReviewSelection {
            switch reviewSelection.kind {
            case .unselected:
                return .unselected
            case .member:
                guard let worktreeId = reviewSelection.worktreeId else {
                    throw BridgeNavigationPayloadCodecError.malformedPayload
                }
                return .member(worktreeId: worktreeId)
            case .importedUnavailable:
                guard
                    let rawVariant = reviewSelection.importedVariant,
                    let variant = BridgeImportedReviewQuery.Variant(rawValue: rawVariant),
                    let payloadJSON = reviewSelection.importedPayloadJSON
                else {
                    throw BridgeNavigationPayloadCodecError.malformedPayload
                }
                return .importedUnavailable(
                    BridgeImportedReviewQuery(variant: variant, originalPayloadJSON: payloadJSON)
                )
            }
        }
    }
}
