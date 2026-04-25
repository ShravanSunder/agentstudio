import Foundation

struct AgentStudioJSONLTraceEncoder: Sendable {
    func encodeLine(_ record: AgentStudioTraceRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        guard let line = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                record,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Agent Studio trace record did not encode as UTF-8 JSON"
                )
            )
        }
        return line + "\n"
    }
}
