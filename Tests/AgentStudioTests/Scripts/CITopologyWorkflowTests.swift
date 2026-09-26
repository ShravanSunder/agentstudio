import Foundation
import Testing

@Suite("CI topology workflow")
struct CITopologyWorkflowTests {
    @Test("CI jobs start independently without cross-job dependencies")
    func ciJobsStartIndependentlyWithoutCrossJobDependencies() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)

        for jobName in [
            "code-quality",
            "marketing-site-validation",
            "bridge-web",
            "swift-test-suite",
        ] {
            let job = try topologyJob(named: jobName, in: workflow)
            #expect(!job.contains("\n    needs:"))
        }
    }

    @Test("CI cancels only superseded attempts for the same pull request")
    func ciCancellationIsScopedToOnePullRequest() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let concurrency = try topologyBlock(
            startingWith: "concurrency:\n",
            endingBefore: "\npermissions:",
            in: workflow
        )

        #expect(
            concurrency.contains(
                "group: \"${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}\""
            )
        )
        #expect(concurrency.contains("cancel-in-progress: ${{ github.event_name == 'pull_request' }}"))
    }

    @Test("portable CI checks retain their browser, lint, and release contracts")
    func portableCIJobsRetainTheirContracts() throws {
        let workflow = try String(contentsOfFile: ".github/workflows/ci.yml", encoding: .utf8)
        let qualityJob = try topologyJob(named: "code-quality", in: workflow)
        let marketingJob = try topologyJob(named: "marketing-site-validation", in: workflow)
        let bridgeWebJob = try topologyJob(named: "bridge-web", in: workflow)
        let swiftJob = try topologyJob(named: "swift-test-suite", in: workflow)
        let lintInstaller = try String(
            contentsOfFile: "scripts/install-ci-lint-tools.sh",
            encoding: .utf8
        )

        #expect(qualityJob.contains("runs-on: ubuntu-24.04"))
        #expect(marketingJob.contains("runs-on: ubuntu-24.04"))
        #expect(bridgeWebJob.contains("runs-on: macos-26"))
        #expect(bridgeWebJob.contains("      - parallel:\n          - name: Install BridgeWeb dependencies"))
        #expect(bridgeWebJob.contains("      - parallel:\n          - name: BridgeWeb packaged build"))
        #expect(bridgeWebJob.contains("      - parallel:\n          - name: Copy XCFramework"))
        #expect(swiftJob.contains("runs-on: macos-26"))
        #expect(qualityJob.contains("run: mise run lint:portable"))
        #expect(qualityJob.contains("run: mise run test:architecture"))
        #expect(qualityJob.contains("check-ledger-ratchet.sh"))
        #expect(qualityJob.contains("architecture-lint-linux-${{ runner.arch }}-swift-6.3.3-"))
        #expect(qualityJob.contains("github.ref == 'refs/heads/main'"))
        #expect(marketingJob.contains("lfs: true"))
        #expect(marketingJob.contains("playwright@1.61.0 install --with-deps chrome"))
        #expect(marketingJob.contains("CHROME_BIN=$chrome_binary"))
        #expect(marketingJob.contains("pnpm --dir web run check"))
        #expect(marketingJob.contains("pnpm --dir web run build"))
        #expect(swiftJob.contains("run: mise run lint:release-scripts"))
        #expect(swiftJob.contains("bash scripts/install-ci-lint-tools.sh"))
        #expect(qualityJob.contains("bash scripts/install-ci-lint-tools.sh"))
        #expect(lintInstaller.contains("--branch 603.0.0"))
        #expect(lintInstaller.contains("mise install swiftlint@0.65.1"))
        #expect(lintInstaller.contains("swiftlint\" rules --enabled --config .swiftlint.yml"))
    }
}

private enum CITopologyWorkflowError: Error {
    case missingBlock(String)
}

private func topologyJob(named jobName: String, in workflow: String) throws -> String {
    let workflowLines = workflow.split(separator: "\n", omittingEmptySubsequences: false)
    guard let startIndex = workflowLines.firstIndex(where: { $0 == "  \(jobName):" }) else {
        throw CITopologyWorkflowError.missingBlock(jobName)
    }

    var endIndex = workflowLines.index(after: startIndex)
    while endIndex < workflowLines.endIndex {
        let line = workflowLines[endIndex]
        if line.hasPrefix("  "), !line.hasPrefix("    "), !line.trimmingCharacters(in: .whitespaces).isEmpty {
            break
        }
        endIndex = workflowLines.index(after: endIndex)
    }

    return workflowLines[startIndex..<endIndex].joined(separator: "\n")
}

private func topologyBlock(startingWith marker: String, endingBefore terminator: String, in text: String) throws
    -> String
{
    guard let startRange = text.range(of: marker) else {
        throw CITopologyWorkflowError.missingBlock(marker)
    }
    let tail = text[startRange.lowerBound...]
    guard let endRange = tail.range(of: terminator, range: tail.index(after: startRange.lowerBound)..<tail.endIndex)
    else {
        return String(tail)
    }
    return String(tail[..<endRange.lowerBound])
}
