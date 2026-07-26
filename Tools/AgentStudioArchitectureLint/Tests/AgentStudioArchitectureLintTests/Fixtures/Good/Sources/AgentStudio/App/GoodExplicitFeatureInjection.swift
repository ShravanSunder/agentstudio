struct GoodExplicitFeatureInjection {
    let terminalActivity: GoodTerminalActivityAtom
}

struct GoodPinnedProjection {
    let isPinned: () -> Bool
}
