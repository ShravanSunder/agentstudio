export const marketingCopy = {
  productName: "Agent Studio",
  hero: {
    eyebrow: "Agent-agnostic. Repo-aware. Keyboard-first.",
    headline: "Stay oriented without losing context.",
    headlineLead: "Stay oriented",
    headlineTail: "without losing",
    headlineAccent: "context.",
    description:
      "An opinionated native macOS workspace for running dozens of coding agents across repositories and worktrees.",
  },
  switcher: {
    eyebrow: "Organized parallelism",
    headline: "Keep parallel work separate, but visible.",
    description:
      "Agent Studio makes the repository and worktree, not the terminal tab, the unit of organization.",
    accessibilityLabel: "Workspace views",
  },
  stories: {
    parallelWork: {
      label: "Parallel work",
      description:
        "Each pane keeps its repository, branch, worktree, and current directory visible.",
      imageDescription:
        "Codex and Claude Code working in two panes beside repository, branch, Git, activity, and recency context in All Panes.",
    },
    paneDrawer: {
      label: "Pane drawer",
      description:
        "Open a build log, git status, documentation, or a browser beside the agent that prompted it.",
      imageDescription:
        "One populated Git file-status drawer attached to the active agent task, with Codex and Claude Code visible behind it.",
    },
    quickFind: {
      label: "Quick Find",
      description: "Press Cmd+P to reach repositories, worktrees, panes, tabs, and commands.",
      imageDescription:
        "Quick Find listing agent-studio, y-websocket, and sidebar worktree panes over active Codex and Claude Code sessions.",
    },
    review: {
      label: "Review",
      description:
        "Agent Studio presents every changed file as one continuous, read-only diff with file-tree navigation and syntax highlighting.",
      imageDescription:
        "A readable unified CI workflow diff and Changed Files tree beside Claude Code in the matching worktree for pull request 313, with the global repository sidebar hidden.",
    },
    persistence: {
      label: "Persistent terminal sessions",
      description:
        "Reopen the app to restore tabs, panes, drawers, layouts, and terminal sessions.",
      beforeLabel: "Before close",
      restoredLabel: "Restored",
      beforeImageDescription:
        "Five tabs, All Panes, a CI workflow diff in Review, and Claude Code in the matching worktree before closing.",
      restoredImageDescription:
        "The same five tabs, All Panes grouping, CI workflow diff, Claude Code worktree, pull request, and terminal session after reopening.",
    },
  },
  featureDetails: {
    eyebrow: "More of the workspace",
    headline: "The work around each agent matters too.",
    description: "Sessions, layouts, pane types, and CLI agents stay part of the same workspace.",
    items: [
      {
        id: "persistence",
        title: "Close the app. Keep the work.",
        summary: "Terminal processes keep running while the workspace closes.",
        detail:
          "Reopen Agent Studio to restore tabs, panes, drawers, layouts, and visible terminal sessions instead of rebuilding the workspace by hand.",
      },
      {
        id: "arrangements",
        title: "Save the layout that fits the task.",
        summary: "Use named arrangements, or zoom one pane when you need focus.",
        detail:
          "Switch between saved arrangements without stopping the work in other panes, then return to the wider workspace when you are ready.",
        imageDescription:
          "A restored Agent Studio workspace with its tabs, panes, Review surface, and sidebar grouping intact.",
      },
      {
        id: "pane-types",
        title: "Use more than terminal panes.",
        summary: "Terminal, browser, Files, and Review panes share one workspace.",
        detail:
          "Keep source, diffs, browser context, and supporting terminals beside the task that needs them instead of opening another disconnected window.",
        imageDescription:
          "A terminal beside Agent Studio Review with a changed-files tree and unified diff.",
      },
      {
        id: "agent-agnostic",
        title: "Run the agents you already use.",
        summary: "Codex, Claude Code, and other CLI agents use the same workspace model.",
        detail:
          "Agent Studio organizes the repository, worktree, branch, and panes around the task without requiring one agent vendor or protocol.",
        imageDescription:
          "Codex and Claude Code working in separate panes inside one Agent Studio workspace.",
      },
    ],
  },
  installation: {
    commands: ["brew tap ShravanSunder/agentstudio", "brew install --cask agent-studio"],
    copyButton: "Copy install commands",
    copyButtonVisible: "Copy",
    copiedStatus: "Copied",
    failedStatus: "Select and copy the command",
  },
  navigation: {
    homeLabel: "Agent Studio home",
    primaryLabel: "Primary navigation",
    githubAction: "GitHub",
  },
  socialLinks: {
    label: "Shravan Sunder profile links",
    github: {
      label: "Shravan Sunder on GitHub",
      url: "https://github.com/shravansunder",
    },
    x: {
      label: "Shravan Sunder on X",
      url: "https://x.com/shravansunder",
    },
  },
  finalCallToAction: {
    description:
      "A workspace for keeping agents, terminals, source, reviews, and project context together.",
    traits: "Agent-agnostic. Repo-aware. Keyboard-first. Built on Ghostty.",
  },
  githubUrl: "https://github.com/ShravanSunder/agentstudio",
} as const;

export const installCommandText = marketingCopy.installation.commands.join("\n");
