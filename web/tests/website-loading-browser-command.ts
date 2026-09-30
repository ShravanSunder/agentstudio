import { defineBrowserCommand } from "@vitest/browser-playwright";

import type { ScenePlaybackControl } from "../src/home-page/scene-playback.ts";

interface LoadingProofWindow extends Window {
  loadingProofControl?: ScenePlaybackControl;
}

export interface HeroProofImageObservation {
  readonly loading: string;
  readonly fetchPriority: string;
  readonly completeAtIntroEnd: boolean;
  readonly decodedBeforeScroll: boolean;
}

export const verifyHeroProofImage = defineBrowserCommand(
  async (
    { context },
    pageUrl: string,
    width: number,
    height: number,
  ): Promise<HeroProofImageObservation> => {
    const page = await context.newPage();
    try {
      await page.setViewportSize({ width, height });
      await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
      await page.waitForSelector('[data-hero-intro-state="settled"]');
      return await page.evaluate(async (): Promise<HeroProofImageObservation> => {
        const image = document.querySelector<HTMLImageElement>("[data-hero-app-frame] picture img");
        if (image === null) throw new Error("Hero proof image missing");
        const completeAtIntroEnd = image.complete && image.naturalWidth > 0;
        await image.decode();
        return {
          loading: image.loading,
          fetchPriority: image.fetchPriority,
          completeAtIntroEnd,
          decodedBeforeScroll: scrollY === 0 && image.naturalWidth > 0,
        };
      });
    } finally {
      await page.close();
    }
  },
);

export interface DeferredVideoObservation {
  readonly initialRequests: number;
  readonly initialBytes: number;
  readonly initialPreload: string;
  readonly initialSource: string | null;
  readonly requestedNearViewport: boolean;
  readonly posterWhileLoading: boolean;
  readonly playedAfterReady: boolean;
}

export const verifyDeferredProofVideo = defineBrowserCommand(
  async ({ context }, pageUrl: string): Promise<DeferredVideoObservation> => {
    const page = await context.newPage();
    let releaseVideo: (() => void) | undefined;
    const videoAdmission = new Promise<void>((resolve): void => {
      releaseVideo = resolve;
    });
    let videoRequests = 0;
    try {
      await page.setViewportSize({ width: 1600, height: 1000 });
      await page.addInitScript((): void => {
        const isPlaybackControl = (value: unknown): value is ScenePlaybackControl =>
          typeof value === "object" &&
          value !== null &&
          "duration" in value &&
          typeof value.duration === "number" &&
          "finish" in value &&
          typeof value.finish === "function" &&
          "seek" in value &&
          typeof value.seek === "function" &&
          "pause" in value &&
          typeof value.pause === "function";
        document.addEventListener("scene-playback-ready", (event): void => {
          if (
            event instanceof CustomEvent &&
            event.target instanceof HTMLElement &&
            event.target.closest("#come-back") !== null
          ) {
            if (isPlaybackControl(event.detail))
              (window as LoadingProofWindow).loadingProofControl = event.detail;
          }
        });
      });
      await page.route("**/*session-restore*.mp4*", async (route): Promise<void> => {
        videoRequests += 1;
        await videoAdmission;
        await route.continue();
      });
      await page.goto(pageUrl, { waitUntil: "domcontentloaded" });
      // The intro's closing fact bounds the initial no-scroll observation.
      await page.waitForSelector('[data-hero-intro-state="settled"]');
      const initial = await page.evaluate(() => {
        const video = document.querySelector<HTMLVideoElement>("[data-scene-proof-video]");
        if (video === null) throw new Error("Proof video missing");
        return {
          initialPreload: video.preload,
          initialSource:
            video.querySelector("source")?.getAttribute("src") ?? video.getAttribute("src"),
          initialBytes: performance
            .getEntriesByType("resource")
            .filter((entry) => /session-restore.*\.mp4/u.test(entry.name))
            .reduce(
              (bytes, entry) =>
                bytes + (entry instanceof PerformanceResourceTiming ? entry.transferSize : 0),
              0,
            ),
        };
      });
      const initialRequests = videoRequests;
      if (initialRequests > 0)
        return {
          ...initial,
          initialRequests,
          requestedNearViewport: false,
          posterWhileLoading: false,
          playedAfterReady: false,
        };

      const nearRequest = page.waitForRequest("**/*session-restore*.mp4*");
      await page.evaluate((): void => {
        const stage = document.querySelector("#come-back .chapter-scene-stage");
        if (stage === null) throw new Error("Come-back stage missing");
        window.scrollTo({
          top: scrollY + stage.getBoundingClientRect().top - innerHeight * 1.5,
          behavior: "instant",
        });
      });
      await nearRequest;
      await page.evaluate((): void => {
        const stage = document.querySelector("#come-back .chapter-scene-stage");
        if (stage === null) throw new Error("Come-back stage missing");
        window.scrollTo({
          top:
            scrollY +
            stage.getBoundingClientRect().top -
            (innerHeight - stage.getBoundingClientRect().height) / 2,
          behavior: "instant",
        });
      });
      await page.waitForFunction(
        () => (window as LoadingProofWindow).loadingProofControl !== undefined,
      );
      const posterWhileLoading = await page.evaluate((): boolean => {
        (window as LoadingProofWindow).loadingProofControl?.finish();
        const video = document.querySelector<HTMLVideoElement>("[data-scene-proof-video]");
        const proof = video?.closest<HTMLElement>("[data-scene-proof]");
        return (
          video !== null &&
          video !== undefined &&
          video.paused &&
          video.readyState < 3 &&
          video.poster.length > 0 &&
          video.error === null &&
          proof?.dataset["sceneProofState"] === "shown"
        );
      });
      releaseVideo?.();
      await page.waitForFunction(() => {
        const video = document.querySelector<HTMLVideoElement>("[data-scene-proof-video]");
        return video !== null && video.readyState >= 3 && !video.paused;
      });
      return {
        ...initial,
        initialRequests,
        requestedNearViewport: true,
        posterWhileLoading,
        playedAfterReady: true,
      };
    } finally {
      releaseVideo?.();
      await page.close();
    }
  },
);
