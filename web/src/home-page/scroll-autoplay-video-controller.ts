interface ScrollAutoplayVideoController {
  readonly dispose: () => void;
  readonly synchronize: (progress: number, autoplayEnabled: boolean) => void;
}

type PlaybackIntent = "auto" | "manual-pause" | "manual-play";
type AutomaticTransition = "pause" | "play";

interface VideoPlaybackState {
  automaticTransition: AutomaticTransition | undefined;
  autoplayEnabled: boolean;
  intent: PlaybackIntent;
  latestProgress: number;
  replayTimer: number | undefined;
}

const defaultStartProgress = 0.9;
const defaultStopProgress = 0.85;
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
    automaticTransition: undefined,
    autoplayEnabled: true,
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
    state.automaticTransition = "play";
    void video.play().catch((): void => {
      if (state.automaticTransition === "play") {
        state.automaticTransition = undefined;
      }
    });
  };

  const pauseAutomatically = (): void => {
    if (video.paused || state.intent === "manual-play") {
      return;
    }
    state.automaticTransition = "pause";
    video.pause();
  };

  const replayIfEligible = (): void => {
    clearReplayTimer();
    if (!state.autoplayEnabled || state.intent !== "auto" || state.latestProgress < startProgress) {
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
      video.currentTime = 0;
      playAutomatically();
    }, replayDelayMs);
  };

  const handlePlay = (): void => {
    if (state.automaticTransition === "play") {
      state.automaticTransition = undefined;
      return;
    }
    clearReplayTimer();
    state.intent = "manual-play";
  };

  const handlePause = (): void => {
    if (state.automaticTransition === "pause") {
      state.automaticTransition = undefined;
      return;
    }
    if (video.ended) {
      return;
    }
    clearReplayTimer();
    state.intent = "manual-pause";
  };

  const handleEnded = (): void => {
    state.automaticTransition = undefined;
    state.intent = "auto";
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
      if (video.ended) {
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
