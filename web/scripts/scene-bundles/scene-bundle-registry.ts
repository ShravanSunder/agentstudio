// The global contract a scene.js fulfils when a host loads it as a classic
// script: one entry per scene on `window.AgentStudioScenes`.

import type { SceneBuildOptions, SceneTimeline } from "../../src/motion-scenes/scene-contract.ts";

export interface RegisteredSceneBundle {
  /** Timeline label name to time in seconds, in time order. */
  readonly labels: Readonly<Record<string, number>>;
  readonly durationSeconds: number;
  /** Adds the scene's tweens to the host's paused timeline; a plain function, not a method. */
  readonly buildScene: (
    root: HTMLElement,
    timeline: SceneTimeline,
    options: SceneBuildOptions,
  ) => void;
}

declare global {
  interface Window {
    AgentStudioScenes?: Record<string, RegisteredSceneBundle>;
  }
}
