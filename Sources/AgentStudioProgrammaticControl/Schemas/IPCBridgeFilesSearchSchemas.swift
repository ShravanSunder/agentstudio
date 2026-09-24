import Foundation

extension IPCBridgeFilesSearchScope: IPCSchemaProviding {}
extension IPCBridgeFilesSearchStatus: IPCSchemaProviding {}
extension IPCBridgeFilesSearchUnavailableReason: IPCSchemaProviding {}

extension IPCBridgeFilesSearchParams: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            IPCRequestSchemaFields.pane(),
            .init(
                name: "searchText",
                description: "Exact search text, at most 4096 UTF-16 code units; empty lists every file in scope",
                schema: .string(
                    maximumLength: maximumSearchTextUTF16Length,
                    maximumUTF16Length: maximumSearchTextUTF16Length
                )
            ),
            .init(
                name: "searchMode", description: "Text or regular-expression matching",
                schema: try IPCBridgeReviewSearchMode.ipcSchema(),
                presence: try .defaulted(IPCBridgeReviewSearchMode.text)
            ),
            .init(
                name: "scope",
                description: "All members and opened documents, one member, or only opened documents",
                schema: try IPCBridgeFilesSearchScope.ipcSchema(),
                presence: try .defaulted(IPCBridgeFilesSearchScope.all)
            ),
            .optional(
                "worktreeId", description: "Member worktree UUID; required for the member scope only",
                schema: IPCSchemaScalars.uuid),
            .init(
                name: "limit", description: "Maximum matches returned",
                schema: .integer(minimum: 1, maximum: Int64(maximumLimit)),
                presence: try .defaulted(defaultLimit)
            ),
        ])
    }
}

extension IPCBridgeFilesSearchMatch: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "displayPath", description: "Key the Files tree lists the document under", schema: .string()),
            .init(name: "path", description: "Canonical absolute document path", schema: .string()),
            .optional(
                "memberWorktreeId", description: "Member worktree listing the file; absent for an opened document",
                schema: IPCSchemaScalars.uuid),
            .optional(
                "memberRelativePath", description: "Path relative to the member worktree root",
                schema: .string()),
        ])
    }
}

extension IPCBridgeFilesSearchResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "paneId", description: "Bridge pane UUID", schema: IPCSchemaScalars.uuid),
            .init(name: "status", description: "Search outcome", schema: try IPCBridgeFilesSearchStatus.ipcSchema()),
            .optional(
                "reason", description: "Why no results were produced",
                schema: try IPCBridgeFilesSearchUnavailableReason.ipcSchema()),
            .optional("searchError", description: "Regular-expression error", schema: .string()),
            .init(
                name: "matches", description: "Matches in collection order",
                schema: .array(
                    items: try IPCBridgeFilesSearchMatch.ipcSchema(),
                    maximumCount: IPCBridgeFilesSearchParams.maximumLimit
                )),
            .init(name: "totalMatchCount", description: "Matches before the limit", schema: .integer(minimum: 0)),
            .init(name: "truncated", description: "Whether matches were cut at the limit", schema: .boolean),
            .init(
                name: "complete", description: "Whether the collection's initial tree had finished loading",
                schema: .boolean),
            .init(
                name: "unavailableMemberWorktreeIds", description: "Members whose source failed and were not searched",
                schema: .array(items: IPCSchemaScalars.uuid)),
        ])
    }
}
