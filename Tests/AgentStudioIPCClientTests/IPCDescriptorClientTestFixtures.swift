import AgentStudioIPCClientCore
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

struct IPCDescriptorClientFixtureCatalog {
    let authentication: IPCAnyMethodDescriptor
    let query: IPCAnyMethodDescriptor
    let subscription: IPCAnyMethodDescriptor

    var descriptors: [IPCAnyMethodDescriptor] {
        [authentication, query, subscription]
    }

    static func make() throws -> Self {
        Self(
            authentication: try IPCAnyMethodDescriptor(
                erasing: IPCDescriptorClientFixtureDescriptors.authentication()
            ),
            query: try IPCAnyMethodDescriptor(
                erasing: IPCDescriptorClientFixtureDescriptors.query()
            ),
            subscription: try IPCAnyMethodDescriptor(
                erasing: IPCDescriptorClientFixtureDescriptors.subscription()
            )
        )
    }
}

enum IPCDescriptorClientFixtureDescriptors {
    static func authentication() throws
        -> IPCMethodDescriptor<IPCAuthLoginParams, IPCAuthStatusResult>
    {
        try IPCMethodDescriptor(
            name: "auth.login",
            description: "Authenticate the descriptor client fixture.",
            examples: [],
            exposure: .allChannels,
            requiredPrivileges: [.systemRead],
            dataScope: .unspecified,
            allowedTargetKinds: [],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .queryReader,
            principalAvailability: .preAuthentication,
            resultSemantics: .applied,
            documentedErrors: [
                .init(reason: "unauthenticated", description: "The supplied fixture credential is invalid.")
            ],
            isMutating: false,
            correlationPolicy: .notAccepted
        )
    }

    static func query() throws
        -> IPCMethodDescriptor<IPCDescriptorClientQueryParameters, IPCDescriptorClientQueryResult>
    {
        try IPCMethodDescriptor(
            name: "fixture.query",
            description: "Return one typed fixture value.",
            examples: [],
            exposure: .allChannels,
            requiredPrivileges: [.systemRead],
            dataScope: .unspecified,
            allowedTargetKinds: [],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .queryReader,
            principalAvailability: .authenticated,
            resultSemantics: .applied,
            documentedErrors: [
                .init(reason: "fixtureRejected", description: "The fixture query was rejected.")
            ],
            isMutating: false,
            correlationPolicy: .notAccepted
        )
    }

    static func subscription() throws
        -> IPCMethodDescriptor<IPCDescriptorClientSubscriptionParameters, IPCDescriptorClientSubscriptionResult>
    {
        try IPCMethodDescriptor(
            name: "fixture.events.subscribe",
            description: "Subscribe to fixture events.",
            examples: [],
            exposure: .debugTesting,
            requiredPrivileges: [.eventsRead],
            dataScope: .unspecified,
            allowedTargetKinds: [],
            commandRelationship: .noInteractiveIdentity,
            executionOwner: .eventReader,
            principalAvailability: .authenticated,
            resultSemantics: .accepted,
            documentedErrors: [],
            isMutating: false,
            correlationPolicy: .notAccepted,
            responseDelivery: .subscription
        )
    }
}

struct IPCDescriptorClientQueryParameters: IPCSchemaProviding, Equatable {
    let query: String

    static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "query", description: "Exact fixture query", schema: .string(minimumLength: 1))
        ])
    }
}

struct IPCDescriptorClientQueryResult: IPCSchemaProviding, Equatable {
    let value: String

    static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "value", description: "Exact fixture result", schema: .string(minimumLength: 1))
        ])
    }
}

struct IPCDescriptorClientSubscriptionParameters: IPCSchemaProviding, Equatable {
    let eventName: String

    static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "eventName",
                description: "Fixture event name",
                schema: .string(allowedValues: ["fixture.changed"])
            )
        ])
    }
}

struct IPCDescriptorClientSubscriptionResult: IPCSchemaProviding, Equatable {
    let subscriptionId: UUID

    static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "subscriptionId",
                description: "Fixture subscription UUID",
                schema: IPCSchemaScalars.uuid
            )
        ])
    }
}

func makeIPCDescriptorClientInvocation<Parameters: Encodable>(
    descriptor: IPCAnyMethodDescriptor,
    parameters: Parameters
) throws -> IPCDescriptorInvocation {
    IPCDescriptorInvocation(
        descriptor: descriptor,
        normalizedParameters: try descriptor.normalizeParameters(JSONEncoder().encode(parameters)),
        presentation: .tooling
    )
}

func makeIPCDescriptorClientResponseFrame<Result: Encodable>(
    id: JSONRPCIdentifier?,
    result: Result
) throws -> Data {
    let resultValue = try JSONRPCCodec.encodeJSONValue(result)
    return try NDJSONFrameEncoder.encode(
        JSONRPCCodec.encodeResponse(.success(id: id, result: resultValue)),
        maxFrameBytes: 65_536
    )
}

func makeIPCDescriptorClientErrorFrame(
    id: JSONRPCIdentifier?,
    code: Int,
    message: String,
    data: JSONValue? = nil
) throws -> Data {
    try NDJSONFrameEncoder.encode(
        JSONRPCCodec.encodeResponse(
            .failure(
                id: id,
                error: JSONRPCErrorPayload(code: code, message: message, data: data)
            )
        ),
        maxFrameBytes: 65_536
    )
}

func makeIPCDescriptorClientNotificationFrame() throws -> Data {
    try NDJSONFrameEncoder.encode(
        JSONRPCCodec.encodeNotification(
            JSONRPCNotification(
                method: "events.notification",
                params: .object(["name": .string("fixture.changed")])
            )
        ),
        maxFrameBytes: 65_536
    )
}

func receiveIPCDescriptorClientRequest(
    connection: UnixSocketConnection,
    decoder: inout NDJSONFrameDecoder
) throws -> JSONRPCRequest {
    while true {
        let data = try connection.receive(maxBytes: 4096)
        let frames = try decoder.append(data)
        if let frame = frames.first {
            return try JSONRPCCodec.decodeRequest(frame)
        }
    }
}

func temporaryIPCDescriptorClientSocketPath() -> String {
    "/tmp/asipc-descriptor-\(UUIDv7.generate().uuidString.prefix(8)).sock"
}

final class IPCDescriptorClientLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    func set(_ value: Value) {
        lock.withLock { storedValue = value }
    }

    func value() -> Value {
        lock.withLock { storedValue }
    }
}

enum IPCDescriptorClientFixtureError: Error {
    case expectedFailure
}

func captureIPCDescriptorClientFailure(
    _ operation: () throws -> Void
) throws -> IPCDescriptorClientFailure {
    do {
        try operation()
    } catch let failure as IPCDescriptorClientFailure {
        return failure
    } catch {
        Issue.record("Expected IPCDescriptorClientFailure, received \(type(of: error))")
        throw error
    }
    Issue.record("Expected descriptor client call to fail")
    throw IPCDescriptorClientFixtureError.expectedFailure
}
