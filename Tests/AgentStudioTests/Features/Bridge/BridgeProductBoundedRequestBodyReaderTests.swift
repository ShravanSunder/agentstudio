import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge product bounded request body reader")
struct BridgeProductBoundedRequestBodyReaderTests {
    @Test("httpBody accepts the exact ceiling and retains no oversize tail")
    func httpBodyIsBoundedAtCapPlusOne() {
        // Arrange
        let maximumBytes = 32
        let reader = BridgeProductBoundedRequestBodyReader(maximumBytes: maximumBytes)
        var exactRequest = URLRequest(url: URL(string: BridgeProductWireContract.commandRoute)!)
        exactRequest.httpBody = Data(repeating: 0x61, count: maximumBytes)
        var oversizedRequest = URLRequest(url: URL(string: BridgeProductWireContract.commandRoute)!)
        oversizedRequest.httpBody = Data(repeating: 0x62, count: maximumBytes * 4)

        // Act
        let exactRead = reader.read(exactRequest)
        let oversizedRead = reader.read(oversizedRequest)

        // Assert
        #expect(
            exactRead
                == .body(
                    Data(repeating: 0x61, count: maximumBytes),
                    source: .httpBody
                )
        )
        #expect(
            oversizedRead
                == .oversized(
                    source: .httpBody,
                    observedByteCount: maximumBytes + 1
                )
        )
    }

    @Test("httpBodyStream accepts the exact ceiling without Content-Length")
    func httpBodyStreamAcceptsMissingDeclaredLength() {
        // Arrange
        let maximumBytes = 32
        let body = Data(repeating: 0x63, count: maximumBytes)
        let reader = BridgeProductBoundedRequestBodyReader(maximumBytes: maximumBytes)
        var request = URLRequest(url: URL(string: BridgeProductWireContract.streamRoute)!)
        request.httpBodyStream = InputStream(data: body)

        // Act
        let read = reader.read(request)

        // Assert
        #expect(request.value(forHTTPHeaderField: "Content-Length") == nil)
        #expect(read == .body(body, source: .httpBodyStream))
    }

    @Test("httpBodyStream observes at most cap plus one before oversize rejection")
    func httpBodyStreamRejectsAtCapPlusOne() {
        // Arrange
        let maximumBytes = 32
        let reader = BridgeProductBoundedRequestBodyReader(maximumBytes: maximumBytes)
        var request = URLRequest(url: URL(string: BridgeProductWireContract.contentRoute)!)
        request.httpBodyStream = InputStream(data: Data(repeating: 0x64, count: maximumBytes * 4))

        // Act
        let read = reader.read(request)

        // Assert
        #expect(
            read
                == .oversized(
                    source: .httpBodyStream,
                    observedByteCount: maximumBytes + 1
                )
        )
    }

    @Test("missing body is rejected without fabrication")
    func missingBodyIsExplicit() {
        // Arrange
        let reader = BridgeProductBoundedRequestBodyReader(maximumBytes: 32)
        let request = URLRequest(url: URL(string: BridgeProductWireContract.commandRoute)!)

        // Act
        let read = reader.read(request)

        // Assert
        #expect(read == .missing)
    }
}
