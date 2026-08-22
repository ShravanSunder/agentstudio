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
      "Agent Studio organizes your work by repository and worktree, not by terminal tab.",
    accessibilityLabel: "Workspace views",
  },
  stories: {
    parallelWork: {
      label: "Parallel agents",
      description: "See which repo, worktree, branch, and directory each of your agents is using.",
      phoneDescription: "See every agent's repo, worktree, and branch.",
      imageDescription:
        "Agent Studio All Panes showing active Codex and Claude Code sessions with repository, worktree, branch, and activity context.",
    },
    watchFolders: {
      label: "Watch folders",
      description:
        "Choose your folders once. Agent Studio finds and keeps their repos and worktrees current.",
      phoneDescription: "Watch your folders. Agent Studio keeps their repos and worktrees current.",
      imageDescription:
        "Agent Studio welcome screen explaining Watch Folder discovery beside an example repository and worktree map.",
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
      description: "Press Cmd+P to find your repositories, worktrees, panes, tabs, and commands.",
      phoneDescription: "Find your repos, panes, and commands.",
      imageDescription:
        "Agent Studio command bar showing recent repositories and command, pane, and repository scopes with the global sidebar hidden.",
    },
    files: {
      label: "Files",
      description: "Browse your repository without leaving the task you're working on.",
      phoneDescription: "Keep source beside the task.",
      imageDescription:
        "Agent Studio Files showing a source file beside its repository tree, with Review available as the adjacent tab and the global sidebar hidden.",
    },
    review: {
      label: "Review",
      description:
        "Review every changed file in one continuous diff, with the Changed Files tree beside it.",
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
    eyebrow: "More for your workspace",
    headline: "Keep the rest of your work within reach.",
    description: "Sessions, source, reviews, and layouts stay close to the work that needs them.",
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
          beforeAccent: "Go big on ",
          accent: "one pane",
          afterAccent: ".",
        },
        summary: "Save arrangements for the layouts you return to.",
        detail:
          "When one pane needs your full attention, Pane Zoom gives it the whole workspace without stopping work in your other panes.",
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
