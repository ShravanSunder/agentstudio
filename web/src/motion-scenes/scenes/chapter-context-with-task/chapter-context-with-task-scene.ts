import type { SceneBuildOptions, SceneModule, SceneTimeline } from "../../scene-contract";
import {
  requireLine,
  requireScenePart,
  requireTerminalLines,
  SceneTimelineBuilder,
} from "../scene-timeline-builder";
import {
  contextWithTaskFileTree,
  contextWithTaskParts,
  contextWithTaskPhoneDrawerScrollLines,
  contextWithTaskSource,
} from "./chapter-context-with-task-fixture";

const totalDurationSeconds = 11.5;

interface ContextWithTaskElements {
  readonly agentLines: readonly HTMLElement[];
  readonly drawer: HTMLElement;
  readonly drawerLines: readonly HTMLElement[];
  readonly footerBadges: HTMLElement;
  readonly sourceView: HTMLElement;
  readonly sourceLines: readonly HTMLElement[];
  readonly fileTree: HTMLElement;
  readonly fileTreeRows: readonly HTMLElement[];
}

function resolveContextWithTaskElements(root: HTMLElement): ContextWithTaskElements {
  return {
    agentLines: requireTerminalLines(
      requireScenePart(root, contextWithTaskParts.agentTerminal),
      contextWithTaskParts.agentTerminal,
      7,
    ),
    drawer: requireScenePart(root, contextWithTaskParts.drawer),
    drawerLines: requireTerminalLines(
      requireScenePart(root, contextWithTaskParts.drawerTerminal),
      contextWithTaskParts.drawerTerminal,
      9,
    ),
    footerBadges: requireScenePart(root, contextWithTaskParts.footerBadges),
    sourceView: requireScenePart(root, contextWithTaskParts.sourceView),
    sourceLines: contextWithTaskSource.lines.map((_line, lineIndex) =>
      requireScenePart(root, `${contextWithTaskParts.sourceLinePrefix}-${String(lineIndex)}`),
    ),
    fileTree: requireScenePart(root, contextWithTaskParts.fileTree),
    fileTreeRows: contextWithTaskFileTree.map((_row, rowIndex) =>
      requireScenePart(root, `${contextWithTaskParts.fileTreeRowPrefix}-${String(rowIndex)}`),
    ),
  };
}

function buildContextWithTaskScene(
  root: HTMLElement,
  timeline: SceneTimeline,
  options: SceneBuildOptions,
): void {
  const elements = resolveContextWithTaskElements(root);
  const builder = new SceneTimelineBuilder(timeline, options.seed);
  const agent = (lineIndex: number): HTMLElement => requireLine(elements.agentLines, lineIndex);
  const drawer = (lineIndex: number): HTMLElement => requireLine(elements.drawerLines, lineIndex);

  // Beat 1: the agent works; a Git terminal slides up in the drawer it owns.
  builder.label("task-drawers", 0);
  builder.showAndTypeLine(agent(0), 0.2, 12);
  builder.showAndTypeLine(agent(2), 0.6, 44);
  builder.showAndTypeLine(agent(4), 1.7, 80);
  builder.showAndTypeLine(agent(5), 2.15, 75);
  builder.showAndTypeLine(agent(6), 2.7, 75);
  builder.reveal(elements.drawer, 1.9, { duration: 0.55, fromYPercent: 100, ease: "power3.out" });
  const statusTyped = builder.showAndTypeLine(drawer(0), 2.6, 24);
  [1, 2, 3, 4].forEach((lineIndex, offset) => {
    builder.reveal(drawer(lineIndex), statusTyped + 0.1 + offset * 0.1, { duration: 0.12 });
  });

  // Beat 2: the branch history and its pull request print beside the task.
  builder.label("git-context", 4.8);
  builder.variable(root, {
    name: "--scene-drawer-scroll",
    from: 0,
    to: contextWithTaskPhoneDrawerScrollLines,
    at: 4.85,
    duration: 0.45,
  });
  const logTyped = builder.showAndTypeLine(drawer(5), 5.0, 20);
  builder.reveal(drawer(6), logTyped + 0.12, { duration: 0.15 });
  builder.reveal(drawer(7), logTyped + 0.3, { duration: 0.15 });
  builder.reveal(drawer(8), logTyped + 0.5, { duration: 0.05 });
  builder.reveal(elements.footerBadges, logTyped + 0.55, { duration: 0.35, fromY: 4 });

  // Beat 3: Files opens the changed source beside the same task.
  builder.label("files", 7.6);
  builder.variable(root, {
    name: "--scene-files-reveal",
    from: 0,
    to: 1,
    at: 7.75,
    duration: 0.75,
  });
  builder.reveal(elements.sourceView, 7.9, { duration: 0.3 });
  builder.reveal(elements.fileTree, 8.0, { duration: 0.3 });
  elements.fileTreeRows.forEach((row, rowIndex) => {
    builder.reveal(row, 8.3 + rowIndex * 0.07, { duration: 0.2, fromX: -6 });
  });
  elements.sourceLines.forEach((line, lineIndex) => {
    builder.reveal(line, 8.5 + lineIndex * 0.08, { duration: 0.2, fromX: -6 });
  });

  builder.holdUntil(totalDurationSeconds);
}

export const chapterContextWithTaskScene: SceneModule = {
  sceneId: "chapter-context-with-task",
  steps: [
    { stepId: "task-drawers", timelineLabel: "task-drawers" },
    { stepId: "git-context", timelineLabel: "git-context" },
    { stepId: "files", timelineLabel: "files" },
  ],
  buildScene: buildContextWithTaskScene,
};
