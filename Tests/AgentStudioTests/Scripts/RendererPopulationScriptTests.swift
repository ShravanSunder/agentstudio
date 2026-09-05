import AgentStudioInfrastructure
import Foundation
import Testing

/// Red-first proof for `scripts/verify-renderer-population.sh`: a read-only sampler that reports
/// renderer/IO thread counts, IOSurface/IOAccelerator dirty footprint, and heap class occupancy for
/// one AgentStudio PID. Governing: plan S8; specification V2/V6/V9; program design "Proof
/// architecture" runtime rows.
@Suite("Renderer population script")
struct RendererPopulationScriptTests {
    private static let scriptPath = "scripts/verify-renderer-population.sh"
    private static let productionAppPath = "/Applications/AgentStudio.app/Contents/MacOS/AgentStudio"

    @Test("script has valid syntax and refuses the production executable")
    func scriptHasValidSyntaxAndRefusesTheProductionExecutable() async throws {
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

    private func writeFixture(_ contents: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
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
