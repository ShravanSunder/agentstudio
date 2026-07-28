let workloadFixtureJSON = """
    {"schemaVersion":1,"id":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb1","name":"Git Refresh Performance Fixture",
    "repos":[{"id":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb2","name":"repo-000","repoPath":"file:///tmp/agentstudio-perf/repo-000","createdAt":0}],
    "worktrees":[{"id":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb3","repoId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb2","name":"main","path":"file:///tmp/agentstudio-perf/repo-000","isMainWorktree":true}],
    "unavailableRepoIds":[],"panes":[{
    "id":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb6","content":{"version":3,"type":"terminal","state":{"provider":"zmx","lifetime":"persistent","zmxSessionID":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb5"}},
    "metadata":{"paneId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb6","contentType":{"terminal":{}},
    "source":{"worktree":{"worktreeId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb3","repoId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb2","launchDirectory":"file:///tmp/agentstudio-perf/repo-000"}},
    "executionBackend":{"local":{}},"createdAt":0,"title":"repo-pane-0","facets":{"repoId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb2","worktreeId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb3","cwd":"file:///tmp/agentstudio-perf/repo-000","tags":[]},"checkoutRef":null,"note":null},
    "residency":{"active":{}},"kind":{"layout":{"drawer":{"drawerId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb4","parentPaneId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb6","paneIds":[],"isExpanded":false}}}}],
    "tabs":[{"id":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb7","name":"Performance","panes":["019eb9e5-2de8-7c5f-83b1-cc9782b2efb6"],
    "arrangements":[{"id":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb8","name":"Default","isDefault":true,"layout":{"panes":[{"paneId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb6","ratio":1.0}],"dividerIds":[]},"minimizedPaneIds":[],"activePaneId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb6","drawerViews":[]}],
    "activeArrangementId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb8"}],"activeTabId":"019eb9e5-2de8-7c5f-83b1-cc9782b2efb7",
    "sidebarWidth":250,"windowFrame":null,"watchedPaths":[],"createdAt":0,"updatedAt":0}
    """
