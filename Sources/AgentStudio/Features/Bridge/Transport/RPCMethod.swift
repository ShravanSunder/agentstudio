import Foundation

/// Explicit empty response type for methods that intentionally return no payload.
struct RPCNoResponse: Codable, Sendable {}

/// Protocol for strongly-typed JSON-RPC methods.
///
/// Typed methods bind the request `Params` type to a handler and allow
/// decoding-time validation instead of ad-hoc dictionary inspection.
protocol RPCMethod {
    associatedtype Params: Decodable, Sendable
    associatedtype Result: Encodable, Sendable

    /// JSON-RPC method name.
    static var method: String { get }

    /// Decode method params from the raw `params` payload.
    ///
    /// Implementations can enforce custom decoding rules by overriding this method.
    static func decodeParams(from data: Data?) throws -> Params

    /// Erased handler construction for registration in a method-name keyed router map.
    static func makeHandler(
        _ handler: @escaping @MainActor @Sendable (Params) async throws -> Result?
    ) -> any AnyRPCMethodHandler
}

protocol AnyRPCMethodHandler: Sendable {
    func run(id: RPCIdentifier?, paramsData: Data?) async throws -> Encodable?
}

enum RPCMethodDispatchError: Error, Sendable {
    case invalidParams(Error)
    case handlerFailure(Error)
}

extension RPCMethod {
    /// Default payload decoding behavior for JSON-RPC parameters:
    /// decode from `data` when present, otherwise decode `{}`.
    static func decodeParams(from data: Data?) throws -> Params {
        let source = data ?? Data("{}".utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(Params.self, from: source)
    }

    /// Default typed handler adapter.
    static func makeHandler(
        _ handler: @escaping @MainActor @Sendable (Params) async throws -> Result?
    ) -> any AnyRPCMethodHandler {
        TypedRPCMethodHandler<Self>(handler)
    }
}

/// Adapts a typed method handler to a non-generic registration surface.
private struct TypedRPCMethodHandler<Method: RPCMethod>: AnyRPCMethodHandler {
    private let handler: @MainActor @Sendable (Method.Params) async throws -> Method.Result?

    init(_ handler: @escaping @MainActor @Sendable (Method.Params) async throws -> Method.Result?) {
        self.handler = handler
    }

    func runWithDecode(_ paramsData: Data?) throws -> Method.Params {
        do {
            return try Method.decodeParams(from: paramsData)
        } catch {
            throw RPCMethodDispatchError.invalidParams(error)
        }
    }

    func run(id: RPCIdentifier?, paramsData: Data?) async throws -> Encodable? {
        let params = try runWithDecode(paramsData)
        do {
            return try await handler(params)
        } catch {
            throw RPCMethodDispatchError.handlerFailure(error)
        }
    }
}

/// JSON-RPC id parity contract.
enum RPCIdentifier: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let integer = try? container.decode(Int64.self) {
            self = .integer(integer)
            return
        }
        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "RPC identifier must be a string, integer, float, or null"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
