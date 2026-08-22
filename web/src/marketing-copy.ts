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
      label: "Parallel agents",
      description: "See which repository, worktree, branch, and directory each agent is using.",
      phoneDescription: "See every agent's repo and branch.",
      imageDescription:
        "Agent Studio All Panes showing active Codex and Claude Code sessions with repository, worktree, branch, and activity context.",
    },
    paneDrawer: {
      label: "Pane drawer",
      description: "Keep related terminals and tools attached to the agent that needs them.",
      phoneDescription: "Keep a Git terminal with its task.",
      imageDescription:
        "A Git-status drawer attached beneath Antigravity with the global sidebar hidden.",
    },
    quickFind: {
      label: "Command bar",
      description: "Press Cmd+P to find a repository, pane, or command.",
      phoneDescription: "Find repos, panes, and commands from the command bar.",
      imageDescription:
        "Agent Studio command bar showing recent repositories and command, pane, and repository scopes with the global sidebar hidden.",
    },
    review: {
      label: "Review",
      description: "Review every changed file in one continuous diff with its file tree beside it.",
      phoneDescription: "Browse changed files beside the diff.",
      imageDescription:
        "Agent Studio Review showing an AGENTS.md diff and its Changed Files tree, with the global sidebar hidden.",
    },
    gitContext: {
      label: "Git and PR context",
      description: "See the branch, changes, and pull request beside the work.",
      phoneDescription: "See a PR beside its branch and worktree.",
      imageDescription:
        "Agent Studio filtered to workspace-local, with PR 201 and branch status beside the By Repo sidebar.",
    },
    persistence: {
      label: "Persistent terminal sessions",
      description:
        "Reopen the app to restore tabs, panes, drawers, layouts, and terminal sessions.",
      beforeLabel: "Before close",
      restoredLabel: "Restored",
      beforeImageDescription:
        "Agent Studio before closing with All Panes, the Parallel agents arrangement, Codex, and Claude Code visible.",
      restoredImageDescription:
        "Agent Studio after reopening in the Parallel agents arrangement with All Panes, Codex, and continued Claude Code terminal output visible.",
    },
  },
  featureDetails: {
    eyebrow: "More of the workspace",
    headline: "Keep the rest of the work together.",
    description: "Files, reviews, sessions, and layouts stay part of the same workspace.",
    items: [
      {
        id: "pane-types",
        title: {
          kind: "accented",
          beforeAccent: "Keep ",
          accent: "tabs",
          afterAccent: " on your code.",
        },
        summary: "Browse source and review every changed file without leaving the workspace.",
        detail:
          "Files keeps the repository tree close. Review puts every changed file into one continuous diff.",
        imageDescription:
          "Agent Studio with Files and Review tabs above a changed-files tree and continuous diff, with the global sidebar hidden.",
      },
      {
        id: "persistence",
        title: {
          kind: "accented",
          beforeAccent: "Close the app, not your ",
          accent: "sessions",
          afterAccent: ".",
        },
        summary: "Terminal sessions keep running after Agent Studio closes.",
        detail:
          "Reopen the app to restore your tabs, panes, drawers, arrangements, and visible terminal sessions.",
      },
      {
        id: "arrangements",
        title: {
          kind: "accented",
          beforeAccent: "Get your ",
          accent: "panes",
          afterAccent: " in order.",
        },
        summary: "Save arrangements for the way you work, or zoom one pane when you need focus.",
        detail:
          "Switch arrangements without stopping work in other panes, then return to the wider workspace when you are ready.",
        savedArrangementLabel: "Saved layout",
        paneZoomLabel: "Pane Zoom",
        savedArrangementImageDescription:
          "Agent Studio with the Parallel agents arrangement active, showing Codex and Claude Code side by side with the global sidebar hidden.",
        paneZoomImageDescription: "Claude Code filling the Agent Studio workspace in Pane Zoom.",
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
