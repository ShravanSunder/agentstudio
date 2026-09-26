import { gsap } from "gsap";

import { heroIntroFourthPlaneAttribute, heroIntroStateAttribute } from "./hero-intro-dom-contract";
import { collectHeroIntroTargets, buildHeroIntroScene } from "./hero-intro-scene";

export interface HeroIntroPlayback {
  readonly timeline: ReturnType<typeof gsap.timeline> | null;
  readonly state: "playing" | "settled";
  finish(): void;
}

export function initializeHeroIntroPlayback(root: HTMLElement): HeroIntroPlayback {
  let settled = false;
  let timeline: ReturnType<typeof gsap.timeline> | null = null;

  function removeFinishListeners(): void {
    for (const eventName of ["wheel", "touchstart", "keydown", "scroll", "resize"]) {
      window.removeEventListener(eventName, finish);
    }
  }

  function finish(): void {
    if (settled) {
      return;
    }
    settled = true;
    if (timeline !== null && timeline.progress() < 1) {
      timeline.progress(1);
    }
    removeFinishListeners();
    const targets = collectHeroIntroTargets(root);
    const clearTween = gsap.set(targets, { clearProps: "all" });
    clearTween.kill();
    timeline?.kill();
    for (const target of targets) {
      target.removeAttribute("style");
    }
    for (const target of targets.filter((target) => target.hasAttribute("style"))) {
      target.removeAttribute("style");
    }
    root.querySelector(`[${heroIntroFourthPlaneAttribute}]`)?.remove();
    root.querySelector<HTMLElement>("[data-hero-intro-typed-input]")?.replaceChildren();
    root.setAttribute(heroIntroStateAttribute, "settled");
    root.setAttribute("data-hero-intro-progress", "1");
    root.dispatchEvent(new CustomEvent("hero-intro-settled", { bubbles: true }));
  }

  if (document.hidden || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    finish();
    return {
      timeline: null,
      get state() {
        return "settled" as const;
      },
      finish,
    };
  }

  timeline = gsap.timeline({
    paused: true,
    onComplete: finish,
    onUpdate: () => {
      root.setAttribute("data-hero-intro-progress", String(timeline?.progress() ?? 0));
    },
  });
  root.setAttribute("data-hero-intro-timeline-created", "");
  buildHeroIntroScene(root, timeline, {
    width: window.innerWidth,
    height: window.innerHeight,
    seed: 0,
  });
  root.setAttribute(heroIntroStateAttribute, "playing");
  for (const eventName of ["wheel", "touchstart", "keydown", "scroll", "resize"]) {
    window.addEventListener(eventName, finish, { passive: true });
  }
  timeline.play();
  return {
    timeline,
    get state() {
      return settled ? ("settled" as const) : ("playing" as const);
    },
    finish,
  };
}
