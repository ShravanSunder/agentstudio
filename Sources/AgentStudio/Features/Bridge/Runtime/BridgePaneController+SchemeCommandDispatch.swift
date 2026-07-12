import CoreFoundation
import Foundation

extension BridgePaneController {
    struct SchemeRPCBootstrapOnlyRejection: Sendable {
        let responseJSON: String?
    }

    nonisolated static func schemeRPCBootstrapOnlyRejection(for json: String)
        -> SchemeRPCBootstrapOnlyRejection?
    {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            dictionary["method"] as? String == BridgeReadyMethod.method
        else {
            return nil
        }

        guard dictionary.keys.contains("id") else {
            return SchemeRPCBootstrapOnlyRejection(
                responseJSON: makeSchemeRPCErrorResponse(
                    id: NSNull(),
                    code: -32_600,
                    message: "Invalid request"
                )
            )
        }
        guard let responseID = schemeRPCResponseIDValue(from: dictionary["id"]) else {
            return SchemeRPCBootstrapOnlyRejection(
                responseJSON: makeSchemeRPCErrorResponse(
                    id: NSNull(),
                    code: -32_600,
                    message: "Invalid request: invalid id"
                )
            )
        }
        return SchemeRPCBootstrapOnlyRejection(
            responseJSON: makeSchemeRPCErrorResponse(
                id: responseID,
                code: -32_601,
                message: "bridge.ready is bootstrap-only"
            )
        )
    }

    private nonisolated static func makeSchemeRPCErrorResponse(id: Any, code: Int, message: String) -> String? {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message,
            ],
        ]
        guard JSONSerialization.isValidJSONObject(envelope),
            let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func schemeRPCResponseIDValue(from id: Any?) -> Any? {
        guard let id else {
            return nil
        }
        if let string = id as? String {
            return string
        }
        if let number = id as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number
        }
        if id is NSNull {
            return NSNull()
        }
        return nil
    }
}
