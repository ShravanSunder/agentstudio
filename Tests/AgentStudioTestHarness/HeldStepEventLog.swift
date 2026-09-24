import Foundation

/// Where a `HeldStep` records that a test started waiting for it and that the
/// work first arrived at it.
///
/// A lane's hang bound ends a stuck test process with TERM and KILL, which
/// never cancels the waiting task, so the step's own error cannot name it. The
/// runner sets `AGENTSTUDIO_HELD_STEP_LOG` for each lane and, when the bound
/// fires, reports every step instance that has a `waiting` line and no
/// `arrived` line. Lines are tab-separated, because step names contain spaces,
/// and pair by the step's process-unique instance id, so an arrival at one
/// instance can never answer a wait on another instance with the same name:
///
///     waiting<TAB><instance id><TAB><step name><TAB><test>
///     arrived<TAB><instance id><TAB><step name>
///
/// Each line is one `write(2)` on a descriptor opened with `O_APPEND`, so a
/// process killed mid-test loses nothing it already logged and concurrent
/// steps never interleave within a line. With the variable unset nothing is
/// written.
package struct HeldStepEventLog: Sendable {
    package static let environmentVariableName = "AGENTSTUDIO_HELD_STEP_LOG"

    /// The log the lane asked for, or no log.
    package static let environment = Self(
        path: ProcessInfo.processInfo.environment[environmentVariableName].flatMap { $0.isEmpty ? nil : $0 }
    )

    package let path: String?

    package init(path: String?) {
        self.path = path
    }

    func recordWaiting(instanceID: UInt64, stepName: String, test: String) {
        append("waiting\t\(instanceID)\t\(stepName)\t\(test)\n")
    }

    func recordArrived(instanceID: UInt64, stepName: String) {
        append("arrived\t\(instanceID)\t\(stepName)\n")
    }

    private func append(_ line: String) {
        guard let path else { return }
        let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let bytes = Array(line.utf8)
        _ = bytes.withUnsafeBytes { buffer in
            write(descriptor, buffer.baseAddress, buffer.count)
        }
    }
}
