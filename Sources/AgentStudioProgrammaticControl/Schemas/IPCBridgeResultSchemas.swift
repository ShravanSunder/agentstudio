import Foundation

extension IPCBridgeReviewOpenResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        bridgeOpenedPaneSchema(handleMeaning: "Bridge review handle")
    }
}

extension IPCBridgeFileViewOpenResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        bridgeOpenedPaneSchema(handleMeaning: "Bridge file viewer handle")
    }
}

extension IPCBridgeReviewRefreshResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgePaneIdField(),
            .init(name: "refreshed", description: "Whether the review package was refreshed", schema: .boolean),
            .init(name: "status", description: "Review refresh outcome", schema: .string()),
            .optional("packageId", description: "Current review package identifier", schema: .string()),
            .optional("reviewGeneration", description: "Current review generation", schema: .integer(minimum: 0)),
            bridgeCorrelationField(),
        ])
    }
}

extension IPCBridgeReviewItemSummary: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "itemId", description: "Stable item identifier within the review package", schema: .string()),
            .init(
                name: "displayPath", description: "Repository-relative path displayed for the item", schema: .string()),
            .init(name: "itemKind", description: "Review item content kind", schema: .string()),
            .init(name: "changeKind", description: "Git change classification", schema: .string()),
            .init(name: "collapsed", description: "Whether the item is collapsed in the review", schema: .boolean),
        ])
    }
}

extension IPCBridgeReviewPackageSummary: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "filesChanged", description: "Number of changed files", schema: .integer(minimum: 0)),
            .init(name: "additions", description: "Number of added lines", schema: .integer(minimum: 0)),
            .init(name: "deletions", description: "Number of deleted lines", schema: .integer(minimum: 0)),
            .init(
                name: "visibleFileCount", description: "Changed files visible under current filters",
                schema: .integer(minimum: 0)),
            .init(
                name: "hiddenFileCount", description: "Changed files hidden by current filters",
                schema: .integer(minimum: 0)),
        ])
    }
}

extension IPCBridgeReviewPackageResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgePaneIdField(),
            .init(name: "status", description: "Review package availability status", schema: .string()),
            .optional("error", description: "Review package failure description", schema: .string()),
            .optional("selectedItemId", description: "Currently selected review item identifier", schema: .string()),
            .optional("packageId", description: "Review package identifier", schema: .string()),
            .optional("reviewGeneration", description: "Review package generation", schema: .integer(minimum: 0)),
            .optional("revision", description: "Review metadata revision", schema: .integer(minimum: 0)),
            .optional(
                "summary", description: "Aggregate review change counts",
                schema: try IPCBridgeReviewPackageSummary.ipcSchema()),
            .optional(
                "comparisonOrigin", description: "Resolved Git comparison provenance",
                schema: try IPCBridgeReviewComparisonOrigin.ipcSchema()),
            .optional("reviewedSubjectLabel", description: "Human-readable reviewed subject", schema: .string()),
            .init(
                name: "items", description: "Review items in presentation order",
                schema: .array(items: try IPCBridgeReviewItemSummary.ipcSchema())),
        ])
    }
}

extension IPCBridgeContentHandleIdentity: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "handleId", description: "Opaque content handle identifier", schema: .string()),
            .init(name: "itemId", description: "Review item identifier", schema: .string()),
            .init(name: "role", description: "Content role within the comparison", schema: .string()),
            .init(
                name: "reviewGeneration", description: "Review generation owning the handle",
                schema: .integer(minimum: 0)),
        ])
    }
}

extension IPCBridgeContentHandlePresentation: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "mimeType", description: "Content MIME type", schema: .string()),
            .optional("language", description: "Syntax language identifier", schema: .string()),
        ])
    }
}

extension IPCBridgeContentHandleSize: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "sizeBytes", description: "Content size in bytes", schema: .integer(minimum: 0)),
            .init(name: "isBinary", description: "Whether the content is binary", schema: .boolean),
        ])
    }
}

extension IPCBridgeContentHandleSummary: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "handleId", description: "Opaque content handle identifier", schema: .string()),
            .init(name: "itemId", description: "Review item identifier", schema: .string()),
            .init(name: "role", description: "Content role within the comparison", schema: .string()),
            .init(
                name: "reviewGeneration", description: "Review generation owning the handle",
                schema: .integer(minimum: 0)),
            .init(name: "mimeType", description: "Content MIME type", schema: .string()),
            .optional("language", description: "Syntax language identifier", schema: .string()),
            .init(name: "sizeBytes", description: "Content size in bytes", schema: .integer(minimum: 0)),
            .init(name: "isBinary", description: "Whether the content is binary", schema: .boolean),
        ])
    }
}

extension IPCBridgeReviewSelectFileResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgePaneIdField(),
            .init(name: "itemId", description: "Selected review item identifier", schema: .string()),
            .init(name: "selected", description: "Whether the requested item became selected", schema: .boolean),
            bridgeCorrelationField(),
        ])
    }
}

extension IPCBridgePageControlResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgePaneIdField(),
            .init(name: "method", description: "Bridge page-control method applied", schema: .string()),
            .init(name: "status", description: "Page-control outcome", schema: .string()),
            .optional("itemId", description: "Affected review item identifier", schema: .string()),
            .optional("path", description: "Affected repository-relative path", schema: .string()),
            .init(name: "treeSearchText", description: "Effective file-tree search text", schema: .string()),
            .init(
                name: "filterSurface", description: "File-tree filter surface",
                schema: try IPCBridgeFileTreeFilterSurface.ipcSchema()),
            .init(
                name: "gitStatusFilter", description: "Effective Git status filter",
                schema: try IPCBridgeGitStatusFilter.ipcSchema()),
            .init(
                name: "categoryFilter", description: "Effective file category filter",
                schema: try IPCBridgeFilterCategory.ipcSchema()),
            .init(name: "showBinary", description: "Whether binary files are visible", schema: .boolean),
            .init(name: "showLarge", description: "Whether large files are visible", schema: .boolean),
            .init(name: "renderMode", description: "Effective file render mode", schema: .string()),
            .optional("reason", description: "Reason when the action was unavailable or rejected", schema: .string()),
            bridgeCorrelationField(),
        ])
    }
}

extension IPCBridgeContentGetResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgePaneIdField(),
            .init(
                name: "handle", description: "Resolved content handle metadata",
                schema: try IPCBridgeContentHandleSummary.ipcSchema()),
            .init(name: "mimeType", description: "Returned content MIME type", schema: .string()),
            .init(name: "byteCount", description: "Returned content size in bytes", schema: .integer(minimum: 0)),
            .init(name: "isBinary", description: "Whether the returned content is binary", schema: .boolean),
        ])
    }
}

private func bridgeOpenedPaneSchema(handleMeaning: String) -> IPCJSONSchema {
    .object(fields: [
        bridgePaneIdField(),
        .init(name: "handle", description: handleMeaning, schema: .string()),
        bridgeCorrelationField(),
    ])
}

private func bridgePaneIdField() -> IPCObjectField {
    .init(name: "paneId", description: "Bridge pane UUID", schema: IPCSchemaScalars.uuid)
}

private func bridgeCorrelationField() -> IPCObjectField {
    .optional("correlationId", description: "Caller correlation UUID when supplied", schema: IPCSchemaScalars.uuid)
}
