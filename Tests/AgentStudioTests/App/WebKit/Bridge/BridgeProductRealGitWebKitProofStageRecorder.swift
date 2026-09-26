import Foundation

func recordRealGitLiveProofStage(_ stage: String) {
    let marker = "[real-git-file-review] \(stage)\n"
    FileHandle.standardError.write(Data(marker.utf8))
    appendRealGitProofStageToHeldStepLog(marker)
    if let phaseFilePath = ProcessInfo.processInfo.environment["AGENTSTUDIO_B1_PHASE_FILE"] {
        let phaseFileURL = URL(fileURLWithPath: phaseFilePath)
        if FileManager.default.fileExists(atPath: phaseFileURL.path),
            let phaseFileHandle = try? FileHandle(forWritingTo: phaseFileURL)
        {
            _ = try? phaseFileHandle.seekToEnd()
            try? phaseFileHandle.write(contentsOf: Data(marker.utf8))
            try? phaseFileHandle.close()
        } else {
            try? Data(marker.utf8).write(to: phaseFileURL, options: .atomic)
        }
    }
}

func appendRealGitProofStageToHeldStepLog(_ marker: String) {
    guard let sidecarPath = ProcessInfo.processInfo.environment["AGENTSTUDIO_HELD_STEP_LOG"] else {
        return
    }

    let sidecarURL = URL(fileURLWithPath: sidecarPath)
    if !FileManager.default.fileExists(atPath: sidecarURL.path),
        !FileManager.default.createFile(atPath: sidecarURL.path, contents: nil)
    {
        FileHandle.standardError.write(
            Data("[real-git-proof-phase-log] sidecar-create-failed\n".utf8)
        )
        return
    }

    do {
        let sidecar = try FileHandle(forWritingTo: sidecarURL)
        try sidecar.seekToEnd()
        try sidecar.write(contentsOf: Data(marker.utf8))
        try sidecar.close()
    } catch {
        FileHandle.standardError.write(
            Data("[real-git-proof-phase-log] sidecar-append-failed\n".utf8)
        )
    }
}
