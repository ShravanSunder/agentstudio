import Foundation

enum BridgeProductRequestBodySource: String, Equatable, Sendable {
    case unread
    case missing
    case httpBody = "http_body"
    case httpBodyStream = "http_body_stream"
}

enum BridgeProductBoundedRequestBodyRead: Equatable, Sendable {
    case missing
    case invalid(source: BridgeProductRequestBodySource, observedByteCount: Int)
    case oversized(source: BridgeProductRequestBodySource, observedByteCount: Int)
    case body(Data, source: BridgeProductRequestBodySource)
}

struct BridgeProductBoundedRequestBodyReader: Sendable {
    let maximumBytes: Int

    init(maximumBytes: Int = BridgeProductWireContract.maximumRequestBodyBytes) {
        precondition(maximumBytes > 0)
        precondition(maximumBytes <= BridgeProductWireContract.maximumRequestBodyBytes)
        self.maximumBytes = maximumBytes
    }

    func read(_ request: URLRequest) -> BridgeProductBoundedRequestBodyRead {
        if let body = request.httpBody {
            let observed = Data(body.prefix(maximumBytes + 1))
            return body.count > maximumBytes
                ? .oversized(source: .httpBody, observedByteCount: observed.count)
                : .body(observed, source: .httpBody)
        }
        guard let stream = request.httpBodyStream else { return .missing }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(8192, maximumBytes + 1))
        while data.count <= maximumBytes {
            let remaining = maximumBytes + 1 - data.count
            let readCount = stream.read(&buffer, maxLength: min(buffer.count, remaining))
            if readCount < 0 {
                return .invalid(source: .httpBodyStream, observedByteCount: data.count)
            }
            if readCount == 0 { break }
            data.append(buffer, count: readCount)
        }
        return data.count > maximumBytes
            ? .oversized(source: .httpBodyStream, observedByteCount: data.count)
            : .body(data, source: .httpBodyStream)
    }
}
