import Foundation

package struct IPCPaneContextMethodDescriptors: Sendable {
    package let messageSend: IPCMethodDescriptor<IPCPaneMessageSendParams, IPCPaneMessageSendResult>
    package let messageAsk: IPCMethodDescriptor<IPCPaneMessageAskParams, IPCPaneAskOutcome>
    package let messageWithdraw: IPCMethodDescriptor<IPCPaneMessageWithdrawParams, IPCPaneMessageWithdrawResult>
    package let messageChanges: IPCMethodDescriptor<IPCPaneMessageChangesParams, IPCPaneMessageChangesResult>
    package let lineSet: IPCMethodDescriptor<IPCPaneLineSetParams, IPCPaneOrderedWriteResult>
    package let titleSet: IPCMethodDescriptor<IPCPaneTitleSetParams, IPCPaneOrderedWriteResult>
    package let writerClaimEpoch: IPCMethodDescriptor<IPCPaneWriterClaimEpochParams, IPCPaneEpochClaimResult>
    package let contextGet: IPCMethodDescriptor<IPCPaneContextGetParams, IPCPaneContextGetResult>

    init(examples: IPCBuiltInMethodExampleContext) throws {
        messageSend = try Self.makeMessageSendDescriptor(examples: examples)
        messageAsk = try Self.makeMessageAskDescriptor(examples: examples)
        messageWithdraw = try Self.makeMessageWithdrawDescriptor(examples: examples)
        messageChanges = try Self.makeMessageChangesDescriptor(examples: examples)
        lineSet = try Self.makeLineSetDescriptor(examples: examples)
        titleSet = try Self.makeTitleSetDescriptor(examples: examples)
        writerClaimEpoch = try Self.makeWriterClaimEpochDescriptor(examples: examples)
        contextGet = try Self.makeContextGetDescriptor(examples: examples)
    }

    private static func makeMessageSendDescriptor(examples: IPCBuiltInMethodExampleContext) throws
        -> IPCMethodDescriptor<IPCPaneMessageSendParams, IPCPaneMessageSendResult>
    {
        try IPCMethodDescriptor(
            name: "pane.message.send",
            description:
                "Post a notice or non-blocking ask. Body <= 4 KiB UTF-8, why <= 1 KiB, choices <= 12 with labels <= 200 bytes, form <= 16 properties and 8 KiB encoded, actions <= 4 with each <= 1 KiB encoded. At most 32 open asks and 200 unread notices per pane.",
            examples: [
                .init(
                    description: "Representative pane.message.send call",
                    parameters: IPCPaneMessageSendParams(
                        handle: "self", messageId: examples.commandId, importance: .info,
                        body: "The migration finished", actions: [], shape: .notice,
                        correlationId: examples.correlationId), result: .created(id: examples.commandId))
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextWrite],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: Self.errors,
            isMutating: true,
            correlationPolicy: .required,
            agentEligibility: .ownPane
        )
    }

    private static func makeMessageAskDescriptor(examples: IPCBuiltInMethodExampleContext) throws
        -> IPCMethodDescriptor<IPCPaneMessageAskParams, IPCPaneAskOutcome>
    {
        try IPCMethodDescriptor(
            name: "pane.message.ask",
            description:
                "Wait beside the connection reader for one blocking ask. The send limits apply; EOF withdraws, stopping makes stale, and the first committed settlement wins.",
            examples: [
                .init(
                    description: "Representative pane.message.ask call",
                    parameters: IPCPaneMessageAskParams(
                        handle: "self", messageId: examples.commandId,
                        writer: IPCPaneWriterClaim(provider: "claude-code", conversationId: "conversation-1"),
                        importance: .attention, body: "Continue?", actions: [],
                        shape: .ask(
                            reason: .approval, form: .freeText(placeholder: nil),
                            waiting: .blocking(deadline: Date(timeIntervalSinceReferenceDate: 60))),
                        correlationId: examples.correlationId), result: .expired)
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextWrite],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: Self.errors,
            isMutating: true,
            correlationPolicy: .required,
            agentEligibility: .ownPane
        )
    }

    private static func makeMessageWithdrawDescriptor(examples: IPCBuiltInMethodExampleContext) throws
        -> IPCMethodDescriptor<IPCPaneMessageWithdrawParams, IPCPaneMessageWithdrawResult>
    {
        try IPCMethodDescriptor(
            name: "pane.message.withdraw",
            description:
                "Withdraw one message owned by this pane writer. A settled ask returns its committed terminal state; a read notice cannot be withdrawn.",
            examples: [
                .init(
                    description: "Representative pane.message.withdraw call",
                    parameters: IPCPaneMessageWithdrawParams(
                        handle: "self", messageId: examples.commandId, correlationId: examples.correlationId),
                    result: .withdrawn)
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextWrite],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: Self.errors,
            isMutating: true,
            correlationPolicy: .required,
            agentEligibility: .ownPane
        )
    }

    private static func makeMessageChangesDescriptor(examples: IPCBuiltInMethodExampleContext) throws
        -> IPCMethodDescriptor<IPCPaneMessageChangesParams, IPCPaneMessageChangesResult>
    {
        try IPCMethodDescriptor(
            name: "pane.message.changes",
            description:
                "Read up to 200 changes or 256 KiB and confirm receipt through after. Positions are exact non-negative JSON safe integers.",
            examples: [
                .init(
                    description: "Representative pane.message.changes call",
                    parameters: IPCPaneMessageChangesParams(
                        handle: "self", after: 0, correlationId: examples.correlationId),
                    result: IPCPaneMessageChangesResult(entries: [], nextPosition: 0, more: false))
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextWrite],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: Self.errors,
            isMutating: true,
            correlationPolicy: .required,
            agentEligibility: .ownPane
        )
    }

    private static func makeLineSetDescriptor(examples: IPCBuiltInMethodExampleContext) throws -> IPCMethodDescriptor<
        IPCPaneLineSetParams, IPCPaneOrderedWriteResult
    > {
        try IPCMethodDescriptor(
            name: "pane.line.set",
            description:
                "Set or clear the ordered Agent Line. Summary/work <= 200 UTF-8 bytes, detail <= 2 KiB, steps <= 10000, refs <= 8 with each <= 512 encoded bytes.",
            examples: [
                .init(
                    description: "Representative pane.line.set call",
                    parameters: IPCPaneLineSetParams(
                        handle: "self", line: nil, writeNumber: IPCPaneWriteNumber(epoch: 1, counter: 1),
                        correlationId: examples.correlationId), result: .applied)
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextWrite],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: Self.errors,
            isMutating: true,
            correlationPolicy: .required,
            agentEligibility: .ownPane
        )
    }

    private static func makeTitleSetDescriptor(examples: IPCBuiltInMethodExampleContext) throws -> IPCMethodDescriptor<
        IPCPaneTitleSetParams, IPCPaneOrderedWriteResult
    > {
        try IPCMethodDescriptor(
            name: "pane.title.set",
            description:
                "Set or clear the ordered Agent Title, at most 256 UTF-8 bytes. Stale payloads are final and must never be retried under a new number.",
            examples: [
                .init(
                    description: "Representative pane.title.set call",
                    parameters: IPCPaneTitleSetParams(
                        handle: "self", text: "Migration complete",
                        writeNumber: IPCPaneWriteNumber(epoch: 1, counter: 1), correlationId: examples.correlationId),
                    result: .applied)
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextWrite],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: Self.errors,
            isMutating: true,
            correlationPolicy: .required,
            agentEligibility: .ownPane
        )
    }

    private static func makeWriterClaimEpochDescriptor(examples: IPCBuiltInMethodExampleContext) throws
        -> IPCMethodDescriptor<IPCPaneWriterClaimEpochParams, IPCPaneEpochClaimResult>
    {
        try IPCMethodDescriptor(
            name: "pane.writer.claimEpoch",
            description:
                "Idempotently claim the current writer stream epoch by claimId. A claim changes no displayed value.",
            examples: [
                .init(
                    description: "Representative pane.writer.claimEpoch call",
                    parameters: IPCPaneWriterClaimEpochParams(
                        handle: "self", stream: .title, claimId: examples.commandId,
                        correlationId: examples.correlationId), result: .claimed(epoch: 1))
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextWrite],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .discriminated,
            documentedErrors: Self.errors,
            isMutating: true,
            correlationPolicy: .required,
            agentEligibility: .ownPane
        )
    }

    private static func makeContextGetDescriptor(examples: IPCBuiltInMethodExampleContext) throws
        -> IPCMethodDescriptor<IPCPaneContextGetParams, IPCPaneContextGetResult>
    {
        try IPCMethodDescriptor(
            name: "pane.context.get",
            description:
                "Read the credential pane and its current drawers. One composed 1 MiB logical budget; truncation and more pages reach every live message. Encoded replies also fit the transport and output-queue bounds.",
            examples: [
                .init(
                    description: "Representative pane.context.get call",
                    parameters: IPCPaneContextGetParams(handle: "self", page: .first),
                    result: IPCPaneContextGetResult(
                        paneId: examples.paneId, revision: 0, messages: [], drawerMessages: [], links: .unknown,
                        pullRequests: .notApplicable))
            ],
            exposure: .allChannels,
            requiredPrivileges: [.paneContextRead],
            dataScope: .paneContext,
            allowedTargetKinds: [.pane],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .paneContextService,
            principalAvailability: .authenticated,
            resultSemantics: .applied,
            documentedErrors: Self.errors,
            isMutating: false,
            correlationPolicy: .notAccepted,
            agentEligibility: .ownPane
        )
    }

    private static var errors: [IPCMethodErrorCase] {
        [
            "unauthorized", "bindingRequired", "conflict", "paneGone", "notSender", "noticeAlreadyRead", "tooLarge",
            "invalidField", "stale", "sourceNotInView", "unavailable", "internalError", "connectionBusy",
        ].map {
            IPCMethodErrorCase(reason: $0, description: "Typed pane context refusal: \($0).")
        }
    }

    var descriptorRepresentations: [any IPCMethodDescriptorRepresentation] {
        get throws {
            try [
                IPCMethodDescriptorRepresentations(typedDescriptor: messageSend),
                IPCMethodDescriptorRepresentations(typedDescriptor: messageAsk),
                IPCMethodDescriptorRepresentations(typedDescriptor: messageWithdraw),
                IPCMethodDescriptorRepresentations(typedDescriptor: messageChanges),
                IPCMethodDescriptorRepresentations(typedDescriptor: lineSet),
                IPCMethodDescriptorRepresentations(typedDescriptor: titleSet),
                IPCMethodDescriptorRepresentations(typedDescriptor: writerClaimEpoch),
                IPCMethodDescriptorRepresentations(typedDescriptor: contextGet),
            ]
        }
    }
}
