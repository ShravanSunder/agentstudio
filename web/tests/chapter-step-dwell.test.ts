import { expect, it } from "vitest";

import { computeStepDwellSeconds } from "../src/chapters/chapter-step-dwell";

it("uses scene labels and final proof/replay length without a minimum floor", () => {
  expect(
    computeStepDwellSeconds({
      labelTimes: [0, 2.7, 4.5],
      timelineDuration: 8.9,
      proofSeconds: 0,
      replayDelaySeconds: 3,
    }),
  ).toEqual([2.7, 1.8, 7.4]);
});

it("adds real proof duration to the last step only", () => {
  expect(
    computeStepDwellSeconds({
      labelTimes: [0, 1],
      timelineDuration: 4,
      proofSeconds: 5,
      replayDelaySeconds: 3,
    }),
  ).toEqual([1, 11]);
});
