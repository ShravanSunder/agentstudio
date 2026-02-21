import Foundation

/// Type-erased command result container for typed JSON-RPC method handlers.
public struct RPCNoResponse: Codable, Sendable {}

/// Protocol for strongly-typed JSON-RPC methods.
///
/// Typed methods bind the request `Params` type to a handler and allow
/// decoding-time validation instead of ad-hoc dictionary inspection.
public protocol RPCMethod {
    associatedtype Params: Decodable
    associatedtype Result: Encodable

    /// JSON-RPC method name.
    static var method: String { get }

    /// Decode method params from the raw `params` payload.
    ///
    /// Implementations can enforce custom decoding rules by overriding this method.
    static func decodeParams(from data: Data?) throws -> Params

    /// Erased handler construction for registration in a method-name keyed router map.
    static func makeHandler(
        _ handler: @escaping (Params) async throws -> Result?
    ) -> any AnyRPCMethodHandler
}

public protocol AnyRPCMethodHandler: Sendable {
    func run(id: RPCIdentifier?, paramsData: Data?) async throws -> Encodable?
}

public extension RPCMethod {
    /// Default payload decoding behavior for JSON-RPC parameters:
    /// decode from `data` when present, otherwise decode `{}`.
    static func decodeParams(from data: Data?) throws -> Params {
        let source = data ?? Data("{}".utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(Params.self, from: source)
    }

    /// Default typed handler adapter.
    static func makeHandler(
        _ handler: @escaping (Params) async throws -> Result?
    ) -> any AnyRPCMethodHandler {
        TypedRPCMethodHandler<Self>(handler)
    }
}

/// Sends a typed handler through a non-generic registration surface.
private struct TypedRPCMethodHandler<Method: RPCMethod>: AnyRPCMethodHandler {
    private let handler: @Sendable (Method.Params) async throws -> Method.Result?

    init(_ handler: @escaping @Sendable (Method.Params) async throws -> Method.Result?) {
        self.handler = handler
    }

    func run(id: RPCIdentifier?, paramsData: Data?) async throws -> Encodable? {
        let params = try Method.decodeParams(from: paramsData)
        return try await handler(params)
    }
}

/// JSON-RPC id parity contract.
public enum RPCIdentifier: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case null
}
