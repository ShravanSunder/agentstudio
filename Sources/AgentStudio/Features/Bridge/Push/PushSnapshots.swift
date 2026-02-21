import Foundation

/// Wire payload for diff status push (section 6.8).
/// Pushed to React on `.hot` level — immediate user feedback for loading states.
struct DiffStatusSlice: Encodable, Equatable {
    let status: DiffStatus
    let error: String?
    let epoch: Int
}

/// Wire payload for connection health push (section 6.8).
/// Pushed on `.hot` level — connection changes need immediate UI response.
struct ConnectionSlice: Encodable, Equatable {
    let health: ConnectionState.ConnectionHealth
    let latencyMs: Int
}
