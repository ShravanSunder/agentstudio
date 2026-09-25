import Foundation

enum BridgeProductOperationWaitKind: String, Codable, Equatable, Sendable {
    case ordinary
    case human
}

enum BridgeProductOperationSettlement: String, Codable, Equatable, Sendable {
    case succeeded
    case refused
    case failed
    case outcomeUnknown
    case cancelled
}

/// A sequenced control reply acknowledges only admission. The operation's effect
/// is returned by a separate, unsequenced result read.
struct BridgeProductOperationAdmittedResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case operationId
        case waitKind
    }

    let correlation: BridgeProductControlCorrelation
    let operationId: String
    let waitKind: BridgeProductOperationWaitKind

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "operation.admitted response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "operation.admitted" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid operation.admitted response kind",
                codingPath: decoder.codingPath
            )
        }
        correlation = try BridgeProductControlCorrelation(from: decoder)
        operationId = try container.decode(String.self, forKey: .operationId)
        waitKind = try container.decode(BridgeProductOperationWaitKind.self, forKey: .waitKind)
        try BridgeProductContractDecoding.validateIdentifier(operationId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try correlation.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("operation.admitted", forKey: .kind)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(waitKind, forKey: .waitKind)
    }
}

/// Result reads bypass the sequenced admission chain so a held result cannot
/// delay another control or an escape request.
struct BridgeProductOperationResultRequest: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case operationId
        case paneSessionId
        case wireVersion
        case workerInstanceId
    }

    let operationId: String
    let paneSessionId: String
    let wireVersion: Int
    let workerInstanceId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "operation.result request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "operation.result" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid operation.result request kind",
                codingPath: decoder.codingPath
            )
        }
        operationId = try container.decode(String.self, forKey: .operationId)
        paneSessionId = try container.decode(String.self, forKey: .paneSessionId)
        wireVersion = try container.decode(Int.self, forKey: .wireVersion)
        workerInstanceId = try container.decode(String.self, forKey: .workerInstanceId)
        try BridgeProductContractDecoding.validateIdentifier(operationId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateWireVersion(wireVersion, codingPath: decoder.codingPath)
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("operation.result", forKey: .kind)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(paneSessionId, forKey: .paneSessionId)
        try container.encode(wireVersion, forKey: .wireVersion)
        try container.encode(workerInstanceId, forKey: .workerInstanceId)
    }
}

struct BridgeProductOperationResultResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case failureCode
        case kind
        case operationId
        case outcome
        case result
    }

    let failureCode: BridgeProductRequestErrorCode?
    let operationId: String
    let outcome: BridgeProductOperationSettlement
    let result: BridgeProductJSONValue?

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: Set(CodingKeys.allCases.map(\.rawValue)),
            contract: "operation.result response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "operation.result" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid operation.result response kind",
                codingPath: decoder.codingPath
            )
        }
        failureCode = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeProductRequestErrorCode.self,
            forKey: .failureCode,
            from: container,
            codingPath: decoder.codingPath
        )
        operationId = try container.decode(String.self, forKey: .operationId)
        outcome = try container.decode(BridgeProductOperationSettlement.self, forKey: .outcome)
        result = try BridgeProductContractDecoding.decodeRequiredNullable(
            BridgeProductJSONValue.self,
            forKey: .result,
            from: container,
            codingPath: decoder.codingPath
        )
        try BridgeProductContractDecoding.validateIdentifier(operationId, codingPath: decoder.codingPath)
        guard result == nil || outcome == .succeeded else {
            throw BridgeProductContractDecoding.invalidValue(
                "A non-successful operation cannot carry a result",
                codingPath: decoder.codingPath
            )
        }
        guard outcome == .refused || outcome == .failed || failureCode == nil else {
            throw BridgeProductContractDecoding.invalidValue(
                "Only a refused or failed operation carries a failure code",
                codingPath: decoder.codingPath
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(failureCode, forKey: .failureCode)
        try container.encode("operation.result", forKey: .kind)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(result, forKey: .result)
    }
}

struct BridgeProductOperationResultAcknowledgement: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case operationId
    }

    let correlation: BridgeProductControlCorrelation
    let operationId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "operation.resultAcknowledgement request"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "operation.resultAcknowledgement" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid operation.resultAcknowledgement request kind",
                codingPath: decoder.codingPath
            )
        }
        correlation = try BridgeProductControlCorrelation(from: decoder)
        operationId = try container.decode(String.self, forKey: .operationId)
        try BridgeProductContractDecoding.validateIdentifier(operationId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try correlation.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("operation.resultAcknowledgement", forKey: .kind)
        try container.encode(operationId, forKey: .operationId)
    }
}

struct BridgeProductOperationResultAcknowledgedResponse: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case operationId
    }

    let correlation: BridgeProductControlCorrelation
    let operationId: String

    init(from decoder: Decoder) throws {
        try BridgeProductContractDecoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: BridgeProductControlCorrelation.codingKeyNames.union(
                CodingKeys.allCases.map(\.rawValue)
            ),
            contract: "operation.resultAcknowledged response"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .kind) == "operation.resultAcknowledged" else {
            throw BridgeProductContractDecoding.invalidValue(
                "Invalid operation.resultAcknowledged response kind",
                codingPath: decoder.codingPath
            )
        }
        correlation = try BridgeProductControlCorrelation(from: decoder)
        operationId = try container.decode(String.self, forKey: .operationId)
        try BridgeProductContractDecoding.validateIdentifier(operationId, codingPath: decoder.codingPath)
    }

    func encode(to encoder: Encoder) throws {
        try correlation.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("operation.resultAcknowledged", forKey: .kind)
        try container.encode(operationId, forKey: .operationId)
    }
}
