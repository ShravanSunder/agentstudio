import AgentStudioIPCClientCore
import AgentStudioProgrammaticControl
import Foundation
import Testing

enum IPCDescriptorInvocationToolingDisplayMode: String, Codable, Sendable {
    case compact
    case expanded
}

struct IPCDescriptorInvocationToolingParameters: IPCSchemaProviding, Equatable {
    let retryCount: Int
    let isEnabled: Bool
    let displayName: String
    let displayMode: IPCDescriptorInvocationToolingDisplayMode
    let tags: [String]?
    let correlationId: UUID

    static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "retryCount",
                description: "Retry count from one through five",
                schema: .integer(minimum: 1, maximum: 5)
            ),
            .init(name: "isEnabled", description: "Whether the fixture is enabled", schema: .boolean),
            .init(
                name: "displayName",
                description: "Exact display name",
                schema: .string(minimumLength: 1, maximumLength: 80)
            ),
            .init(
                name: "displayMode",
                description: "Display mode",
                schema: .string(allowedValues: ["compact", "expanded"]),
                presence: try .defaulted("compact")
            ),
            .optional(
                "tags",
                description: "Optional structured tags",
                schema: .array(items: .string(minimumLength: 1), maximumCount: 3)
            ),
            .init(
                name: "correlationId",
                description: "Logical mutation UUID",
                schema: IPCSchemaScalars.uuid
            ),
        ])
    }
}

struct IPCDescriptorInvocationMessageParameters: IPCSchemaProviding, Equatable {
    let text: String
    let correlationId: UUID

    static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "text", description: "Exact private message text", schema: .string()),
            .init(
                name: "correlationId",
                description: "Logical mutation UUID",
                schema: IPCSchemaScalars.uuid
            ),
        ])
    }
}

enum IPCDescriptorInvocationReportOperation: String, Codable, Sendable {
    case needsYou
    case clear
    case done
}

struct IPCDescriptorInvocationReportParameters: IPCSchemaProviding, Equatable {
    let operation: IPCDescriptorInvocationReportOperation
    let explanation: String?
    let correlationId: UUID

    static func ipcSchema() throws -> IPCJSONSchema {
        .oneOf([
            reportSchema(operation: .needsYou, includesExplanation: true),
            reportSchema(operation: .clear, includesExplanation: false),
            reportSchema(operation: .done, includesExplanation: false),
        ])
    }

    private static func reportSchema(
        operation: IPCDescriptorInvocationReportOperation,
        includesExplanation: Bool
    ) -> IPCJSONSchema {
        var fields = [
            IPCObjectField(
                name: "operation",
                description: "Report operation",
                schema: .string(allowedValues: [operation.rawValue])
            )
        ]
        if includesExplanation {
            fields.append(
                .init(
                    name: "explanation",
                    description: "Exact private explanation",
                    schema: .string()
                )
            )
        }
        fields.append(
            .init(
                name: "correlationId",
                description: "Logical mutation UUID",
                schema: IPCSchemaScalars.uuid
            )
        )
        return .object(fields: fields)
    }
}

struct IPCDescriptorInvocationFixtureResult: IPCSchemaProviding, Equatable {
    let disposition: String

    static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "disposition",
                description: "Fixture disposition",
                schema: .string(allowedValues: ["accepted"])
            )
        ])
    }
}

final class IPCDescriptorInvocationCorrelationGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private let correlationID: UUID
    private var storedInvocationCount = 0

    init(_ correlationID: UUID) {
        self.correlationID = correlationID
    }

    var invocationCount: Int {
        lock.withLock { storedInvocationCount }
    }

    func generate() -> UUID {
        lock.withLock {
            storedInvocationCount += 1
        }
        return correlationID
    }
}

enum IPCDescriptorInvocationFixtureError: Error {
    case expectedParserFailure
}

func captureIPCDescriptorInvocationError(
    _ operation: () throws -> IPCDescriptorInvocation
) throws -> IPCDescriptorInvocationError {
    do {
        _ = try operation()
    } catch let error as IPCDescriptorInvocationError {
        return error
    } catch {
        Issue.record("Expected IPCDescriptorInvocationError, received \(type(of: error))")
        throw error
    }
    Issue.record("Expected descriptor invocation parsing to fail")
    throw IPCDescriptorInvocationFixtureError.expectedParserFailure
}

func decodeIPCDescriptorInvocationParameters<Value: Decodable>(
    _ type: Value.Type,
    from data: Data
) throws -> Value {
    try JSONDecoder().decode(type, from: data)
}

extension IPCDescriptorInvocationPresentation {
    var modelInvocation: IPCModelInvocationPresentation? {
        guard case .model(let presentation) = self else { return nil }
        return presentation
    }
}
