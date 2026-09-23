import Foundation

package struct IPCBuiltInMethodExampleContext: Sendable {
    package let runtimeId: UUID
    package let windowId: UUID
    package let workspaceId: UUID
    package let repositoryId: UUID
    package let worktreeId: UUID
    package let tabId: UUID
    package let paneId: UUID
    package let commandId: UUID
    package let correlationId: UUID
    package let subscriptionId: UUID

    package init(
        runtimeId: UUID,
        windowId: UUID,
        workspaceId: UUID,
        repositoryId: UUID,
        worktreeId: UUID,
        tabId: UUID,
        paneId: UUID,
        commandId: UUID,
        correlationId: UUID,
        subscriptionId: UUID
    ) {
        self.runtimeId = runtimeId
        self.windowId = windowId
        self.workspaceId = workspaceId
        self.repositoryId = repositoryId
        self.worktreeId = worktreeId
        self.tabId = tabId
        self.paneId = paneId
        self.commandId = commandId
        self.correlationId = correlationId
        self.subscriptionId = subscriptionId
    }
}

package struct IPCBuiltInMethodRelationshipInputs: Sendable {
    package let paneFocus: IPCCommandRelationship
    package let paneClose: IPCCommandRelationship
    package let drawerToggle: IPCCommandRelationship
    package let drawerAddPane: IPCCommandRelationship
    package let bridgeDiffLoad: IPCCommandRelationship
    package let bridgeFileViewOpen: IPCCommandRelationship

    package init(
        paneFocus: IPCCommandRelationship,
        paneClose: IPCCommandRelationship,
        drawerToggle: IPCCommandRelationship,
        drawerAddPane: IPCCommandRelationship,
        bridgeDiffLoad: IPCCommandRelationship,
        bridgeFileViewOpen: IPCCommandRelationship
    ) {
        self.paneFocus = paneFocus
        self.paneClose = paneClose
        self.drawerToggle = drawerToggle
        self.drawerAddPane = drawerAddPane
        self.bridgeDiffLoad = bridgeDiffLoad
        self.bridgeFileViewOpen = bridgeFileViewOpen
    }
}

package struct IPCBuiltInMethodCatalogInputs: Sendable {
    package let terminalWaitMaximumSeconds: Double
    package let relationships: IPCBuiltInMethodRelationshipInputs
    package let examples: IPCBuiltInMethodExampleContext

    package init(
        terminalWaitMaximumSeconds: Double,
        relationships: IPCBuiltInMethodRelationshipInputs,
        examples: IPCBuiltInMethodExampleContext
    ) {
        self.terminalWaitMaximumSeconds = terminalWaitMaximumSeconds
        self.relationships = relationships
        self.examples = examples
    }
}

enum IPCBuiltInDescriptorSupport {
    struct MutationMetadata {
        let privilege: IPCPrivilegeClass
        let dataScope: IPCDataScope
        let targetKinds: Set<IPCHandleKind>
        let relationship: IPCCommandRelationship
        let owner: IPCExecutionOwner
        let semantics: IPCResultSemantics
        let errors: [IPCMethodErrorCase]

        init(
            privilege: IPCPrivilegeClass,
            dataScope: IPCDataScope,
            targetKinds: Set<IPCHandleKind>,
            relationship: IPCCommandRelationship = .noInteractiveIdentity,
            owner: IPCExecutionOwner,
            semantics: IPCResultSemantics = .applied,
            errors: [IPCMethodErrorCase] = [
                IPCBuiltInDescriptorSupport.invalidParams,
                IPCBuiltInDescriptorSupport.targetNotFound,
            ]
        ) {
            self.privilege = privilege
            self.dataScope = dataScope
            self.targetKinds = targetKinds
            self.relationship = relationship
            self.owner = owner
            self.semantics = semantics
            self.errors = errors
        }
    }

    static let invalidParams = IPCMethodErrorCase(
        reason: "invalidParams",
        description: "A declared parameter is missing or invalid."
    )
    static let targetNotFound = IPCMethodErrorCase(
        reason: "targetNotFound",
        description: "The declared target does not exist."
    )
    static let unavailable = IPCMethodErrorCase(
        reason: "unavailable",
        description: "The owning application capability is unavailable."
    )

    static func read<Parameters, Result>(
        name: String,
        description: String,
        parameters: Parameters,
        result: Result,
        privilege: IPCPrivilegeClass,
        dataScope: IPCDataScope,
        targetKinds: Set<IPCHandleKind> = [],
        exposure: IPCMethodExposure = .debugTesting,
        availability: IPCPrincipalAvailability = .authenticated,
        owner: IPCExecutionOwner = .queryReader,
        errors: [IPCMethodErrorCase] = []
    ) throws -> IPCMethodDescriptor<Parameters, Result>
    where Parameters: IPCSchemaProviding, Result: IPCSchemaProviding {
        try IPCMethodDescriptor(
            name: name,
            description: description,
            examples: [
                .init(description: "Representative \(name) result", parameters: parameters, result: result)
            ],
            exposure: exposure,
            requiredPrivileges: [privilege],
            dataScope: dataScope,
            allowedTargetKinds: targetKinds,
            commandRelationship: .noInteractiveIdentity,
            executionOwner: owner,
            principalAvailability: availability,
            resultSemantics: .applied,
            documentedErrors: errors,
            isMutating: false,
            correlationPolicy: .notAccepted
        )
    }

    static func mutation<Parameters, Result>(
        name: String,
        description: String,
        parameters: Parameters,
        result: Result,
        metadata: MutationMetadata
    ) throws -> IPCMethodDescriptor<Parameters, Result>
    where Parameters: IPCSchemaProviding, Result: IPCSchemaProviding {
        try IPCMethodDescriptor(
            name: name,
            description: description,
            examples: [
                .init(description: "Representative \(name) result", parameters: parameters, result: result)
            ],
            exposure: .debugTesting,
            requiredPrivileges: [metadata.privilege],
            dataScope: metadata.dataScope,
            allowedTargetKinds: metadata.targetKinds,
            commandRelationship: metadata.relationship,
            executionOwner: metadata.owner,
            principalAvailability: .authenticated,
            resultSemantics: metadata.semantics,
            documentedErrors: metadata.errors,
            isMutating: true,
            correlationPolicy: .required
        )
    }
}
