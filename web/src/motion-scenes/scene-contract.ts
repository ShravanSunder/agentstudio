import type { gsap } from "gsap";

// Type-only in both directions: the chapter catalog names scene ids and scenes
// name chapter step ids, and neither import survives compilation.
import type { ChapterStepId } from "../chapters/chapter-catalog";

export const sceneIds = [
  "chapter-many-agents",
  "chapter-context-with-task",
  "chapter-find-and-focus",
] as const;

export type SceneId = (typeof sceneIds)[number];

export function isSceneId(value: string): value is SceneId {
  return (sceneIds as readonly string[]).includes(value);
}

/**
 * The host-owned GSAP timeline a scene adds tweens to: `gsap.core.Timeline`.
 * GSAP's `gsap.core` types live in a global namespace; deriving from the
 * imported `gsap` keeps this file bound to the installed package's types.
 */
export type SceneTimeline = ReturnType<typeof gsap.timeline>;

export interface SceneBuildOptions {
  readonly width: number;
  readonly height: number;
  readonly seed: number;
}

export interface SceneStep {
  readonly stepId: ChapterStepId;
  readonly timelineLabel: string;
}

/**
 * One scene module serves two hosts: the website's ScenePlayback and a
 * HyperFrames composition. Both own the paused timeline and seek it freely,
 * so a scene must be a pure function of timeline time.
 */
export interface SceneModule {
  readonly sceneId: SceneId;
  readonly steps: readonly SceneStep[];
  /**
   * Adds tweens to a PAUSED host-owned timeline; never creates one. Markup is
   * rendered in its settled (final) state and tweens use from()/fromTo(), so
   * the timeline's end equals the no-JavaScript markup. Build is synchronous
   * and must not use requestAnimationFrame, Math.random, Date.now,
   * performance.now, or gsap.utils.random; randomness comes from
   * createSeededRandom(options.seed).
   */
  buildScene(root: HTMLElement, timeline: SceneTimeline, options: SceneBuildOptions): void;
}

/**
 * Mulberry32: a small deterministic PRNG returning values in [0, 1). The same
 * seed yields the same sequence on every host, which keeps HyperFrames renders
 * and the live site frame-identical.
 */
export function createSeededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return (): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let mixed = state;
    mixed = Math.imul(mixed ^ (mixed >>> 15), mixed | 1);
    mixed ^= mixed + Math.imul(mixed ^ (mixed >>> 7), mixed | 61);
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4_294_967_296;
  };
}
