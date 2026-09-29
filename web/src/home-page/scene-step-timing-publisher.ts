import { computeStepDwellSeconds } from "../chapters/chapter-step-dwell";
import { createSceneStepTimingEvent } from "../chapters/chapter-step-events";
import type { SceneModule, SceneTimeline } from "../motion-scenes/scene-contract";

export interface SceneStepTimingProps {
  readonly awaitingReplay: boolean;
  readonly manualPause: boolean;
  readonly playingScene: boolean;
  readonly proofVideo: HTMLVideoElement | null;
  readonly proofVideoEnded: boolean;
  readonly replayDelayMs: number;
  readonly replayTimerActive: boolean;
  readonly replayTimerStartedAt: number | undefined;
  readonly sceneModule: SceneModule;
  readonly sceneRoot: HTMLElement;
  readonly stepId: string;
  readonly timeline: SceneTimeline;
}

/** Publish one scene-owned dwell sample at a step or control boundary. */
export function publishSceneStepTiming(props: SceneStepTimingProps): void {
  const stepIndex = props.sceneModule.steps.findIndex((step) => step.stepId === props.stepId);
  if (stepIndex < 0) return;
  const labelTimes = props.sceneModule.steps.map(
    (step) => props.timeline.labels[step.timelineLabel] ?? 0,
  );
  const labelTime = labelTimes[stepIndex] ?? 0;
  const proofVideo = props.proofVideo;
  const dwellSeconds =
    computeStepDwellSeconds({
      labelTimes,
      timelineDuration: props.timeline.duration(),
      proofSeconds:
        proofVideo !== null && Number.isFinite(proofVideo.duration) ? proofVideo.duration : 0,
      replayDelaySeconds: props.replayDelayMs / 1000,
    })[stepIndex] ?? 0;
  const proofElapsed = props.awaitingReplay
    ? (props.proofVideoEnded && proofVideo !== null && Number.isFinite(proofVideo.duration)
        ? proofVideo.duration
        : (proofVideo?.currentTime ?? 0)) +
      (props.replayTimerStartedAt === undefined
        ? 0
        : (performance.now() - props.replayTimerStartedAt) / 1000)
    : 0;
  props.sceneRoot.dispatchEvent(
    createSceneStepTimingEvent({
      stepId: props.stepId,
      dwellSeconds,
      elapsedSeconds: Math.max(0, props.timeline.time() - labelTime + proofElapsed),
      manualPause: props.manualPause,
      running:
        (props.playingScene && !props.timeline.paused()) ||
        (props.awaitingReplay &&
          ((proofVideo !== null && !proofVideo.paused) || props.replayTimerActive)),
    }),
  );
}
