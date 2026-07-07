import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class BridgeBrowserNativeRPCCutoverSourceScanTests {
    @Test
    func scriptMessageRPCPlane_isCompileDeadExceptOneShotPageLoadBootstrap() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let scannedRoots = [
            "BridgeWeb/src",
            "Sources/AgentStudio",
            "Sources/AgentStudio/Resources/BridgeWeb/app",
            "Tests/AgentStudioTests",
        ]
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "Sources/AgentStudio/Resources/BridgeWeb/app").path
            ),
            "Packaged BridgeWeb app assets must exist so the G6 source scan covers the shipped runtime, not only TypeScript source."
        )
        let allowedNegativeProofFiles: Set<String> = [
            "BridgeWeb/src/app/bridge-app-dev-telemetry.unit.test.ts",
            "BridgeWeb/src/app/bridge-app-dev-worktree-review.unit.test.ts",
            "BridgeWeb/src/bridge/bridge-page-handshake.unit.test.ts",
            "Tests/AgentStudioTests/Features/Bridge/BridgeBootstrapTests.swift",
            "Tests/AgentStudioTests/Features/Bridge/BridgeBrowserNativeRPCCutoverSourceScanTests.swift",
            "Tests/AgentStudioTests/Features/Bridge/BridgeContentWorldIsolationTests.swift",
        ]
        let bootstrapSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift"),
            encoding: .utf8
        )

        let allowedDirectPrivilegedRPCRelayFiles: Set<String> = [
            "Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift",
            "Tests/AgentStudioTests/Features/Bridge/BridgeBrowserNativeRPCCutoverSourceScanTests.swift",
            "Tests/AgentStudioTests/Features/Bridge/BridgeWebKitSpikeTests.swift",
        ]

        let violations = try scannedRoots.flatMap { root in
            try sourceFiles(in: projectRoot.appending(path: root)).flatMap { fileURL -> [String] in
                let relativePath = relativePath(for: fileURL, under: projectRoot)
                guard !allowedNegativeProofFiles.contains(relativePath) else {
                    return []
                }
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                return forbiddenOrdinaryRPCMatches(in: source).map { "\(relativePath): \($0)" }
            }
        }
        #expect(
            violations.isEmpty,
            "Ordinary script-message RPC markers survived outside the one-shot bootstrap/negative-proof allowlist: \(violations.joined(separator: ", "))"
        )

        let directPrivilegedRPCRelayViolations = try scannedRoots.flatMap { root in
            try sourceFiles(in: projectRoot.appending(path: root)).compactMap { fileURL -> String? in
                let relativePath = relativePath(for: fileURL, under: projectRoot)
                guard !allowedDirectPrivilegedRPCRelayFiles.contains(relativePath) else {
                    return nil
                }
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let matches = directPrivilegedRPCRelayMatches(in: source)
                return matches.isEmpty
                    ? nil
                    : "\(relativePath): \(matches.joined(separator: ", "))"
            }
        }
        #expect(
            directPrivilegedRPCRelayViolations.isEmpty,
            "Direct WKScriptMessage rpc relay survived outside bootstrap/negative-proof allowlist: \(directPrivilegedRPCRelayViolations.joined(separator: ", "))"
        )

        let bootstrapRelayCount = directPrivilegedRPCRelayMatches(in: bootstrapSource).count
        #expect(bootstrapRelayCount == 1)
        let readyListenerRange = try #require(
            bootstrapSource.range(of: "document.addEventListener('__bridge_ready'")
        )
        let readyMethodRange = try #require(bootstrapSource.range(of: "method: 'bridge.ready'"))
        let directRelayRange = try #require(bootstrapSource.range(of: "messageHandlers.rpc.postMessage"))
        #expect(readyListenerRange.lowerBound < readyMethodRange.lowerBound)
        #expect(readyListenerRange.lowerBound < directRelayRange.lowerBound)
    }

    @Test
    func forbiddenRPCSourceScanDetectsAlternateSpellings() {
        let alternateSpellings = [
            #"document.addEventListener("__bridge_command", handler)"#,
            #"window.webkit.messageHandlers["rpc"].postMessage(payload)"#,
            #"window.webkit?.messageHandlers?.rpc?.postMessage(payload)"#,
            #"const handlers = window.webkit.messageHandlers; handlers.rpc.postMessage(payload)"#,
        ]

        for source in alternateSpellings.prefix(1) {
            #expect(
                !forbiddenOrdinaryRPCMatches(in: source).isEmpty,
                "Expected alternate script-message RPC spelling to be flagged: \(source)"
            )
        }
        for source in alternateSpellings.dropFirst() {
            #expect(
                !directPrivilegedRPCRelayMatches(in: source).isEmpty,
                "Expected alternate direct WKScriptMessage rpc relay spelling to be flagged: \(source)"
            )
        }
    }

    private func sourceFiles(in root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else {
                continue
            }
            switch fileURL.pathExtension {
            case "html", "js", "json", "swift", "ts", "tsx":
                files.append(fileURL)
            default:
                continue
            }
        }
        return files
    }

    private func relativePath(for fileURL: URL, under projectRoot: URL) -> String {
        let rootPath = projectRoot.path.hasSuffix("/") ? projectRoot.path : "\(projectRoot.path)/"
        guard fileURL.path.hasPrefix(rootPath) else {
            return fileURL.path
        }
        return String(fileURL.path.dropFirst(rootPath.count))
    }

    private func forbiddenOrdinaryRPCMatches(in source: String) -> [String] {
        let forbiddenOrdinaryRPCMarkers = [
            "sendCommandJSON: function(commandJSON)",
            "__bridge_response",
            "data-bridge-nonce",
            "bridge-content-world-rpc",
            "RPCMessageHandler",
            "PAGE_WORLD_ALLOWED_COMMAND_METHODS",
            "pageWorldLegacy",
        ]
        var matches = forbiddenOrdinaryRPCMarkers.filter { source.contains($0) }
        if source.contains("__bridge_command") {
            matches.append("__bridge_command")
        }
        return matches
    }

    private func directPrivilegedRPCRelayMatches(in source: String) -> [String] {
        let normalizedSource =
            source
            .replacingOccurrences(of: #"[\s\n\r\t]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: #"["rpc"]"#, with: ".rpc")
            .replacingOccurrences(of: #"['rpc']"#, with: ".rpc")
        let rpcPostMessagePattern = #"[A-Za-z_$][A-Za-z0-9_$]*\.rpc\.postMessage"#
        guard normalizedSource.range(of: rpcPostMessagePattern, options: .regularExpression) != nil else {
            return []
        }
        return ["rpc.postMessage"]
    }
}
