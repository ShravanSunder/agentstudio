import { describe, expect, it } from "vitest";

import * as chapterDomContract from "../src/chapters/chapter-dom-contract";

describe("chapter DOM contract", () => {
  it("names distinct data attributes that every lane can select", () => {
    // Arrange
    const attributeNames = Object.values(chapterDomContract);

    // Act / Assert (module namespaces enumerate exports alphabetically)
    expect(new Set(attributeNames)).toEqual(
      new Set([
        "data-rail-anchor",
        "data-rail-surface-target",
        "data-rail-media-target",
        "data-rail-current",
        "data-scroll-playback-stage",
        "data-scene-root",
        "data-scene-step",
        "data-scene-proof",
        "data-scene-proof-state",
        "data-scene-proof-transition",
      ]),
    );
    expect(new Set(attributeNames).size).toBe(attributeNames.length);
    for (const attributeName of attributeNames) {
      expect(attributeName).toMatch(/^data-[a-z]+(-[a-z]+)*$/);
    }
  });
});
