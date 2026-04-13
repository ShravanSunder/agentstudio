import { describe, it, expect, beforeEach } from "vitest";
import {
  shouldAcceptRevision,
  getLastRevision,
  resetRevisions,
} from "../src/guards/revision-guard.js";

describe("revision-guard", () => {
  beforeEach(() => {
    resetRevisions();
  });

  it("accepts first revision for a store", () => {
    expect(shouldAcceptRevision("diff", 1)).toBe(true);
    expect(getLastRevision("diff")).toBe(1);
  });

  it("accepts higher revision", () => {
    shouldAcceptRevision("diff", 1);
    expect(shouldAcceptRevision("diff", 2)).toBe(true);
    expect(getLastRevision("diff")).toBe(2);
  });

  it("rejects stale revision (lower)", () => {
    shouldAcceptRevision("diff", 5);
    expect(shouldAcceptRevision("diff", 3)).toBe(false);
    expect(getLastRevision("diff")).toBe(5);
  });

  it("rejects duplicate revision (equal)", () => {
    shouldAcceptRevision("diff", 5);
    expect(shouldAcceptRevision("diff", 5)).toBe(false);
  });

  it("tracks revisions independently per store", () => {
    shouldAcceptRevision("diff", 10);
    shouldAcceptRevision("review", 3);

    expect(shouldAcceptRevision("diff", 5)).toBe(false);
    expect(shouldAcceptRevision("review", 5)).toBe(true);
    expect(getLastRevision("diff")).toBe(10);
    expect(getLastRevision("review")).toBe(5);
  });

  it("returns 0 for unknown store", () => {
    expect(getLastRevision("unknown")).toBe(0);
  });
});
