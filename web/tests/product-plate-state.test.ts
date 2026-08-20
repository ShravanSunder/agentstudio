import { describe, expect, it } from "vitest";

import {
  initialProductPlateState,
  parseProductPlateStoryId,
  reduceProductPlateState,
} from "../src/product-plate/product-plate-state";

describe("product plate state", () => {
  it("keeps selection inert until activation", () => {
    expect(
      reduceProductPlateState(initialProductPlateState, {
        kind: "select",
        storyId: "review",
      }),
    ).toEqual(initialProductPlateState);
  });

  it("selects a valid story after activation", () => {
    const activeState = reduceProductPlateState(initialProductPlateState, { kind: "activate" });

    expect(
      reduceProductPlateState(activeState, { kind: "select", storyId: "pane-drawer" }),
    ).toEqual({ kind: "active", selectedStoryId: "pane-drawer" });
  });

  it("wraps keyboard selection across the closed story set", () => {
    const activeState = reduceProductPlateState(initialProductPlateState, { kind: "activate" });
    const previousState = reduceProductPlateState(activeState, {
      kind: "move",
      direction: "previous",
    });

    expect(previousState).toEqual({
      kind: "active",
      selectedStoryId: "persistent-workspace",
    });
    expect(reduceProductPlateState(previousState, { kind: "move", direction: "next" })).toEqual({
      kind: "active",
      selectedStoryId: "parallel-work",
    });
  });

  it("supports Home and End semantics", () => {
    const selectedReviewState = {
      kind: "active" as const,
      selectedStoryId: "review" as const,
    };

    expect(
      reduceProductPlateState(selectedReviewState, { kind: "move", direction: "first" }),
    ).toEqual({ kind: "active", selectedStoryId: "parallel-work" });
    expect(
      reduceProductPlateState(selectedReviewState, { kind: "move", direction: "last" }),
    ).toEqual({ kind: "active", selectedStoryId: "persistent-workspace" });
  });

  it("rolls back to an honest static state", () => {
    expect(
      reduceProductPlateState(
        { kind: "active", selectedStoryId: "quick-find" },
        { kind: "rollback" },
      ),
    ).toEqual(initialProductPlateState);
  });

  it("rejects identifiers outside the closed story set", () => {
    expect(parseProductPlateStoryId("review")).toBe("review");
    expect(parseProductPlateStoryId("invented-state")).toBeNull();
  });
});
