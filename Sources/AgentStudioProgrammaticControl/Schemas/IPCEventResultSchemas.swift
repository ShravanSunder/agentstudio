import Foundation

extension IPCEventName: IPCSchemaProviding {}
extension IPCPermissionRequestState: IPCSchemaProviding {}
extension IPCPrivilegeClass: IPCSchemaProviding {}
extension IPCDataScope: IPCSchemaProviding {}

extension IPCEventSubscriptionResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "subscriptionId", description: "Server-assigned event subscription UUID",
                schema: IPCSchemaScalars.uuid),
            .init(
                name: "eventNames", description: "Event names admitted for this subscription",
                schema: .array(items: try IPCEventName.ipcSchema())),
        ])
    }
}

extension IPCTerminalEventPayload: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "paneId", description: "Terminal pane UUID", schema: IPCSchemaScalars.uuid),
            .init(
                name: "condition", description: "Terminal condition represented by the event",
                schema: try IPCTerminalWaitCondition.ipcSchema()),
            .optional("commandId", description: "Related terminal command UUID", schema: IPCSchemaScalars.uuid),
            eventCorrelationField(),
            .optional(
                "exitCode", description: "Process exit code for completion events",
                schema: IPCSchemaScalars.signedInteger),
            .optional("duration", description: "Observed duration in seconds", schema: .number(minimum: 0)),
            .optional("healthy", description: "Renderer health value for health events", schema: .boolean),
        ])
    }
}

extension IPCBridgeEventPayload: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "paneId", description: "Bridge pane UUID", schema: IPCSchemaScalars.uuid),
            .optional("packageId", description: "Review package identifier", schema: .string()),
            .optional("itemId", description: "Review item identifier", schema: .string()),
            .optional("contentHandleId", description: "Bridge content handle identifier", schema: .string()),
            eventCorrelationField(),
        ])
    }
}

extension IPCTargetScope: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            eventTagOnly(kind: "selfPane"),
            eventTagValue(kind: "pane", description: "Canonical pane handle", schema: .string()),
            eventTagValue(kind: "workspace", description: "Workspace UUID", schema: IPCSchemaScalars.uuid),
            eventTagOnly(kind: "app"),
        ])
    }
}

extension IPCPermissionScope: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "privilege", description: "Requested privilege class", schema: try IPCPrivilegeClass.ipcSchema()),
            .init(name: "target", description: "Requested target scope", schema: try IPCTargetScope.ipcSchema()),
            .init(name: "dataScope", description: "Requested data category", schema: try IPCDataScope.ipcSchema()),
        ])
    }
}

extension IPCPermissionApprovalRoute: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            eventTagOnly(kind: "appPolicy"),
            eventTagOnly(kind: "humanPrompt"),
            .object(fields: [
                .init(
                    name: "kind", description: "Approval route kind",
                    schema: .string(allowedValues: ["delegatedPrincipal"])),
                .init(
                    name: "principalId", description: "Delegated approver principal UUID", schema: IPCSchemaScalars.uuid
                ),
            ]),
        ])
    }
}

extension IPCPermissionEventPayload: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "requestId", description: "Permission request UUID", schema: IPCSchemaScalars.uuid),
            .init(
                name: "state", description: "Permission request state",
                schema: try IPCPermissionRequestState.ipcSchema()),
            .init(name: "principalId", description: "Requesting principal UUID", schema: IPCSchemaScalars.uuid),
            .init(
                name: "requestedScope", description: "Requested authority scope",
                schema: try IPCPermissionScope.ipcSchema()),
            .init(
                name: "approvalRoute", description: "Authority route handling the request",
                schema: try IPCPermissionApprovalRoute.ipcSchema()),
        ])
    }
}

extension IPCEventPayload: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            .object(fields: [
                .init(name: "kind", description: "Event payload kind", schema: .string(allowedValues: ["bridge"])),
                .init(
                    name: "bridge", description: "Bridge event details", schema: try IPCBridgeEventPayload.ipcSchema()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "Event payload kind", schema: .string(allowedValues: ["permission"])),
                .init(
                    name: "permission", description: "Permission event details",
                    schema: try IPCPermissionEventPayload.ipcSchema()),
            ]),
            .object(fields: [
                .init(name: "kind", description: "Event payload kind", schema: .string(allowedValues: ["terminal"])),
                .init(
                    name: "terminal", description: "Terminal event details",
                    schema: try IPCTerminalEventPayload.ipcSchema()),
            ]),
        ])
    }
}

extension IPCEventNotification: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: try eventEnvelopeFields(payload: IPCEventPayload.ipcSchema()))
    }
}

extension IPCPermissionEventNotification: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: try eventEnvelopeFields(payload: IPCPermissionEventPayload.ipcSchema()))
    }
}

private func eventCorrelationField() -> IPCObjectField {
    .optional("correlationId", description: "Originating request correlation UUID", schema: IPCSchemaScalars.uuid)
}

private func eventTagOnly(kind: String) -> IPCJSONSchema {
    .object(fields: [
        .init(name: "kind", description: "Target or approval variant", schema: .string(allowedValues: [kind]))
    ])
}

private func eventTagValue(kind: String, description: String, schema: IPCJSONSchema) -> IPCJSONSchema {
    .object(fields: [
        .init(name: "kind", description: "Target scope kind", schema: .string(allowedValues: [kind])),
        .init(name: "value", description: description, schema: schema),
    ])
}

private func eventEnvelopeFields(payload: IPCJSONSchema) throws -> [IPCObjectField] {
    [
        .init(name: "eventId", description: "Unique event occurrence UUID", schema: IPCSchemaScalars.uuid),
        .init(name: "name", description: "Qualified event name", schema: try IPCEventName.ipcSchema()),
        .init(
            name: "occurredAt",
            description: "Occurrence time in seconds since the Foundation reference date",
            schema: .number()),
        .init(name: "payload", description: "Typed event payload", schema: payload),
    ]
}
