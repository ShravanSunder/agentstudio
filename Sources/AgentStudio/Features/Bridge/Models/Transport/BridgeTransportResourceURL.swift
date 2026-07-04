import Foundation

struct BridgeTransportResourceURL: Equatable, Sendable {
    let protocolId: String
    let resourceKind: String
    let opaqueId: String
    let generation: Int?
    let revision: Int?
    let cursor: String?
    let canonicalURL: String

    static func parse(
        _ resourceURL: String,
        allowedResourceKindsByProtocol: [String: Set<String>]
    ) -> Self? {
        guard
            let components = URLComponents(string: resourceURL),
            components.scheme == "agentstudio",
            components.host == "resource",
            let pathSegments = parsePathSegments(components.percentEncodedPath),
            pathSegments.count == 3
        else {
            return nil
        }

        let protocolId = pathSegments[0]
        let resourceKind = pathSegments[1]
        let opaqueId = pathSegments[2]
        guard allowedResourceKindsByProtocol[protocolId]?.contains(resourceKind) == true else {
            return nil
        }

        guard let queryValues = parseQueryValues(components.queryItems ?? []) else {
            return nil
        }
        let generation = parseOptionalNonnegativeInteger(queryValues["generation"].flatMap { $0 })
        let revision = parseOptionalNonnegativeInteger(queryValues["revision"].flatMap { $0 })
        let cursor = parseOptionalCursor(queryValues["cursor"].flatMap { $0 })
        let interest = parseOptionalContentDemandInterest(
            queryValues[BridgeContentDemandInterest.queryKey].flatMap { $0 })
        guard generation != nil || queryValues["generation"] == nil,
            revision != nil || queryValues["revision"] == nil,
            cursor != nil || queryValues["cursor"] == nil,
            interest != nil || queryValues[BridgeContentDemandInterest.queryKey] == nil
        else {
            return nil
        }

        return Self(
            protocolId: protocolId,
            resourceKind: resourceKind,
            opaqueId: opaqueId,
            generation: generation,
            revision: revision,
            cursor: cursor,
            canonicalURL: canonicalURL(
                protocolId: protocolId,
                resourceKind: resourceKind,
                opaqueId: opaqueId,
                generation: generation,
                revision: revision,
                cursor: cursor
            )
        )
    }

    private static func parsePathSegments(_ percentEncodedPath: String) -> [String]? {
        guard let decodedPath = stablePercentDecode(percentEncodedPath),
            !hasTraversalSegment(decodedPath)
        else {
            return nil
        }
        var segments: [String] = []
        for rawSegment in percentEncodedPath.split(separator: "/") where !rawSegment.isEmpty {
            guard let decodedSegment = stablePercentDecode(String(rawSegment)),
                !decodedSegment.isEmpty,
                !decodedSegment.contains("/"),
                !hasTraversalSegment(decodedSegment)
            else {
                return nil
            }
            segments.append(decodedSegment)
        }
        return segments
    }

    private static func stablePercentDecode(_ value: String) -> String? {
        var current = value
        var previous: String?
        while current != previous {
            previous = current
            guard let decoded = current.removingPercentEncoding else {
                return nil
            }
            current = decoded
        }
        return current
    }

    private static func hasTraversalSegment(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: false).contains { segment in
            segment == "." || segment == ".."
        }
    }

    private static func parseQueryValues(_ queryItems: [URLQueryItem]) -> [String: String?]? {
        let allowedKeys = Set(["generation", "revision", "cursor", BridgeContentDemandInterest.queryKey])
        var values: [String: String?] = [:]
        for item in queryItems {
            guard allowedKeys.contains(item.name), values[item.name] == nil else {
                return nil
            }
            values[item.name] = item.value
        }
        return values
    }

    private static func parseOptionalNonnegativeInteger(_ value: String?) -> Int? {
        guard let value else {
            return nil
        }
        guard value == "0" || (value.first != "0" && value.allSatisfy(\.isNumber)),
            let parsedValue = Int(value)
        else {
            return nil
        }
        return parsedValue
    }

    private static func parseOptionalCursor(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        guard !value.isEmpty else {
            return nil
        }
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
        return value.rangeOfCharacter(from: allowedCharacters.inverted) == nil ? value : nil
    }

    private static func parseOptionalContentDemandInterest(_ value: String?) -> BridgeContentDemandInterest? {
        guard let value else {
            return nil
        }
        return BridgeContentDemandInterest.parseQueryValue(value)
    }

    private static func canonicalURL(
        protocolId: String,
        resourceKind: String,
        opaqueId: String,
        generation: Int?,
        revision: Int?,
        cursor: String?
    ) -> String {
        var queryParts: [String] = []
        if let generation {
            queryParts.append("generation=\(generation)")
        }
        if let revision {
            queryParts.append("revision=\(revision)")
        }
        if let cursor {
            queryParts.append("cursor=\(percentEncode(cursor))")
        }
        let query = queryParts.isEmpty ? "" : "?\(queryParts.joined(separator: "&"))"
        let encodedPath = [
            percentEncode(protocolId),
            percentEncode(resourceKind),
            percentEncode(opaqueId),
        ].joined(separator: "/")
        return "agentstudio://resource/\(encodedPath)\(query)"
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
