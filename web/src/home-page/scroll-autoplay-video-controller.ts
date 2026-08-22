interface ScrollAutoplayVideoController {
  readonly dispose: () => void;
  readonly synchronize: (progress: number, autoplayEnabled: boolean) => void;
}

type PlaybackIntent = "auto" | "manual-pause" | "manual-play";

interface VideoPlaybackState {
  automaticPauseEventPending: boolean;
  automaticPlayEventPending: boolean;
  autoplayEnabled: boolean;
  awaitingReplay: boolean;
  intent: PlaybackIntent;
  latestProgress: number;
  replayTimer: number | undefined;
}

const defaultStartProgress = 0.95;
const defaultStopProgress = 0.9;
const defaultReplayDelayMs = 3000;

function readNumberAttribute(video: HTMLVideoElement, name: string, fallback: number): number {
  const value = Number.parseFloat(video.getAttribute(name) ?? "");
  return Number.isFinite(value) ? value : fallback;
}

function createVideoPlaybackController(video: HTMLVideoElement): ScrollAutoplayVideoController {
  const startProgress = readNumberAttribute(
    video,
    "data-scroll-autoplay-start-progress",
    defaultStartProgress,
  );
  const stopProgress = readNumberAttribute(
    video,
    "data-scroll-autoplay-stop-progress",
    defaultStopProgress,
  );
  const replayDelayMs = readNumberAttribute(
    video,
    "data-scroll-autoplay-replay-delay-ms",
    defaultReplayDelayMs,
  );
  const state: VideoPlaybackState = {
    automaticPauseEventPending: false,
    automaticPlayEventPending: false,
    autoplayEnabled: true,
    awaitingReplay: video.ended,
    intent: video.paused ? "auto" : "manual-play",
    latestProgress: 0,
    replayTimer: undefined,
  };

  const clearReplayTimer = (): void => {
    if (state.replayTimer === undefined) {
      return;
    }
    window.clearTimeout(state.replayTimer);
    state.replayTimer = undefined;
  };

  const playAutomatically = (): void => {
    if (!video.paused || state.intent !== "auto") {
      return;
    }
    state.automaticPlayEventPending = true;
    void video.play().catch((): void => {
      state.automaticPlayEventPending = false;
    });
  };

  const pauseAutomatically = (): void => {
    if (video.paused || state.intent === "manual-play") {
      return;
    }
    state.automaticPauseEventPending = true;
    video.pause();
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
      state.awaitingReplay = false;
      playAutomatically();
    }, replayDelayMs);
  };

  const handlePlay = (): void => {
    if (state.automaticPlayEventPending) {
      state.automaticPlayEventPending = false;
      if (!state.autoplayEnabled || state.latestProgress < stopProgress) {
        pauseAutomatically();
      }
      return;
    }
    clearReplayTimer();
    state.awaitingReplay = false;
    state.intent = "manual-play";
  };

  const handlePause = (): void => {
    if (state.automaticPauseEventPending) {
      state.automaticPauseEventPending = false;
      return;
    }
    if (video.ended) {
      return;
    }
    clearReplayTimer();
    state.awaitingReplay = false;
    state.intent = "manual-pause";
  };

  const handleEnded = (): void => {
    state.automaticPauseEventPending = false;
    state.automaticPlayEventPending = false;
    state.awaitingReplay = true;
    state.intent = "auto";
    video.currentTime = 0;
    replayIfEligible();
  };

  video.addEventListener("play", handlePlay);
  video.addEventListener("pause", handlePause);
  video.addEventListener("ended", handleEnded);

  return {
    dispose: (): void => {
      clearReplayTimer();
      video.removeEventListener("play", handlePlay);
      video.removeEventListener("pause", handlePause);
      video.removeEventListener("ended", handleEnded);
    },
    synchronize: (progress: number, autoplayEnabled: boolean): void => {
      state.latestProgress = progress;
      state.autoplayEnabled = autoplayEnabled;

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

export function createScrollAutoplayVideoController(
  surface: HTMLElement,
): ScrollAutoplayVideoController {
  const videoControllers = Array.from(
    surface.querySelectorAll<HTMLVideoElement>("[data-scroll-autoplay-video]"),
    createVideoPlaybackController,
  );

  return {
    dispose: (): void => {
      for (const controller of videoControllers) {
        controller.dispose();
      }
    },
    synchronize: (progress: number, autoplayEnabled: boolean): void => {
      for (const controller of videoControllers) {
        controller.synchronize(progress, autoplayEnabled);
      }
    },
  };
}
