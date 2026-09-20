import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

/// Projects untrusted remote errors into the finite correction types understood
/// by the client. Raw messages, unknown keys, and malformed values are dropped.
enum IPCDescriptorRemoteFailureDecoder {
    static func decode(
        _ error: JSONRPCErrorPayload,
        descriptor: IPCAnyMethodDescriptor?
    ) -> IPCDescriptorRemoteFailure {
        IPCDescriptorRemoteFailure(
            code: error.code,
            documentedReason: documentedReason(
                from: error.data,
                descriptor: descriptor
            ),
            correction: schemaCorrection(from: error.data),
            requiredScope: missingGrantScope(from: error)
        )
    }

    private static func documentedReason(
        from data: JSONValue?,
        descriptor: IPCAnyMethodDescriptor?
    ) -> String? {
        guard case .object(let fields) = data,
            case .string(let reason) = fields["reason"],
            descriptor?.metadata.documentedErrors.contains(where: { $0.reason == reason }) == true
        else {
            return nil
        }
        return reason
    }

    private static func schemaCorrection(
        from data: JSONValue?
    ) -> IPCSchemaValidationError? {
        guard case .object(let fields) = data,
            Set(fields.keys) == ["expected", "fieldPath", "reason"]
        else {
            return nil
        }
        return decode(IPCSchemaValidationError.self, from: fields)
    }

    private static func missingGrantScope(
        from error: JSONRPCErrorPayload
    ) -> IPCPermissionScope? {
        guard error.code == -32_002,
            case .object(let fields) = error.data,
            Set(fields.keys) == ["fieldPath", "reason", "requiredScope"],
            fields["reason"] == .string("missingGrant"),
            fields["fieldPath"] == .string("$.authorization"),
            let requiredScope = fields["requiredScope"]
        else {
            return nil
        }
        guard let scope = decode(IPCPermissionScope.self, from: requiredScope) else { return nil }
        switch scope.target {
        case .selfPane:
            return nil
        case .pane(let identifier):
            guard UUID(uuidString: identifier) != nil else { return nil }
        case .workspace, .app:
            break
        }
        return scope
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from fields: [String: JSONValue]
    ) -> Value? {
        decode(type, from: .object(fields))
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from value: JSONValue
    ) -> Value? {
        guard let encoded = try? JSONEncoder().encode(value) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: encoded)
    }
}
