import AgentStudioBridge
import Foundation

/// Development-server substitute for App-owned clipboard and save-panel effects.
///
/// The Vite loop must exercise the real output coordinator and durable history,
/// but a headless HTTP development host must never claim system clipboard or
/// save-panel authority. This effect captures exact bytes beneath the isolated
/// development data root so runtime proof can inspect them directly.
package actor BridgeDevelopmentWorktreeAnnotationOutputEffect:
    WorktreeAnnotationOutputEffect
{
    package nonisolated let outputDirectory: URL

    private var reservedJSONDestinationPaths: Set<String> = []

    package init(dataRoot: URL) {
        outputDirectory =
            dataRoot
            .appending(path: "annotation-output-captures", directoryHint: .isDirectory)
            .standardizedFileURL
    }

    package func chooseJSONDestination(
        suggestedFilename: String
    ) async -> WorktreeAnnotationOutputDestinationOutcome {
        guard isSafeSuggestedFilename(suggestedFilename) else {
            return .failed("The development JSON export filename was invalid.")
        }
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let destination = nextAvailableJSONDestination(
                suggestedFilename: suggestedFilename
            )
            reservedJSONDestinationPaths.insert(destination.path)
            return .selected(path: destination.path)
        } catch {
            return .failed(
                "The isolated development output directory could not be prepared: "
                    + error.localizedDescription
            )
        }
    }

    package func perform(
        _ request: WorktreeAnnotationOutputEffectRequest
    ) async -> WorktreeAnnotationOutputEffectOutcome {
        let destination: URL
        switch request.outputKind {
        case .clipboardMarkdown:
            destination = clipboardCaptureURL(for: request.attemptID)
        case .jsonFile:
            guard let destinationPath = request.destinationPath,
                reservedJSONDestinationPaths.contains(destinationPath),
                isInsideOutputDirectory(destinationPath)
            else {
                return .failed(
                    "The JSON destination was outside the isolated development output directory."
                )
            }
            destination = URL(fileURLWithPath: destinationPath).standardizedFileURL
        }

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            try request.exactBytes.write(to: destination, options: .atomic)
            return .succeeded
        } catch {
            return .failed(
                "The development output capture could not be written: \(error.localizedDescription)"
            )
        }
    }

    package nonisolated func clipboardCaptureURL(for attemptID: UUID) -> URL {
        outputDirectory.appending(
            path: "clipboard-\(attemptID.uuidString.lowercased()).md",
            directoryHint: .notDirectory
        )
    }

    private func nextAvailableJSONDestination(suggestedFilename: String) -> URL {
        let suggestedURL = URL(fileURLWithPath: suggestedFilename)
        let stem = suggestedURL.deletingPathExtension().lastPathComponent
        let pathExtension = suggestedURL.pathExtension
        var sequence = 1
        while true {
            let filename =
                sequence == 1
                ? suggestedFilename
                : "\(stem)-\(sequence).\(pathExtension)"
            let candidate = outputDirectory.appending(
                path: filename,
                directoryHint: .notDirectory
            )
            if !reservedJSONDestinationPaths.contains(candidate.path),
                !FileManager.default.fileExists(atPath: candidate.path)
            {
                return candidate
            }
            sequence += 1
        }
    }

    private func isSafeSuggestedFilename(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename == URL(fileURLWithPath: filename).lastPathComponent
            && URL(fileURLWithPath: filename).pathExtension.lowercased() == "json"
    }

    private func isInsideOutputDirectory(_ destinationPath: String) -> Bool {
        URL(fileURLWithPath: destinationPath)
            .standardizedFileURL
            .deletingLastPathComponent() == outputDirectory
    }
}
