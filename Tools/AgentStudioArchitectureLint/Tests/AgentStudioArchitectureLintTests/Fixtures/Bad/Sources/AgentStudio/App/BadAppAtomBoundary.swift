let ambientAtomRegistry = AtomRegistry()

struct BadStaticAtomRegistryOwner {
    static let sharedAtoms = AtomRegistry()
}

enum AppAtomScope {}

struct RuntimeAtomResolver {}
struct RuntimeAtomRegistration {}
struct LegacyAtomCompatibility {}
struct AgentStudioState {}
struct TerminalFeatureState {}
