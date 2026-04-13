import { describe, it, expect, beforeEach } from "vitest";
import {
  checkEpoch,
  getLastEpoch,
  resetEpochs,
} from "../src/guards/epoch-guard.js";

describe("epoch-guard", () => {
  beforeEach(() => {
    resetEpochs();
  });

  it("accepts first epoch and signals reset", () => {
    const result = checkEpoch("diff", 0);
    expect(result.accepted).toBe(true);
    expect(result.shouldReset).toBe(true);
    expect(getLastEpoch("diff")).toBe(0);
  });

  it("accepts same epoch without reset", () => {
    checkEpoch("diff", 1);
    const result = checkEpoch("diff", 1);
    expect(result.accepted).toBe(true);
    expect(result.shouldReset).toBe(false);
  });

  it("accepts higher epoch and signals reset", () => {
    checkEpoch("diff", 1);
    const result = checkEpoch("diff", 2);
    expect(result.accepted).toBe(true);
    expect(result.shouldReset).toBe(true);
    expect(getLastEpoch("diff")).toBe(2);
  });

  it("rejects stale epoch (lower)", () => {
    checkEpoch("diff", 5);
    const result = checkEpoch("diff", 3);
    expect(result.accepted).toBe(false);
    expect(result.shouldReset).toBe(false);
    expect(getLastEpoch("diff")).toBe(5);
  });

  it("tracks epochs independently per store", () => {
    checkEpoch("diff", 10);
    checkEpoch("review", 3);

    const diffResult = checkEpoch("diff", 5);
    expect(diffResult.accepted).toBe(false);

    const reviewResult = checkEpoch("review", 5);
    expect(reviewResult.accepted).toBe(true);
    expect(reviewResult.shouldReset).toBe(true);
  });

  it("returns -1 for unknown store", () => {
    expect(getLastEpoch("unknown")).toBe(-1);
  });
});
