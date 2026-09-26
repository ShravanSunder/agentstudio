import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

final class CommandBarRecentsDefaultsFixture {
    private struct PersistentDomain {
        let suiteName: String
        let defaults: UserDefaults
    }

    private var persistentDomains: [PersistentDomain] = []

    func makeDefaults() -> UserDefaults {
        let suiteName = "agentstudio.tests.commandbar.\(UUIDv7.generate().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create the Command Bar test defaults suite")
        }

        persistentDomains.append(PersistentDomain(suiteName: suiteName, defaults: defaults))
        return defaults
    }

    deinit {
        for domain in persistentDomains {
            domain.defaults.removePersistentDomain(forName: domain.suiteName)
        }
    }
}
