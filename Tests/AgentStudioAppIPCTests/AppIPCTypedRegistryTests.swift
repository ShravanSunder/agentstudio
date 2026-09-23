import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("App IPC registered typed catalog")
struct AppIPCTypedRegistryTests {
    @Test("debug registry derives its full capabilities from the callable registrations")
    func debugRegistryDerivesCapabilitiesFromHandlers() throws {
        let fixture = BuiltInMethodRegistrationsFixture()
        let registrations = try fixture.registrations()
        let registry = try AppIPCMethodRegistry(registrations: registrations, channel: .debug)
        let names = registry.capabilities.methods.map(\.name)
        #expect(names.count == 48)
        #expect(names == names.sorted())
        #expect(Set(names).count == names.count)
        #expect(names.filter { $0 == "system.capabilities" }.count == 1)
        #expect(registry.registration(named: "permission.request") == nil)
        #expect(registry.registration(named: "file.open") == nil)
        for name in names {
            #expect(
                registry.registration(named: name)?.descriptor.metadata
                    == registry.capabilities.methods.first { $0.name == name })
        }
        let decoded = try IPCMethodCatalogDecoder.decode(JSONEncoder().encode(registry.capabilities))
        #expect(decoded == registry.capabilities)
    }

    @Test(
        "stable and beta omit diagnostic registrations from both invocation and discovery",
        arguments: [AgentStudioIPCChannel.stable, .beta])
    func productionRegistryOmitsDiagnosticMethods(channel: AgentStudioIPCChannel) throws {
        let fixture = BuiltInMethodRegistrationsFixture()
        let registry = try AppIPCMethodRegistry(registrations: fixture.registrations(), channel: channel)
        #expect(registry.capabilities.methods.count == 12)
        #expect(registry.capabilities.methods.allSatisfy { $0.exposure == .allChannels })
        #expect(registry.registration(named: "session.report") != nil)
        #expect(registry.registration(named: "session.query") != nil)
        #expect(registry.registration(named: "terminal.send") == nil)
        #expect(registry.registration(named: "ui.commandBar.open") == nil)
        #expect(registry.registration(named: "pane.snapshot") == nil)
    }

    @Test("duplicate registration identities reject composition")
    func duplicatesRejectComposition() throws {
        let fixture = BuiltInMethodRegistrationsFixture()
        let registrations = try fixture.registrations()
        let duplicate = try #require(registrations.first)
        #expect(throws: AppIPCMethodRegistryError.self) {
            try AppIPCMethodRegistry(registrations: registrations + [duplicate], channel: .debug)
        }
    }

    @Test("registry capabilities handler returns the same validated catalog")
    func capabilitiesHandlerMatchesRegistryProjection() async throws {
        let fixture = BuiltInMethodRegistrationsFixture()
        let registry = try AppIPCMethodRegistry(registrations: fixture.registrations(), channel: .debug)
        let registration = try #require(registry.registration(named: "system.capabilities"))
        let principal = fixture.diagnosticPrincipal
        let result = try await registration.invoke(
            parameters: .object([:]), connectionContext: fixture.connectionContext(principal: principal),
            targetResolutionTools: fixture.targetResolutionTools(),
            authorize: { _, request in
                #expect(request.requiredPrivileges == [.systemRead])
                #expect(request.target == .app)
            }
        )
        let decoded = try IPCMethodCatalogDecoder.decode(JSONEncoder().encode(result))
        #expect(decoded == registry.capabilities)
    }
}
