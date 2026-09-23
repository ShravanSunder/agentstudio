import { gsap } from "gsap";

import { sceneRootAttribute } from "../chapters/chapter-dom-contract";
import {
  chapterStepRequestedEventName,
  createChapterStepEvent,
  readChapterStepEventStepId,
  sceneStepReachedEventName,
} from "../chapters/chapter-step-events";
import {
  isSceneId,
  type SceneId,
  type SceneModule,
  type SceneTimeline,
} from "../motion-scenes/scene-contract";
import { resolveSceneModule } from "../motion-scenes/scene-registry";
import { findSceneProofLayer, type SceneProofTransition } from "./scene-proof-layer";
import { combineSurfacePlaybacks, type SurfacePlayback } from "./surface-playback";

// Same thresholds and replay delay as the scroll-autoplay video, so a scene and
// a video on the page start, stop, and loop at the same scroll positions.
const startProgress = 0.95;
const stopProgress = 0.9;
const replayDelayMs = 3000;
const sceneSeed = 1;
const reducedMotionQuery = "(prefers-reduced-motion: reduce)";

/** The visitor's play/pause control for a scene; hidden until motion can run. */
const scenePlaybackToggleSelector = "[data-scene-playback-toggle]";

export type SceneModuleResolver = (sceneId: SceneId) => SceneModule | undefined;

/**
 * `settled` means no timeline exists and the markup shows the scene's final,
 * no-script state. `awaiting-replay` holds that final frame between loops.
 */
export type ScenePlaybackPhase = "settled" | "playing" | "paused" | "awaiting-replay";

type PlaybackIntent = "auto" | "manual-pause" | "manual-play";

export interface ScenePlaybackProps {
  readonly resolveModule?: SceneModuleResolver;
  readonly sceneRoot: HTMLElement;
  readonly surface: HTMLElement;
}

interface ScenePlaybackState {
  autoplayEnabled: boolean;
  awaitingReplay: boolean;
  buildFailed: boolean;
  intent: PlaybackIntent;
  lastReportedStepId: string | undefined;
  latestProgress: number;
  phase: ScenePlaybackPhase;
  replayTimer: number | undefined;
  timeline: SceneTimeline | undefined;
}

function readSceneModule(
  sceneRoot: HTMLElement,
  resolveModule: SceneModuleResolver,
): SceneModule | undefined {
  const sceneId = sceneRoot.getAttribute(sceneRootAttribute) ?? "";
  return isSceneId(sceneId) ? resolveModule(sceneId) : undefined;
}

function findStepAtTime(module: SceneModule, timeline: SceneTimeline): string | undefined {
  const playheadTime = timeline.time();
  let reachedStep: { readonly stepId: string; readonly labelTime: number } | undefined;
  for (const step of module.steps) {
    const labelTime = timeline.labels[step.timelineLabel];
    if (
      labelTime !== undefined &&
      labelTime <= playheadTime &&
      (reachedStep === undefined || labelTime >= reachedStep.labelTime)
    ) {
      reachedStep = { stepId: step.stepId, labelTime };
    }
  }
  return reachedStep?.stepId;
}

/**
 * Plays one scene module inside a glass surface with the scroll-autoplay
 * video's semantics: play when centered, pause with hysteresis when leaving,
 * replay after a delay while still centered, and let manual intent win.
 * Each completed pass hands the stage to the real capture until the replay.
 * Reduced motion or an unregistered module never builds tweens; reduced
 * motion shows the real capture as the static view.
 */
export function createScenePlayback(props: ScenePlaybackProps): SurfacePlayback {
  const { sceneRoot, surface } = props;
  const sceneModule = readSceneModule(sceneRoot, props.resolveModule ?? resolveSceneModule);
  const motionPreference = window.matchMedia(reducedMotionQuery);
  const toggle = surface.querySelector<HTMLButtonElement>(scenePlaybackToggleSelector);
  const proofLayer = findSceneProofLayer(surface, sceneRoot);
  const lifecycle = new AbortController();
  const state: ScenePlaybackState = {
    autoplayEnabled: true,
    awaitingReplay: false,
    buildFailed: false,
    intent: "auto",
    lastReportedStepId: undefined,
    latestProgress: 0,
    phase: "settled",
    replayTimer: undefined,
    timeline: undefined,
  };

  const motionAllowed = (): boolean =>
    sceneModule !== undefined && !state.buildFailed && !motionPreference.matches;

  // Show, then prove: the real capture holds the stage between loops, and it is
  // the static view whenever a registered scene cannot move (reduced motion or
  // a failed build). An unregistered module keeps the settled recreation.
  const proofBelongsToPhase = (phase: ScenePlaybackPhase): boolean =>
    phase === "awaiting-replay" ||
    (phase === "settled" &&
      sceneModule !== undefined &&
      (state.buildFailed || motionPreference.matches));

  const renderPhase = (
    phase: ScenePlaybackPhase,
    proofTransition: SceneProofTransition = "fade",
  ): void => {
    state.phase = phase;
    sceneRoot.dataset["scenePlaybackState"] = phase;
    proofLayer.render(proofBelongsToPhase(phase), proofTransition);
    if (toggle === null) {
      return;
    }
    toggle.hidden = !motionAllowed();
    toggle.dataset["playbackState"] = phase;
    const label = phase === "playing" ? toggle.dataset["pauseLabel"] : toggle.dataset["playLabel"];
    if (label !== undefined) {
      toggle.setAttribute("aria-label", label);
    }
  };

  const reportStep = (stepId: string | undefined): void => {
    if (stepId === undefined || stepId === state.lastReportedStepId) {
      return;
    }
    state.lastReportedStepId = stepId;
    sceneRoot.dispatchEvent(createChapterStepEvent(sceneStepReachedEventName, stepId));
  };

  const clearReplayTimer = (): void => {
    if (state.replayTimer === undefined) {
      return;
    }
    window.clearTimeout(state.replayTimer);
    state.replayTimer = undefined;
  };

  const settle = (): void => {
    clearReplayTimer();
    state.timeline?.revert();
    state.timeline = undefined;
    state.awaitingReplay = false;
    state.intent = "auto";
    state.lastReportedStepId = undefined;
    renderPhase("settled");
  };

  const handleTimelineComplete = (): void => {
    state.awaitingReplay = true;
    state.intent = "auto";
    renderPhase("awaiting-replay");
    replayIfEligible();
  };

  const ensureTimeline = (): SceneTimeline | undefined => {
    if (state.timeline !== undefined || sceneModule === undefined || !motionAllowed()) {
      return state.timeline;
    }
    const timeline = gsap.timeline({ paused: true });
    try {
      sceneModule.buildScene(sceneRoot, timeline, {
        height: sceneRoot.clientHeight,
        seed: sceneSeed,
        width: sceneRoot.clientWidth,
      });
    } catch (error: unknown) {
      // Markup that does not match its module (a missing scene part) is treated
      // like an unregistered module: drop the partial timeline, keep the settled
      // markup, and never retry this build.
      timeline.revert();
      timeline.kill();
      state.buildFailed = true;
      console.warn(
        `Scene "${sceneModule.sceneId}" could not build; showing its settled frame.`,
        error,
      );
      renderPhase("settled");
      return undefined;
    }
    timeline.eventCallback("onUpdate", (): void => {
      reportStep(findStepAtTime(sceneModule, timeline));
    });
    timeline.eventCallback("onComplete", handleTimelineComplete);
    state.timeline = timeline;
    return timeline;
  };

  // Resting and awaiting-replay both show the final frame, so play restarts.
  const startTimeline = (timeline: SceneTimeline): void => {
    if (timeline.progress() >= 1) {
      timeline.restart();
    } else {
      timeline.play();
    }
    renderPhase("playing");
    if (sceneModule !== undefined) {
      reportStep(findStepAtTime(sceneModule, timeline));
    }
  };

  const playAutomatically = (): void => {
    if (state.phase === "playing" || state.intent !== "auto") {
      return;
    }
    const timeline = ensureTimeline();
    if (timeline !== undefined) {
      state.awaitingReplay = false;
      startTimeline(timeline);
    }
  };

  const pauseAutomatically = (): void => {
    if (state.phase !== "playing" || state.intent === "manual-play") {
      return;
    }
    state.timeline?.pause();
    renderPhase("paused");
  };

  const replayIfEligible = (): void => {
    if (
      state.replayTimer !== undefined ||
      !state.awaitingReplay ||
      !state.autoplayEnabled ||
      state.intent !== "auto" ||
      state.latestProgress < startProgress
    ) {
      return;
    }
    state.replayTimer = window.setTimeout((): void => {
      state.replayTimer = undefined;
      if (
        !state.autoplayEnabled ||
        state.intent !== "auto" ||
        state.latestProgress < startProgress
      ) {
        return;
      }
      playAutomatically();
    }, replayDelayMs);
  };

  const playManually = (timeline: SceneTimeline): void => {
    clearReplayTimer();
    state.awaitingReplay = false;
    state.intent = "manual-play";
    startTimeline(timeline);
  };

  const handleToggle = (): void => {
    if (state.phase === "playing") {
      clearReplayTimer();
      state.awaitingReplay = false;
      state.intent = "manual-pause";
      state.timeline?.pause();
      renderPhase("paused");
      return;
    }
    const timeline = ensureTimeline();
    if (timeline !== undefined) {
      playManually(timeline);
    }
  };

  const handleStepRequest = (event: Event): void => {
    const stepId = readChapterStepEventStepId(event);
    const step = sceneModule?.steps.find((candidate) => candidate.stepId === stepId);
    const timeline = step === undefined ? undefined : ensureTimeline();
    if (step === undefined || timeline === undefined) {
      return;
    }
    // A step chosen during the proof beat drops the proof at once, then seeks.
    proofLayer.render(false, "instant");
    timeline.pause(step.timelineLabel);
    playManually(timeline);
  };

  toggle?.addEventListener("click", handleToggle, { signal: lifecycle.signal });
  surface.addEventListener(chapterStepRequestedEventName, handleStepRequest, {
    signal: lifecycle.signal,
  });
  renderPhase("settled", "instant");

  return {
    dispose: (): void => {
      lifecycle.abort();
      settle();
    },
    synchronize: (progress: number, autoplayEnabled: boolean): void => {
      state.latestProgress = progress;
      state.autoplayEnabled = autoplayEnabled;
      // Follows a reduced-motion change that happens before any timeline exists.
      proofLayer.render(proofBelongsToPhase(state.phase), "instant");

      if (!motionAllowed()) {
        if (state.timeline !== undefined) {
          settle();
        }
        return;
      }
      if (progress < startProgress) {
        clearReplayTimer();
      }
      if (state.intent === "manual-play") {
        return;
      }
      if (!autoplayEnabled) {
        pauseAutomatically();
        return;
      }
      if (progress < stopProgress) {
        if (state.intent === "manual-pause") {
          state.intent = "auto";
        }
        pauseAutomatically();
        return;
      }
      if (progress < startProgress || state.intent === "manual-pause") {
        return;
      }
      if (state.awaitingReplay) {
        replayIfEligible();
        return;
      }
      playAutomatically();
    },
  };
}

/** One scene playback per `data-scene-root` inside the surface. */
export function createSurfaceScenePlayback(surface: HTMLElement): SurfacePlayback {
  return combineSurfacePlaybacks(
    Array.from(
      surface.querySelectorAll<HTMLElement>(`[${sceneRootAttribute}]`),
      (sceneRoot): SurfacePlayback => createScenePlayback({ sceneRoot, surface }),
    ),
  );
}
