import { describe, expect, it } from "vitest";

import {
  assignWorktreeColumns,
  measureFullPageTopologyGrid,
  resolveTopologyGlassBand,
} from "../src/topology-lab/full-page-topology-model";

describe("hardcoded worktree lane allocation", () => {
  it("uses the nearest free column when every worktree forks from main", () => {
    expect(
      assignWorktreeColumns(
        [
          { endKind: "open", endSlot: 18, forkSlot: 2, id: "a" },
          { endKind: "merge", endSlot: 10, forkSlot: 4, id: "b" },
          { endKind: "merge", endSlot: 20, forkSlot: 8, id: "c" },
          { endKind: "open", endSlot: 16, forkSlot: 14, id: "d" },
          { endKind: "open", endSlot: 17, forkSlot: 11, id: "e" },
        ],
        6,
      ),
    ).toEqual([
      { id: "a", lane: 1 },
      { id: "b", lane: 2 },
      { id: "c", lane: 3 },
      { id: "e", lane: 2 },
      { id: "d", lane: 4 },
    ]);
  });

  it("reuses a nearer released column instead of skipping it", () => {
    expect(
      assignWorktreeColumns(
        [
          { endKind: "merge", endSlot: 6, forkSlot: 2, id: "a" },
          { endKind: "merge", endSlot: 10, forkSlot: 4, id: "b" },
          { endKind: "open", endSlot: 12, forkSlot: 7, id: "c" },
        ],
        4,
      ),
    ).toEqual([
      { id: "a", lane: 1 },
      { id: "b", lane: 2 },
      { id: "c", lane: 1 },
    ]);
  });

  it("sorts allocation by fork chronology instead of source order", () => {
    expect(
      assignWorktreeColumns(
        [
          { endKind: "open", endSlot: 20, forkSlot: 10, id: "late" },
          { endKind: "merge", endSlot: 5, forkSlot: 2, id: "early" },
        ],
        3,
      ),
    ).toEqual([
      { id: "early", lane: 1 },
      { id: "late", lane: 1 },
    ]);
  });

  it("does not release a lane when the illustrated worktree remains open", () => {
    expect(
      assignWorktreeColumns(
        [
          { endKind: "open", endSlot: 6, forkSlot: 2, id: "open" },
          { endKind: "merge", endSlot: 10, forkSlot: 7, id: "later" },
        ],
        3,
      ),
    ).toEqual([
      { id: "open", lane: 1 },
      { id: "later", lane: 2 },
    ]);
  });

  it("rejects two forks competing for the same physical row", () => {
    expect(
      assignWorktreeColumns(
        [
          { endKind: "open", endSlot: 12, forkSlot: 2, id: "a" },
          { endKind: "merge", endSlot: 10, forkSlot: 2, id: "b" },
        ],
        3,
      ),
    ).toBeUndefined();
  });
});

describe("full-page topology grid measurement", () => {
  it("reserves the outer column and requires two usable columns in both gutters", () => {
    expect(
      measureFullPageTopologyGrid({
        frameLeft: 287,
        frameRight: 1713,
        height: 5200,
        width: 2000,
      }),
    ).toBeUndefined();

    expect(
      measureFullPageTopologyGrid({
        frameLeft: 288,
        frameRight: 1712,
        height: 5200,
        width: 2000,
      }),
    ).toMatchObject({
      usableColumnCount: 2,
      variant: "compact",
    });
  });

  it("selects hardcoded variants from gutter column capacity", () => {
    const compactGrid = measureFullPageTopologyGrid({
      frameLeft: 288,
      frameRight: 1712,
      height: 5200,
      width: 2000,
    });
    expect(compactGrid?.leftLaneXs).toEqual([144, 240]);
    expect(compactGrid?.rightLaneXs).toEqual([1856, 1760]);
    expect(compactGrid?.variant).toBe("compact");

    expect(
      measureFullPageTopologyGrid({
        frameLeft: 384,
        frameRight: 1616,
        height: 5200,
        width: 2000,
      })?.variant,
    ).toBe("standard");

    expect(
      measureFullPageTopologyGrid({
        frameLeft: 480,
        frameRight: 1520,
        height: 5200,
        width: 2000,
      })?.variant,
    ).toBe("expanded");
  });

  it("projects the first and last glass surfaces onto authored grid rows", () => {
    const grid = measureFullPageTopologyGrid({
      frameLeft: 576,
      frameRight: 1424,
      height: 5200,
      requestedTopPadding: 96,
      width: 2000,
    });
    if (grid === undefined) {
      throw new Error("Expected an eligible topology grid");
    }

    expect(
      resolveTopologyGlassBand({
        glassSurfaces: [
          { bottom: 672, top: 480 },
          { bottom: 1920, top: 1728 },
          { bottom: 2688, top: 2496 },
          { bottom: 2784, top: 2592 },
        ],
        grid,
      }),
    ).toEqual({ firstCrossRow: 5, lastCrossRow: 27, slotCount: 20 });
  });

  it("rejects glass geometry that cannot hold the authored 20-slot composition", () => {
    const grid = measureFullPageTopologyGrid({
      frameLeft: 576,
      frameRight: 1424,
      height: 5200,
      requestedTopPadding: 96,
      width: 2000,
    });
    if (grid === undefined) {
      throw new Error("Expected an eligible topology grid");
    }

    expect(
      resolveTopologyGlassBand({
        glassSurfaces: [
          { bottom: 672, top: 480 },
          { bottom: 2496, top: 2304 },
        ],
        grid,
      }),
    ).toBeUndefined();
  });
});
