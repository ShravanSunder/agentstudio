export const marketingCopy = {
  productName: "Agent Studio",
  hero: {
    eyebrow: "Native macOS. Repo-aware. Terminal-first.",
    headline: "Run dozens of agents in one workspace. Stay oriented. Miss nothing.",
    headlineSetupFirst: "Run dozens of agents",
    headlineSetupSecondBeforeAccent: "in one ",
    headlineSetupSecondAccent: "workspace.",
    headlinePayoff: "Stay oriented. Miss nothing.",
    description:
      "Agent Studio is a native macOS IDE for parallel coding agents, with your repositories and worktrees within reach. Your agents run in Ghostty terminals with files and diffs right beside them.",
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
      label: "Watch your repos",
      description: "Agent Studio watches your repos. Stay oriented across every repo and worktree.",
      phoneDescription:
        "Agent Studio watches your repos. You can easily create or view terminals in all your repos.",
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
        id: "persistence",
        title: {
          kind: "accented",
          beforeAccent: "Close the app without stopping your ",
          accent: "persistent sessions",
          afterAccent: "",
        },
        summary: "Persistent terminal sessions keep running after Agent Studio closes.",
        detail:
          "Reopen the app to restore your tabs, panes, drawers, arrangements, and visible persistent terminal sessions.",
      },
      {
        id: "navigation",
        title: {
          kind: "accented",
          beforeAccent: "Find ",
          accent: "your way",
          afterAccent: " around",
        },
        summary: "Filter the sidebar to find matching repositories and worktrees.",
        detail: "Keep each result's branch and dirty-change state in view.",
        imageDescription:
          "Agent Studio's sidebar filtered to two matching worktrees, with their branch names and dirty-change badges visible.",
      },
      {
        id: "task-tools",
        title: {
          kind: "accented",
          beforeAccent: "Give ",
          accent: "your tools",
          afterAccent: " a home",
        },
        summary: "Give each task a main pane.",
        detail: "Keep its related terminals and tools together in an attached drawer.",
        imageDescription:
          "Agent Studio showing a Codex task with a related terminal in its attached drawer.",
      },
      {
        id: "git-context",
        title: {
          kind: "accented",
          beforeAccent: "Keep ",
          accent: "your Git",
          afterAccent: " close",
        },
        summary: "Keep the worktree, branch, and PR reference in view.",
        detail: "The terminal keeps that Git context beside the task that produced it.",
        imageDescription:
          "Agent Studio showing a worktree and branch with PR 201 visible in its terminal.",
      },
      {
        id: "arrangements",
        title: {
          kind: "accented",
          beforeAccent: "Go big on ",
          accent: "one pane",
          afterAccent: "",
        },
        summary: "Keep a named layout for the wider workspace.",
        detail: "When one task needs your full attention, Pane Zoom gives it the workspace.",
        savedArrangementLabel: "Saved layout",
        paneZoomLabel: "Pane Zoom",
        savedArrangementImageDescription: "Agent Studio with the named Layout 1 active.",
        paneZoomImageDescription:
          "The same Agent Studio task in Pane Zoom with its terminal, code, and Files context filling the workspace.",
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
  ghosttyUrl: "https://ghostty.org",
  finalCallToAction: {
    description: "A native macOS IDE for parallel agents and all your work.",
    traits: "Native macOS. Repo-aware. Terminal-first.",
    technologyCredit: "👻 Built on Ghostty. ",
    creatorPrefix: "🛠️ Made by ",
    creatorName: "Shravan Sunder",
  },
  githubUrl: "https://github.com/ShravanSunder/agentstudio",
} as const;

export const installCommandText = marketingCopy.installation.commands.join("\n");
