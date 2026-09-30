import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { DeferredVideoObservation } from "./website-loading-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyDeferredProofVideo(pageUrl: string): Promise<DeferredVideoObservation>;
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
