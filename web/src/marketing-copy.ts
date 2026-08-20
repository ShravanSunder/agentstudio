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
        "Two terminal panes beside the All Panes sidebar, with repository, branch, Git, activity, and recency context.",
    },
    paneDrawer: {
      label: "Pane drawer",
      description:
        "Open a build log, git status, documentation, or a browser beside the agent that prompted it.",
      imageDescription: "A Git diff summary in a drawer attached to the right terminal pane.",
    },
    quickFind: {
      label: "Quick Find",
      description: "Press Cmd+P to reach repositories, worktrees, panes, tabs, and commands.",
      imageDescription:
        "Quick Find scoped to the agent-studio repository over a two-pane workspace.",
    },
    review: {
      label: "Review",
      description:
        "Agent Studio presents every changed file as one continuous, read-only diff with file-tree navigation and syntax highlighting.",
      imageDescription:
        "A read-only Swift diff and Changed Files tree beside the matching worktree terminal.",
    },
    persistence: {
      label: "Persistent terminal sessions",
      description:
        "Reopen the app to restore tabs, panes, drawers, layouts, and terminal sessions.",
      beforeLabel: "Before close",
      restoredLabel: "Restored",
      beforeImageDescription:
        "Five tabs, two visible terminal panes, drawer and Review entries, and the All Panes sidebar before closing.",
      restoredImageDescription:
        "Five restored tabs, the same terminal panes, drawer and Review entries, terminal output, and sidebar grouping after reopening.",
    },
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
    label: "Shravan Sunder on social media",
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
