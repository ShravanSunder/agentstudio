// Settled-frame content for "Many agents, one map". Curated neutral agent
// output and repository names only; no usage banners, modes, or personal paths.
import type { ChapterStepId } from "../../../chapters/chapter-ids";
import type {
  KitPaneFooterModel,
  KitSidebarModel,
  KitTerminalLine,
  KitToolbarModel,
} from "../../../recreation-kit/recreation-kit-model";

export const manyAgentsParts = {
  leftPane: "left-pane",
  rightPane: "right-pane",
  leftTerminal: "left-terminal",
  leftFirstMessage: "left-first-message",
  rightTerminal: "right-terminal",
  filterPlaceholder: "filter-placeholder",
  filterQuery: "filter-query",
  filterClear: "filter-clear",
  mainWorktree: "worktree-agent-studio-main",
  agentVmRepo: "repo-agent-vm",
  agentVmMainWorktree: "worktree-agent-vm-main",
  agentVmToolPortalWorktree: "worktree-agent-vm-tool-portal",
} as const;

/** The element that carries each beat's point; tests require it visible soon after the label. */
export const chapterManyAgentsStepKeyParts = {
  "parallel-agents": manyAgentsParts.leftFirstMessage,
  "watch-folders": manyAgentsParts.agentVmRepo,
  navigation: manyAgentsParts.filterQuery,
} as const satisfies Partial<Record<ChapterStepId, string>>;

export const manyAgentsAccessibleLabel =
  "Recreated Agent Studio window. Two agents work in separate worktrees while the sidebar lists your repositories, then a filter narrows it to the matching worktrees.";

export const manyAgentsToolbar: KitToolbarModel = {
  arrangementLabel: "1 · Parallel agents",
  tabs: [
    { title: "sidebar-filter", shortcutNumber: 1, selected: true },
    { title: "sidebar-grouping", shortcutNumber: 2, selected: false },
    { title: "agent-studio · main", shortcutNumber: 3, selected: false },
  ],
  tabCount: 3,
};

export const manyAgentsSidebar: KitSidebarModel = {
  filterPlaceholder: "Filter...",
  filterQuery: "sidebar",
  groupingLabel: "By Repo",
  sectionTitle: "REPOSITORIES",
  repos: [
    {
      repoName: "agent-studio",
      settledPresence: "shown",
      worktrees: [
        {
          worktreeName: "agent-studio.sidebar-filter",
          branchName: "sidebar-filter",
          badges: [
            { kind: "diff", added: 37, removed: 6 },
            { kind: "recency", label: "Now" },
          ],
          settledPresence: "shown",
        },
        {
          worktreeName: "agent-studio.sidebar-grouping",
          branchName: "sidebar-grouping",
          badges: [
            { kind: "diff", added: 85, removed: 5 },
            { kind: "recency", label: "Now" },
          ],
          settledPresence: "shown",
        },
        {
          worktreeName: "agent-studio",
          branchName: "main",
          badges: [{ kind: "sync", ahead: 0, behind: 4 }],
          settledPresence: "collapsed",
          scenePart: manyAgentsParts.mainWorktree,
        },
      ],
    },
    {
      repoName: "agent-vm",
      settledPresence: "collapsed",
      scenePart: manyAgentsParts.agentVmRepo,
      worktrees: [
        {
          worktreeName: "agent-vm",
          branchName: "main",
          badges: [{ kind: "sync", ahead: 0, behind: 7 }],
          settledPresence: "shown",
          scenePart: manyAgentsParts.agentVmMainWorktree,
        },
        {
          worktreeName: "agent-vm.tool-portal",
          branchName: "tool-portal",
          badges: [{ kind: "pull-requests", count: 1 }],
          settledPresence: "shown",
          scenePart: manyAgentsParts.agentVmToolPortalWorktree,
        },
      ],
    },
  ],
};

export const manyAgentsLeftTerminal: readonly KitTerminalLine[] = [
  {
    kind: "shell-prompt",
    worktreeName: "agent-studio.sidebar-filter",
    branchName: "sidebar-filter",
    command: "agent",
  },
  { kind: "blank" },
  { kind: "user-message", text: "Filter repos and worktrees." },
  { kind: "blank" },
  { kind: "agent-activity", text: "Reading the sidebar list model" },
  {
    kind: "agent-message",
    text: "Matches repo and worktree names.",
    scenePart: manyAgentsParts.leftFirstMessage,
  },
  { kind: "agent-message", text: "Each match keeps its badges." },
  { kind: "agent-activity", text: "Ran the sidebar tests" },
  { kind: "agent-message", text: "Ready for review." },
  { kind: "agent-input" },
];

export const manyAgentsRightTerminal: readonly KitTerminalLine[] = [
  {
    kind: "shell-prompt",
    worktreeName: "agent-studio.sidebar-grouping",
    branchName: "sidebar-grouping",
    command: "agent",
  },
  { kind: "blank" },
  { kind: "user-message", text: "Group worktrees under their repo." },
  { kind: "blank" },
  { kind: "agent-activity", text: "Reading the sidebar row builder" },
  { kind: "agent-message", text: "Worktrees now sit under their repo." },
  { kind: "agent-message", text: "Favorites stay pinned on top." },
  { kind: "agent-activity", text: "Ran the sidebar tests" },
  { kind: "agent-message", text: "Done. No other files changed." },
  { kind: "agent-input" },
];

export const manyAgentsLeftFooter: KitPaneFooterModel = {
  badges: [{ kind: "diff", added: 37, removed: 6 }],
  zoomed: false,
};

export const manyAgentsRightFooter: KitPaneFooterModel = {
  badges: [{ kind: "diff", added: 85, removed: 5 }],
  zoomed: false,
};
