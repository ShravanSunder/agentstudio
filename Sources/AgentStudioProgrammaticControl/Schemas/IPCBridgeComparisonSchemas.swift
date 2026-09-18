import Foundation

extension IPCBridgeReviewComparisonBasis: IPCSchemaProviding {}
extension IPCBridgeReviewComparisonBaseRole: IPCSchemaProviding {}
extension IPCBridgeFileTreeFilterSurface: IPCSchemaProviding {}
extension IPCBridgeFilterCategory: IPCSchemaProviding {}
extension IPCBridgeGitStatusFilter: IPCSchemaProviding {}
extension IPCBridgeNativeActivity: IPCSchemaProviding {}
extension IPCBridgeReviewSearchMode.Kind: IPCSchemaProviding {}

extension IPCBridgeReviewSearchMode: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "kind", description: "File tree search matching mode", schema: try Kind.ipcSchema())
        ])
    }
}

extension IPCBridgeReviewComparisonTarget: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        let basis = try IPCBridgeReviewComparisonBasis.ipcSchema()
        return .oneOf([
            .object(fields: [
                bridgeComparisonKind("localDefaultBranch"),
                .init(name: "branchName", description: "Resolved local default branch name", schema: .string()),
                .init(name: "basis", description: "Comparison basis for the branch", schema: basis),
            ]),
            .object(fields: [
                bridgeComparisonKind("originDefaultBranch"),
                .init(name: "remoteName", description: "Resolved default remote name", schema: .string()),
                .init(name: "branchName", description: "Resolved remote default branch name", schema: .string()),
                .init(name: "basis", description: "Comparison basis for the branch", schema: basis),
            ]),
            .object(fields: [
                bridgeComparisonKind("branch"),
                .init(name: "name", description: "Selected branch name", schema: .string()),
                .init(name: "basis", description: "Comparison basis for the branch", schema: basis),
            ]),
            .object(fields: [
                bridgeComparisonKind("commit"),
                .init(
                    name: "oid", description: "Selected SHA-1 or SHA-256 commit object ID",
                    schema: bridgeGitObjectIdSchema()),
            ]),
            .object(fields: [
                bridgeComparisonKind("ref"),
                .init(name: "name", description: "Selected Git ref name", schema: .string()),
                .init(name: "basis", description: "Comparison basis for the ref", schema: basis),
            ]),
        ])
    }
}

extension IPCBridgeReviewContributionOrigin: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "symbolicTarget", description: "Symbolic comparison target",
                schema: try IPCBridgeReviewComparisonTarget.ipcSchema()),
            .init(
                name: "resolvedTargetOID", description: "Resolved target Git object ID",
                schema: bridgeGitObjectIdSchema()),
            .init(
                name: "reviewedHeadOID", description: "Reviewed working tree head Git object ID",
                schema: bridgeGitObjectIdSchema()),
            .init(
                name: "baseRole", description: "Role of the selected comparison base",
                schema: try IPCBridgeReviewComparisonBaseRole.ipcSchema()),
            .init(name: "baseOID", description: "Comparison base Git object ID", schema: bridgeGitObjectIdSchema()),
        ])
    }
}

extension IPCBridgeReviewComparisonOrigin: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgeComparisonKind("contribution"),
            .init(
                name: "baseRole", description: "Role of the comparison base",
                schema: try IPCBridgeReviewComparisonBaseRole.ipcSchema()),
            .init(
                name: "comparedRole", description: "Captured endpoint used for review",
                schema: .string(allowedValues: ["capturedWorkingTree"])),
            .init(
                name: "symbolicTarget", description: "Symbolic comparison target",
                schema: try IPCBridgeReviewComparisonTarget.ipcSchema()),
            .init(
                name: "resolvedTargetOID", description: "Resolved target Git object ID",
                schema: bridgeGitObjectIdSchema()),
            .init(
                name: "reviewedHeadOID", description: "Reviewed head Git object ID", schema: bridgeGitObjectIdSchema()),
            .init(name: "baseOID", description: "Comparison base Git object ID", schema: bridgeGitObjectIdSchema()),
        ])
    }
}

private func bridgeComparisonKind(_ value: String) -> IPCObjectField {
    .init(name: "kind", description: "Comparison variant", schema: .string(allowedValues: [value]))
}

private func bridgeGitObjectIdSchema() -> IPCJSONSchema {
    .string(pattern: "^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$")
}
