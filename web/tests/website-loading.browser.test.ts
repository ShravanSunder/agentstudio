import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type {
  DeferredVideoObservation,
  HeroProofImageObservation,
} from "./website-loading-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyDeferredProofVideo(pageUrl: string): Promise<DeferredVideoObservation>;
    verifyHeroProofImage(
      pageUrl: string,
      width: number,
      height: number,
    ): Promise<HeroProofImageObservation>;
  }
}

it("admits the proof video near view and holds its poster until real canplay", async () => {
  const observation = await commands.verifyDeferredProofVideo(inject("siteHeaderBrowserTestUrl"));
  expect(observation.initialRequests).toBe(0);
  expect(observation.initialBytes).toBe(0);
  expect(observation.initialPreload).toBe("none");
  expect(observation.initialSource).toBeNull();
  expect(observation.requestedNearViewport).toBe(true);
  expect(observation.posterWhileLoading).toBe(true);
  expect(observation.playedAfterReady).toBe(true);
});

it.each([
  [1600, 1000],
  [390, 844],
])("decodes a non-prioritized hero proof before first scroll at %ix%i", async (width, height) => {
  const observation = await commands.verifyHeroProofImage(
    inject("siteHeaderBrowserTestUrl"),
    width,
    height,
  );
  expect(observation.loading).not.toBe("eager");
  expect(observation.fetchPriority).not.toBe("high");
  expect(observation.completeAtIntroEnd).toBe(true);
  expect(observation.decodedBeforeScroll).toBe(true);
});
