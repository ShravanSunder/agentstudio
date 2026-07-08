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
    func productionRPCRouter_isCompileDeadForSchemeCommandDispatch() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let productionSourceRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let violations = try sourceFiles(in: productionSourceRoot).compactMap { fileURL -> String? in
            let relativePath = relativePath(for: fileURL, under: projectRoot)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let matches = [
                "RPCRouter",
                "dispatchForSchemeRPC",
                "handleIncomingRPC(",
            ].filter { source.contains($0) }
            return matches.isEmpty ? nil : "\(relativePath): \(matches.joined(separator: ", "))"
        }

        #expect(
            violations.isEmpty,
            "Production ordinary scheme command dispatch must not route through RPCRouter: \(violations.joined(separator: ", "))"
        )
    }

    @Test
    func forbiddenRPCSourceScanDetectsAlternateSpellings() {
        let alternateSpellings = [
            #"document.addEventListener("__bridge_command", handler)"#,
            #"window.webkit.messageHandlers["rpc"].postMessage(payload)"#,
            #"window.webkit?.messageHandlers?.rpc?.postMessage(payload)"#,
            #"const handlers = window.webkit.messageHandlers; handlers.rpc.postMessage(payload)"#,
            #"const handler = window.webkit.messageHandlers.rpc; handler.postMessage(payload)"#,
            #"const { rpc } = window.webkit.messageHandlers; rpc.postMessage(payload)"#,
            #"const wk = window.webkit; wk.messageHandlers.rpc.postMessage(payload)"#,
            #"const { messageHandlers } = window.webkit; messageHandlers.rpc.postMessage(payload)"#,
            #"const { messageHandlers: handlers } = window.webkit; handlers.rpc.postMessage(payload)"#,
            #"const { webkit } = window; webkit.messageHandlers.rpc.postMessage(payload)"#,
            #"const { webkit: wk } = window; wk.messageHandlers.rpc.postMessage(payload)"#,
            #"const { postMessage } = window.webkit.messageHandlers.rpc; postMessage(payload)"#,
            #"const { postMessage: sendRPC } = window.webkit.messageHandlers.rpc; sendRPC(payload)"#,
            #"const { postMessage: sendRPC } = window.webkit.messageHandlers.rpc; sendRPC?.(payload)"#,
            #"const { rpc: { postMessage } } = window.webkit.messageHandlers; postMessage(payload)"#,
            #"const { rpc: { postMessage: sendRPC } } = window.webkit.messageHandlers; sendRPC(payload)"#,
            #"const { messageHandlers: { rpc: { postMessage } } } = window.webkit; postMessage(payload)"#,
            #"const { messageHandlers: { rpc: { postMessage: sendRPC } } } = window.webkit; sendRPC(payload)"#,
            #"const { messageHandlers: { rpc } } = window.webkit; rpc.postMessage(payload)"#,
            #"const { messageHandlers: { rpc: sendRPC } } = window.webkit; sendRPC.postMessage(payload)"#,
            #"const { webkit: { messageHandlers: { rpc: { postMessage } } } } = window; postMessage(payload)"#,
            #"const { webkit: { messageHandlers: { rpc: { postMessage: sendRPC } } } } = window; sendRPC(payload)"#,
            #"const wk = window; wk.webkit.messageHandlers.rpc.postMessage(payload)"#,
            #"window["webkit"]["messageHandlers"]["rpc"]["postMessage"](payload)"#,
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
            .replacingOccurrences(of: #"?.("#, with: #"("#)
            .replacingOccurrences(of: "?", with: "")
            .bridgeNormalizedJavaScriptPropertyAccess("webkit")
            .bridgeNormalizedJavaScriptPropertyAccess("messageHandlers")
            .bridgeNormalizedJavaScriptPropertyAccess("rpc")
            .bridgeNormalizedJavaScriptPropertyAccess("postMessage")
        return Self.directPrivilegedRPCRelayPatterns.compactMap { label, pattern in
            normalizedSource.range(of: pattern, options: .regularExpression) == nil ? nil : label
        }
    }

    private static let directPrivilegedRPCRelayPatterns: [(label: String, pattern: String)] = [
        (
            "window.webkit.messageHandlers.rpc.postMessage",
            #"window\.webkit\.messageHandlers\.rpc\.postMessage"#
        ),
        (
            "window alias webkit messageHandlers rpc postMessage",
            #"(?:const|let|var)([A-Za-z_$][A-Za-z0-9_$]*)=window;.*\1\.webkit\.messageHandlers\.rpc\.postMessage"#
        ),
        (
            "messageHandlers alias rpc.postMessage",
            #"(?:const|let|var)([A-Za-z_$][A-Za-z0-9_$]*)=window\.webkit\.messageHandlers;.*\1\.rpc\.postMessage"#
        ),
        (
            "webkit alias messageHandlers rpc.postMessage",
            #"(?:const|let|var)([A-Za-z_$][A-Za-z0-9_$]*)=window\.webkit;.*\1\.messageHandlers\.rpc\.postMessage"#
        ),
        (
            "destructured webkit messageHandlers rpc.postMessage",
            #"(?:const|let|var)\{webkit\}=window;.*webkit\.messageHandlers\.rpc\.postMessage"#
        ),
        (
            "destructured webkit alias messageHandlers rpc.postMessage",
            #"(?:const|let|var)\{webkit:([A-Za-z_$][A-Za-z0-9_$]*)\}=window;.*\1\.messageHandlers\.rpc\.postMessage"#
        ),
        (
            "destructured window.webkit.messageHandlers rpc relay",
            #"(?:const|let|var)\{[^=;]*rpc[^=;]*\}=window\.webkit\.messageHandlers;.*(?:[A-Za-z_$][A-Za-z0-9_$]*\.)?postMessage\("#
        ),
        (
            "destructured window.webkit messageHandlers rpc relay",
            #"(?:const|let|var)\{[^=;]*messageHandlers[^=;]*rpc[^=;]*\}=window\.webkit;.*(?:[A-Za-z_$][A-Za-z0-9_$]*\.)?postMessage\("#
        ),
        (
            "destructured window webkit messageHandlers rpc relay",
            #"(?:const|let|var)\{[^=;]*webkit[^=;]*messageHandlers[^=;]*rpc[^=;]*\}=window;.*(?:[A-Za-z_$][A-Za-z0-9_$]*\.)?postMessage\("#
        ),
        (
            "destructured messageHandlers rpc.postMessage",
            #"(?:const|let|var)\{messageHandlers\}=window\.webkit;.*messageHandlers\.rpc\.postMessage"#
        ),
        (
            "destructured messageHandlers alias rpc.postMessage",
            #"(?:const|let|var)\{messageHandlers:([A-Za-z_$][A-Za-z0-9_$]*)\}=window\.webkit;.*\1\.rpc\.postMessage"#
        ),
        (
            "rpc alias postMessage",
            #"(?:const|let|var)([A-Za-z_$][A-Za-z0-9_$]*)=window\.webkit\.messageHandlers\.rpc;.*\1\.postMessage"#
        ),
        (
            "destructured rpc postMessage",
            #"(?:const|let|var)\{rpc\}=window\.webkit\.messageHandlers;.*rpc\.postMessage"#
        ),
        (
            "destructured rpc alias postMessage",
            #"(?:const|let|var)\{rpc:([A-Za-z_$][A-Za-z0-9_$]*)\}=window\.webkit\.messageHandlers;.*\1\.postMessage"#
        ),
        (
            "destructured postMessage call",
            #"(?:const|let|var)\{postMessage\}=window\.webkit\.messageHandlers\.rpc;.*postMessage\("#
        ),
        (
            "destructured postMessage alias call",
            #"(?:const|let|var)\{postMessage:([A-Za-z_$][A-Za-z0-9_$]*)\}=window\.webkit\.messageHandlers\.rpc;.*\1\("#
        ),
        (
            "nested destructured rpc postMessage call",
            #"(?:const|let|var)\{rpc:\{postMessage\}\}=window\.webkit\.messageHandlers;.*postMessage\("#
        ),
        (
            "nested destructured rpc postMessage alias call",
            #"(?:const|let|var)\{rpc:\{postMessage:([A-Za-z_$][A-Za-z0-9_$]*)\}\}=window\.webkit\.messageHandlers;.*\1\("#
        ),
        (
            "nested destructured messageHandlers rpc postMessage call",
            #"(?:const|let|var)\{messageHandlers:\{rpc:\{postMessage\}\}\}=window\.webkit;.*postMessage\("#
        ),
        (
            "nested destructured messageHandlers rpc postMessage alias call",
            #"(?:const|let|var)\{messageHandlers:\{rpc:\{postMessage:([A-Za-z_$][A-Za-z0-9_$]*)\}\}\}=window\.webkit;.*\1\("#
        ),
        (
            "nested destructured webkit messageHandlers rpc postMessage call",
            #"(?:const|let|var)\{webkit:\{messageHandlers:\{rpc:\{postMessage\}\}\}\}=window;.*postMessage\("#
        ),
        (
            "nested destructured webkit messageHandlers rpc postMessage alias call",
            #"(?:const|let|var)\{webkit:\{messageHandlers:\{rpc:\{postMessage:([A-Za-z_$][A-Za-z0-9_$]*)\}\}\}\}=window;.*\1\("#
        ),
    ]
}

extension String {
    fileprivate func bridgeNormalizedJavaScriptPropertyAccess(_ propertyName: String) -> String {
        replacingOccurrences(
            of: #"\[(["'])\#(propertyName)\1\]"#,
            with: ".\(propertyName)",
            options: .regularExpression
        )
    }
}
