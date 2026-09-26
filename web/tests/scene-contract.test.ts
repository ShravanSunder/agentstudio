import { describe, expect, expectTypeOf, it } from "vitest";

import {
  createSeededRandom,
  isSceneId,
  sceneIds,
  type SceneTimeline,
} from "../src/motion-scenes/scene-contract";

function drawSequence(seed: number, length: number): readonly number[] {
  const random = createSeededRandom(seed);
  return Array.from({ length }, () => random());
}

describe("scene contract", () => {
  it("replays the same sequence for the same seed", () => {
    // Arrange / Act
    const firstRun = drawSequence(20_260_923, 64);
    const secondRun = drawSequence(20_260_923, 64);

    // Assert
    expect(secondRun).toEqual(firstRun);
  });

  it("matches the published mulberry32 reference so every host renders the same frame", () => {
    // Arrange / Act
    const sequence = drawSequence(1, 3);

    // Assert
    expect(sequence).toEqual([0.6270739405881613, 0.002735721180215478, 0.5274470399599522]);
  });

  it("diverges across seeds and stays within [0, 1)", () => {
    // Arrange / Act
    const seedOne = drawSequence(1, 256);
    const seedTwo = drawSequence(2, 256);

    // Assert
    expect(seedTwo).not.toEqual(seedOne);
    for (const value of [...seedOne, ...seedTwo]) {
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThan(1);
    }
  });

  it("hands scenes GSAP's own timeline type", () => {
    // Compile-time assertion, checked by `astro check` over tests/.
    expectTypeOf<SceneTimeline>().toEqualTypeOf<gsap.core.Timeline>();
  });

  it("accepts only the closed scene id set", () => {
    // Arrange / Act / Assert
    expect(sceneIds.every((sceneId) => isSceneId(sceneId))).toBe(true);
    expect(isSceneId("chapter-not-found")).toBe(false);
  });
});
