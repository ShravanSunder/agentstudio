import AgentStudioInfrastructure
import Foundation
import Testing

/// Red-first proof for `scripts/verify-renderer-population.sh`: a read-only sampler that reports
/// renderer/IO thread counts, IOSurface/IOAccelerator dirty footprint, and heap class occupancy for
/// one AgentStudio PID. This proves parser behavior; native reclamation needs separate runtime evidence.
@Suite("Renderer population script")
struct RendererPopulationScriptTests {
    private static let scriptPath = "scripts/verify-renderer-population.sh"
    private static let productionAppPath = "/Applications/AgentStudio.app/Contents/MacOS/AgentStudio"

    @Test("heap counts exclude keypaths and similarly named classes")
    func heapCountsExcludeKeypathsAndSimilarlyNamedClasses() async throws {
        let fixture = """
            1 640 640.0 PaneHostView Swift AgentStudio
            2 1280 640.0 PaneHostView Swift AgentStudio
            1 80 80.0 Swift.ReferenceWritableKeyPath<AgentStudio.ViewRegistry.PaneViewSlot, Swift.Optional<AgentStudio.PaneHostView>> Swift libswiftCore.dylib
            4 256 64.0 PaneHostViewWrapper Swift AgentStudio
            """
        let file = try writeFixture(fixture, named: "heap-classes.txt")
        defer { try? FileManager.default.removeItem(at: file) }
        let result = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: [Self.scriptPath, "--count-heap-class", file.path, "PaneHostView"],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "3")
    }

    @Test("script has valid syntax and declares the production sampling restriction")
    func scriptHasValidSyntaxAndDeclaresProductionSamplingRestriction() async throws {
        // Arrange: the script must exist and parse as valid bash.
        let syntax = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: ["-n", Self.scriptPath],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )

        // Act: read the script source to confirm the refusal branch and the pkill prohibition.
        let source = try String(contentsOfFile: Self.scriptPath, encoding: .utf8)

        // Assert: syntax is valid, production app is named in a refusal branch, and no process
        // signaling is present anywhere in the script.
        #expect(syntax.exitCode == 0, "stdout: \(syntax.stdout)\nstderr: \(syntax.stderr)")
        #expect(source.contains(Self.productionAppPath))
        #expect(!source.contains("pkill"))
        #expect(!source.contains("pgrep -f AgentStudio"))
    }

    @Test("parsers read footprint and vmmap fixtures")
    func parsersReadFootprintAndVmmapFixtures() async throws {
        // Arrange: fifteen representative lines copied verbatim from
        // tmp/debug-workflows/2026-09-05-agent-studio-fix-memory-pressure-memory-pressure/raw/
        // prod-2409-2026-09-05T0538/footprint.txt, and eight IOSurface lines (six small, two
        // >= 1 MB) copied verbatim from vmmap-wide.txt in that same folder.
        let footprintFixture = """
            ======================================================================
            AgentStudio [2409]: 64-bit    Footprint: 2177 MB (16384 bytes per page)
            ======================================================================

              Dirty      Clean  Reclaimable    Regions    Category
                ---        ---          ---        ---    ---
            1102 MB        0 B          0 B        119    IOSurface
             358 MB        0 B          0 B        556    Owned physical footprint (unmapped) (graphics)
             349 MB        0 B       168 MB        146    MALLOC_SMALL
             208 MB        0 B      4576 KB       1010    IOAccelerator (graphics)
                ---        ---          ---        ---    ---
            2177 MB      69 MB       174 MB      12295    TOTAL

            Auxiliary data:
                phys_footprint: 2177 MB
            """
        let vmmapFixture = """
            IOSurface                   123e8c000-123e90000    [   16K     0K     0K     0K] r--/r-- SM=SHM PURGE=N
            IOSurface                   123ee0000-123ee4000    [   16K     0K     0K     0K] r--/r-- SM=SHM PURGE=N
            IOSurface                   123ee4000-123ee8000    [   16K     0K     0K     0K] r--/r-- SM=SHM PURGE=N
            IOSurface                   123f18000-123f1c000    [   16K     0K     0K     0K] r--/r-- SM=SHM PURGE=N
            IOSurface                   123f34000-123f38000    [   16K     0K     0K     0K] r--/r-- SM=SHM PURGE=N
            IOSurface                   123f3c000-123f40000    [   16K     0K     0K     0K] r--/r-- SM=SHM PURGE=N
            IOSurface                   1245fc000-12587c000    [ 18.5M  18.5M  18.5M     0K] rw-/rw- SM=SHM PURGE=N  SurfaceID: 0x74  2080x2330 (BGRA) 18.5M  'AgentStudio', shared with WindowServer[401]
            IOSurface                   125b28000-126da8000    [ 18.5M  18.5M  18.5M     0K] rw-/rw- SM=SHM PURGE=N  SurfaceID: 0x102  2080x2330 (BGRA) 18.5M  'AgentStudio'
            """

        let footprintFile = try writeFixture(footprintFixture, named: "footprint-fixture.txt")
        defer { try? FileManager.default.removeItem(at: footprintFile) }
        let vmmapFile = try writeFixture(vmmapFixture, named: "vmmap-fixture.txt")
        defer { try? FileManager.default.removeItem(at: vmmapFile) }

        // Act: invoke the script's read-only parser modes against the fixture files.
        let footprintResult = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: [Self.scriptPath, "--parse-footprint", footprintFile.path],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )
        let vmmapResult = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: [Self.scriptPath, "--parse-vmmap", vmmapFile.path],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )

        // Assert: both parsers exit cleanly and report the expected fields from the fixtures.
        #expect(footprintResult.exitCode == 0, "stdout: \(footprintResult.stdout)\nstderr: \(footprintResult.stderr)")
        #expect(vmmapResult.exitCode == 0, "stdout: \(vmmapResult.stdout)\nstderr: \(vmmapResult.stderr)")

        let footprintJSON = try decodeJSONObject(footprintResult.stdout)
        let vmmapJSON = try decodeJSONObject(vmmapResult.stdout)

        #expect(numberValue(footprintJSON, "phys_footprint_mb") == 2177)
        #expect(numberValue(footprintJSON, "iosurface_dirty_mb") == 1102)
        #expect(numberValue(vmmapJSON, "iosurface_regions_total") == 8)
        #expect(numberValue(vmmapJSON, "iosurface_regions_large") == 2)
    }

    @Test("parsers report failed captures as null, not zero population")
    func parsersReportFailedCapturesAsNull() async throws {
        // Arrange: a one-line failure capture, as `vmmap`/`footprint` emit when they cannot
        // attach to the target process.
        let failureFixture =
            "vmmap: cannot examine process 123 (Operation not permitted -- perhaps you need to run as root?)"
        let vmmapFailureFile = try writeFixture(failureFixture, named: "vmmap-failure-fixture.txt")
        defer { try? FileManager.default.removeItem(at: vmmapFailureFile) }
        let footprintFailureFile = try writeFixture(failureFixture, named: "footprint-failure-fixture.txt")
        defer { try? FileManager.default.removeItem(at: footprintFailureFile) }

        // Act
        let vmmapResult = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: [Self.scriptPath, "--parse-vmmap", vmmapFailureFile.path],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )
        let footprintResult = try await DefaultProcessExecutor(timeout: 10).execute(
            command: "/bin/bash",
            args: [Self.scriptPath, "--parse-footprint", footprintFailureFile.path],
            cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            environment: nil
        )

        // Assert: both parsers exit cleanly, every dependent field is null (not zero), and the
        // failed capture's first line rides along as `capture_error`.
        #expect(vmmapResult.exitCode == 0, "stdout: \(vmmapResult.stdout)\nstderr: \(vmmapResult.stderr)")
        #expect(
            footprintResult.exitCode == 0,
            "stdout: \(footprintResult.stdout)\nstderr: \(footprintResult.stderr)")

        let vmmapJSON = try decodeJSONObject(vmmapResult.stdout)
        let footprintJSON = try decodeJSONObject(footprintResult.stdout)

        #expect(vmmapJSON["iosurface_regions_total"] is NSNull)
        #expect(vmmapJSON["iosurface_regions_large"] is NSNull)
        #expect(vmmapJSON["capture_error"] as? String == failureFixture)

        #expect(footprintJSON["phys_footprint_mb"] is NSNull)
        #expect(footprintJSON["iosurface_dirty_mb"] is NSNull)
        #expect(footprintJSON["ioaccelerator_dirty_mb"] is NSNull)
        #expect(footprintJSON["owned_graphics_dirty_mb"] is NSNull)
        #expect(footprintJSON["capture_error"] as? String == failureFixture)
    }

    @Test("system memory parser reports failed or malformed captures as null and never aborts")
    func systemMemoryParserReportsFailedCapturesAsNull() async throws {
        // Arrange: a valid vm_stat/swap pair, a tool-error vm_stat capture, and a truncated vm_stat capture.
        let validVMStat = """
            Mach Virtual Memory Statistics: (page size of 16384 bytes)
            Pages free:                               1024.
            Pages occupied by compressor:             2048.
            """
        let validSwap = "vm.swapusage: total = 4096.00M  used = 1024.00M  free = 3072.00M  (encrypted)"
        let erroredVMStat = "vm_stat: cannot read statistics"
        let truncatedVMStat = "Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages free: 5."
        let swapFile = try writeFixture(validSwap, named: "swap-fixture.txt")
        defer { try? FileManager.default.removeItem(at: swapFile) }
        let validFile = try writeFixture(validVMStat, named: "vm-valid.txt")
        defer { try? FileManager.default.removeItem(at: validFile) }
        let erroredFile = try writeFixture(erroredVMStat, named: "vm-errored.txt")
        defer { try? FileManager.default.removeItem(at: erroredFile) }
        let truncatedFile = try writeFixture(truncatedVMStat, named: "vm-truncated.txt")
        defer { try? FileManager.default.removeItem(at: truncatedFile) }

        // Act
        var results: [String: [String: Any]] = [:]
        for (name, file) in [("valid", validFile), ("errored", erroredFile), ("truncated", truncatedFile)] {
            let result = try await DefaultProcessExecutor(timeout: 10).execute(
                command: "/bin/bash",
                args: [Self.scriptPath, "--parse-system-memory", file.path, swapFile.path],
                cwd: URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
                environment: nil
            )
            #expect(result.exitCode == 0, "\(name) stdout: \(result.stdout)\nstderr: \(result.stderr)")
            results[name] = try decodeJSONObject(result.stdout)
        }

        // Assert: valid parses to numbers (16384-byte pages: 1024 pages = 16 MB free, 2048 = 32 MB compressor,
        // swap used 1024 MB); errored and truncated captures yield nulls plus a capture_error, never zero.
        #expect(numberValue(results["valid"]!, "free_mb") == 16)
        #expect(numberValue(results["valid"]!, "compressor_mb") == 32)
        #expect(numberValue(results["valid"]!, "swap_used_mb") == 1024)
        for name in ["errored", "truncated"] {
            let json = results[name]!
            #expect(json["free_mb"] is NSNull, "\(name) free_mb should be null")
            #expect(json["compressor_mb"] is NSNull, "\(name) compressor_mb should be null")
            #expect(json["swap_used_mb"] is NSNull, "\(name) swap_used_mb should be null")
            #expect((json["capture_error"] as? String)?.isEmpty == false, "\(name) needs a capture_error")
        }
    }

    private func writeFixture(_ contents: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUIDv7.generate().uuidString)-\(name)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func decodeJSONObject(_ output: String) throws -> [String: Any] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try #require(trimmed.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func numberValue(_ json: [String: Any], _ key: String) -> Double? {
        (json[key] as? NSNumber)?.doubleValue
    }
}
