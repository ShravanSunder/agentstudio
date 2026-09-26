import { describe, expect, it } from "vitest";

import { stagePlaybackProgressForBounds } from "../src/home-page/scroll-material-surface-controller";

describe("large stage playback visibility", () => {
  it("starts at sixty percent of the smaller stage or viewport height", () => {
    expect(
      stagePlaybackProgressForBounds({ stageTop: 0, stageHeight: 1000, viewportHeight: 800 }),
    ).toBe(0.95);
    expect(
      stagePlaybackProgressForBounds({ stageTop: 320, stageHeight: 1000, viewportHeight: 800 }),
    ).toBe(0.95);
    expect(
      stagePlaybackProgressForBounds({ stageTop: 328, stageHeight: 1000, viewportHeight: 800 }),
    ).toBeLessThan(0.95);
    expect(
      stagePlaybackProgressForBounds({ stageTop: 320, stageHeight: 400, viewportHeight: 800 }),
    ).toBe(0.95);
    expect(
      stagePlaybackProgressForBounds({ stageTop: 580, stageHeight: 400, viewportHeight: 800 }),
    ).toBeLessThan(0.95);
  });
});
