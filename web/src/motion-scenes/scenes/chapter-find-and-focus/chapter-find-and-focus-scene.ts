import type { SceneBuildOptions, SceneModule, SceneTimeline } from "../../scene-contract";
import {
  requireLine,
  requireScenePart,
  requireTerminalLines,
  SceneTimelineBuilder,
} from "../scene-timeline-builder";
import {
  findAndFocusParts,
  findAndFocusTargetLateLineIndexes,
} from "./chapter-find-and-focus-fixture";

const totalDurationSeconds = 8;

interface FindAndFocusElements {
  readonly arrangementZoom: HTMLElement;
  readonly commandBar: HTMLElement;
  readonly commandPlaceholder: HTMLElement;
  readonly commandQuery: HTMLElement;
  readonly recentSection: HTMLElement;
  readonly panesSection: HTMLElement;
  readonly worktreesSection: HTMLElement;
  readonly targetLines: readonly HTMLElement[];
  readonly targetFocusRing: HTMLElement;
  readonly targetZoomedChip: HTMLElement;
}

function resolveFindAndFocusElements(root: HTMLElement): FindAndFocusElements {
  return {
    arrangementZoom: requireScenePart(root, findAndFocusParts.arrangementZoom),
    commandBar: requireScenePart(root, findAndFocusParts.commandBar),
    commandPlaceholder: requireScenePart(root, findAndFocusParts.commandPlaceholder),
    commandQuery: requireScenePart(root, findAndFocusParts.commandQuery),
    recentSection: requireScenePart(root, findAndFocusParts.recentSection),
    panesSection: requireScenePart(root, findAndFocusParts.panesSection),
    worktreesSection: requireScenePart(root, findAndFocusParts.worktreesSection),
    targetLines: requireTerminalLines(
      requireScenePart(root, findAndFocusParts.targetTerminal),
      findAndFocusParts.targetTerminal,
      9,
    ),
    targetFocusRing: requireScenePart(root, findAndFocusParts.targetFocusRing),
    targetZoomedChip: requireScenePart(root, findAndFocusParts.targetZoomedChip),
  };
}

function buildFindAndFocusScene(
  root: HTMLElement,
  timeline: SceneTimeline,
  options: SceneBuildOptions,
): void {
  const elements = resolveFindAndFocusElements(root);
  const builder = new SceneTimelineBuilder(timeline, options.seed);

  // Beat 1: Cmd+P opens the command bar, a short query finds the pane, Enter jumps to it.
  builder.label("quick-find", 0);
  builder.reveal(elements.commandBar, 0.1, { duration: 0.25, fromScale: 0.97, fromY: -8 });
  builder.conceal(elements.commandPlaceholder, 0.45, { duration: 0.1 });
  const queryTyped = builder.type(elements.commandQuery, 0.5, builder.vary(9, 0.1));
  builder.collapse(elements.recentSection, queryTyped + 0.1, 0.3);
  builder.expand(elements.panesSection, queryTyped + 0.15, 0.3);
  builder.expand(elements.worktreesSection, queryTyped + 0.25, 0.3);
  const barClosed = builder.conceal(elements.commandBar, 2.3, { duration: 0.2 });
  builder.reveal(elements.targetFocusRing, barClosed + 0.05, { duration: 0.25 });

  // Beat 2: Pane Zoom gives the found pane the workspace; its agent keeps going.
  builder.label("pane-zoom", 3.0);
  const zoomed = builder.variable(root, {
    name: "--scene-zoom",
    from: 0,
    to: 1,
    at: 3.0,
    duration: 0.5,
  });
  builder.reveal(elements.arrangementZoom, 3.1, { duration: 0.25 });
  builder.reveal(elements.targetZoomedChip, 3.15, { duration: 0.25, fromY: 4 });
  findAndFocusTargetLateLineIndexes.forEach((lineIndex, offset) => {
    builder.showAndTypeLine(
      requireLine(elements.targetLines, lineIndex),
      zoomed + 0.2 + offset * 0.6,
      60,
    );
  });

  builder.holdUntil(totalDurationSeconds);
}

export const chapterFindAndFocusScene: SceneModule = {
  sceneId: "chapter-find-and-focus",
  steps: [
    { stepId: "quick-find", timelineLabel: "quick-find" },
    { stepId: "pane-zoom", timelineLabel: "pane-zoom" },
  ],
  buildScene: buildFindAndFocusScene,
};
