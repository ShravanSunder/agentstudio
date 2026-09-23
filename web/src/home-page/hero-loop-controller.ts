// The hero frame is static glass and taller than the scroll-autoplay bookends,
// so its loop cannot use scroll-owned playback. It plays muted at once unless
// the visitor prefers reduced motion; then the poster stays until the visitor
// asks to play. The visitor's pause always wins.

const reducedMotionQuery = "(prefers-reduced-motion: reduce)";

export interface HeroLoopController {
  readonly destroy: () => void;
}

interface HeroLoopElements {
  readonly toggle: HTMLButtonElement;
  readonly video: HTMLVideoElement;
}

function resolveHeroLoopElements(root: HTMLElement): HeroLoopElements {
  const video = root.querySelector<HTMLVideoElement>("[data-hero-loop-video]");
  const toggle = root.querySelector<HTMLButtonElement>("[data-hero-loop-toggle]");
  if (video === null || toggle === null) {
    throw new Error("Hero loop markup is incomplete.");
  }
  return { toggle, video };
}

export function initializeHeroLoop(root: HTMLElement): HeroLoopController {
  const { toggle, video } = resolveHeroLoopElements(root);
  const motionPreference = window.matchMedia(reducedMotionQuery);
  const lifecycle = new AbortController();
  const listenerOptions = { signal: lifecycle.signal };
  let pausedByVisitor = false;

  const renderPlaybackState = (): void => {
    const playing = !video.paused;
    toggle.dataset["playbackState"] = playing ? "playing" : "paused";
    const label = playing ? toggle.dataset["pauseLabel"] : toggle.dataset["playLabel"];
    if (label !== undefined) {
      toggle.setAttribute("aria-label", label);
    }
  };

  // A refused play (autoplay policy, decode failure) leaves the poster showing.
  const requestPlay = (): void => {
    void video.play().catch(renderPlaybackState);
  };

  const playWhenAllowed = (): void => {
    if (video.paused && !pausedByVisitor && !motionPreference.matches) {
      requestPlay();
    }
  };

  toggle.addEventListener(
    "click",
    (): void => {
      if (video.paused) {
        pausedByVisitor = false;
        requestPlay();
        return;
      }
      pausedByVisitor = true;
      video.pause();
    },
    listenerOptions,
  );
  video.addEventListener("play", renderPlaybackState, listenerOptions);
  video.addEventListener("pause", renderPlaybackState, listenerOptions);
  video.addEventListener(
    "error",
    (): void => {
      toggle.hidden = true;
    },
    listenerOptions,
  );
  motionPreference.addEventListener(
    "change",
    (): void => {
      if (motionPreference.matches) {
        video.pause();
      } else {
        playWhenAllowed();
      }
    },
    listenerOptions,
  );

  toggle.hidden = false;
  renderPlaybackState();
  playWhenAllowed();

  return {
    destroy: (): void => {
      lifecycle.abort();
      toggle.hidden = true;
    },
  };
}
