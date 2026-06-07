import Foundation

extension WorkspacePersistor {
    static func dataRoutingLegacyDrawerActivePaneIds(_ data: Data) -> Data {
        guard
            var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let panes = root["panes"] as? [[String: Any]],
            var tabs = root["tabs"] as? [[String: Any]]
        else {
            return data
        }

        let activePaneIdsByDrawerId = legacyActivePaneIdsByDrawerId(from: panes)
        guard !activePaneIdsByDrawerId.isEmpty else { return data }

        var didRouteLegacyCursor = false
        for tabIndex in tabs.indices {
            guard var arrangements = tabs[tabIndex]["arrangements"] as? [[String: Any]] else { continue }
            for arrangementIndex in arrangements.indices {
                guard var drawerViews = arrangements[arrangementIndex]["drawerViews"] else { continue }
                if routeLegacyActivePaneIds(
                    into: &drawerViews,
                    activePaneIdsByDrawerId: activePaneIdsByDrawerId
                ) {
                    arrangements[arrangementIndex]["drawerViews"] = drawerViews
                    didRouteLegacyCursor = true
                }
            }
            tabs[tabIndex]["arrangements"] = arrangements
        }

        guard didRouteLegacyCursor else { return data }
        root["tabs"] = tabs
        return (try? JSONSerialization.data(withJSONObject: root)) ?? data
    }
}

private func legacyActivePaneIdsByDrawerId(from panes: [[String: Any]]) -> [String: String] {
    panes.reduce(into: [:]) { result, pane in
        guard
            let kind = pane["kind"] as? [String: Any],
            let layout = kind["layout"] as? [String: Any],
            let drawer = layout["drawer"] as? [String: Any],
            let drawerId = drawer["drawerId"] as? String,
            let activePaneId = drawer["activePaneId"] as? String,
            let paneIds = drawer["paneIds"] as? [String],
            paneIds.contains(activePaneId)
        else {
            return
        }
        result[drawerId] = activePaneId
    }
}

private func routeLegacyActivePaneIds(
    into drawerViews: inout Any,
    activePaneIdsByDrawerId: [String: String]
) -> Bool {
    if var keyedDrawerViews = drawerViews as? [String: Any] {
        let didRoute = routeLegacyActivePaneIds(
            intoKeyedDrawerViews: &keyedDrawerViews,
            activePaneIdsByDrawerId: activePaneIdsByDrawerId
        )
        if didRoute { drawerViews = keyedDrawerViews }
        return didRoute
    }

    guard var alternatingDrawerViews = drawerViews as? [Any] else { return false }
    var didRoute = false
    var index = 0
    while index + 1 < alternatingDrawerViews.count {
        guard
            let drawerId = alternatingDrawerViews[index] as? String,
            var drawerView = alternatingDrawerViews[index + 1] as? [String: Any],
            routeLegacyActivePaneId(
                into: &drawerView,
                drawerId: drawerId,
                activePaneIdsByDrawerId: activePaneIdsByDrawerId
            )
        else {
            index += 2
            continue
        }
        alternatingDrawerViews[index + 1] = drawerView
        didRoute = true
        index += 2
    }
    if didRoute { drawerViews = alternatingDrawerViews }
    return didRoute
}

private func routeLegacyActivePaneIds(
    intoKeyedDrawerViews drawerViews: inout [String: Any],
    activePaneIdsByDrawerId: [String: String]
) -> Bool {
    var didRoute = false
    for drawerId in Array(drawerViews.keys) {
        guard
            var drawerView = drawerViews[drawerId] as? [String: Any],
            routeLegacyActivePaneId(
                into: &drawerView,
                drawerId: drawerId,
                activePaneIdsByDrawerId: activePaneIdsByDrawerId
            )
        else {
            continue
        }
        drawerViews[drawerId] = drawerView
        didRoute = true
    }
    return didRoute
}

private func routeLegacyActivePaneId(
    into drawerView: inout [String: Any],
    drawerId: String,
    activePaneIdsByDrawerId: [String: String]
) -> Bool {
    guard
        drawerView["activeChildId"] == nil,
        let activePaneId = activePaneIdsByDrawerId[drawerId],
        drawerViewLayout(drawerView["layout"], containsPaneId: activePaneId)
    else {
        return false
    }
    drawerView["activeChildId"] = activePaneId
    return true
}

private func drawerViewLayout(_ payload: Any?, containsPaneId paneId: String) -> Bool {
    guard let payload = payload as? [String: Any] else { return false }
    return layoutPayload(payload["topRow"], containsPaneId: paneId)
        || layoutPayload(payload["bottomRow"], containsPaneId: paneId)
        || layoutPayload(payload, containsPaneId: paneId)
}

private func layoutPayload(_ payload: Any?, containsPaneId paneId: String) -> Bool {
    guard
        let payload = payload as? [String: Any],
        let panes = payload["panes"] as? [[String: Any]]
    else {
        return false
    }
    return panes.contains { ($0["paneId"] as? String) == paneId }
}
