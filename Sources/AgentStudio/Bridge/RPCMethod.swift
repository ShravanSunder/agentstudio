import Foundation

/// Protocol for defining RPC methods with typed params.
///
/// Each method declares its name and parameter type. Conforming types
/// describe the shape of a single JSON-RPC method the bridge accepts.
///
/// Design doc §5.1 — command format.
protocol RPCMethod {
    associatedtype Params: Decodable
    associatedtype Result: Encodable = Never
    static var method: String { get }
}

/// Empty params for methods that take no arguments.
struct EmptyParams: Codable {}

/// Type-erased method handler for dynamic dispatch.
///
/// Wraps a handler closure that receives raw `Data?` params and returns
/// optional `Data?` result, enabling the router to store heterogeneous
/// handlers in a single dictionary.
struct AnyMethodHandler {
    let handle: (_ paramsData: Data?) async throws -> Data?

    init(handler: @escaping (Data?) async throws -> Data?) {
        self.handle = handler
    }
}
