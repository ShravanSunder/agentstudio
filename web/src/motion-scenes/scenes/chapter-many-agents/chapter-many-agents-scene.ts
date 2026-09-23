import type { SceneBuildOptions, SceneModule, SceneTimeline } from "../../scene-contract";
import {
  requireLine,
  requireScenePart,
  requireTerminalLines,
  SceneTimelineBuilder,
} from "../scene-timeline-builder";
import { manyAgentsParts } from "./chapter-many-agents-fixture";

const totalDurationSeconds = 11.5;

interface ManyAgentsElements {
  readonly leftPane: HTMLElement;
  readonly rightPane: HTMLElement;
  readonly leftLines: readonly HTMLElement[];
  readonly rightLines: readonly HTMLElement[];
  readonly filterPlaceholder: HTMLElement;
  readonly filterQuery: HTMLElement;
  readonly filterClear: HTMLElement;
  readonly mainWorktree: HTMLElement;
  readonly agentVmRepo: HTMLElement;
  readonly agentVmWorktrees: readonly HTMLElement[];
}

// Every element is resolved before the first tween exists, so incomplete
// markup fails without leaving a half-animated frame behind.
function resolveManyAgentsElements(root: HTMLElement): ManyAgentsElements {
  return {
    leftPane: requireScenePart(root, manyAgentsParts.leftPane),
    rightPane: requireScenePart(root, manyAgentsParts.rightPane),
    leftLines: requireTerminalLines(
      requireScenePart(root, manyAgentsParts.leftTerminal),
      manyAgentsParts.leftTerminal,
      9,
    ),
    rightLines: requireTerminalLines(
      requireScenePart(root, manyAgentsParts.rightTerminal),
      manyAgentsParts.rightTerminal,
      9,
    ),
    filterPlaceholder: requireScenePart(root, manyAgentsParts.filterPlaceholder),
    filterQuery: requireScenePart(root, manyAgentsParts.filterQuery),
    filterClear: requireScenePart(root, manyAgentsParts.filterClear),
    mainWorktree: requireScenePart(root, manyAgentsParts.mainWorktree),
    agentVmRepo: requireScenePart(root, manyAgentsParts.agentVmRepo),
    agentVmWorktrees: [
      requireScenePart(root, manyAgentsParts.agentVmMainWorktree),
      requireScenePart(root, manyAgentsParts.agentVmToolPortalWorktree),
    ],
  };
}

function buildManyAgentsScene(
  root: HTMLElement,
  timeline: SceneTimeline,
  options: SceneBuildOptions,
): void {
  const elements = resolveManyAgentsElements(root);
  const builder = new SceneTimelineBuilder(timeline, options.seed);
  const left = (lineIndex: number): HTMLElement => requireLine(elements.leftLines, lineIndex);
  const right = (lineIndex: number): HTMLElement => requireLine(elements.rightLines, lineIndex);

  // Beat 1: two panes open and two agents start work side by side.
  builder.label("parallel-agents", 0);
  builder.reveal(elements.leftPane, 0.15, { duration: 0.45, fromY: 14 });
  builder.reveal(elements.rightPane, 0.35, { duration: 0.45, fromY: 14 });
  builder.showAndTypeLine(left(0), 0.6, 12);
  builder.showAndTypeLine(right(0), 0.85, 12);
  builder.showAndTypeLine(left(2), 1.15, 42);
  builder.showAndTypeLine(right(2), 1.4, 42);
  const agentLineStarts = [2.6, 3.05, 3.5] as const;
  agentLineStarts.forEach((startSeconds, offset) => {
    builder.showAndTypeLine(left(4 + offset), startSeconds, 70);
    builder.showAndTypeLine(right(4 + offset), startSeconds + 0.22, 70);
  });

  // Beat 2: the watched folder fills the sidebar with every repo and worktree.
  builder.label("watch-folders", 4.6);
  builder.expand(elements.mainWorktree, 4.8, 0.4);
  builder.expand(elements.agentVmRepo, 5.3, 0.45);
  elements.agentVmWorktrees.forEach((worktree, offset) => {
    builder.reveal(worktree, 5.65 + offset * 0.3, { duration: 0.3, fromX: -8 });
  });
  // The agents keep working while the map fills in.
  builder.showAndTypeLine(left(7), 6.1, 70);
  builder.showAndTypeLine(right(7), 6.6, 70);

  // Beat 3: a filter narrows the sidebar to the worktrees that match.
  builder.label("navigation", 7.4);
  builder.conceal(elements.filterPlaceholder, 7.55, { duration: 0.12 });
  const typedQueryEnd = builder.type(elements.filterQuery, 7.62, builder.vary(9, 0.1));
  builder.reveal(elements.filterClear, typedQueryEnd + 0.05, { duration: 0.2 });
  builder.collapse(elements.mainWorktree, typedQueryEnd + 0.25, 0.4);
  builder.collapse(elements.agentVmRepo, typedQueryEnd + 0.32, 0.45);
  builder.showAndTypeLine(left(8), 8.6, 60);
  builder.showAndTypeLine(right(8), 9.1, 60);

  builder.holdUntil(totalDurationSeconds);
}

export const chapterManyAgentsScene: SceneModule = {
  sceneId: "chapter-many-agents",
  steps: [
    { stepId: "parallel-agents", timelineLabel: "parallel-agents" },
    { stepId: "watch-folders", timelineLabel: "watch-folders" },
    { stepId: "navigation", timelineLabel: "navigation" },
  ],
  buildScene: buildManyAgentsScene,
};
