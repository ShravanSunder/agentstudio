import { describe, expect, it } from "vitest";

import {
  initialPersistenceProofState,
  reducePersistenceProofState,
} from "../src/product-plate/persistence-proof-state";

describe("persistence proof state", () => {
  it("shows the before frame first", () => {
    expect(initialPersistenceProofState).toEqual({ kind: "showing", frame: "before" });
  });

  it("switches between the matched before and restored frames", () => {
    const restoredState = reducePersistenceProofState(initialPersistenceProofState, {
      kind: "select",
      frame: "restored",
    });
    const beforeState = reducePersistenceProofState(restoredState, {
      kind: "select",
      frame: "before",
    });

    expect(restoredState).toEqual({ kind: "showing", frame: "restored" });
    expect(beforeState).toEqual({ kind: "showing", frame: "before" });
  });

  it("returns to the before frame when reset", () => {
    const restoredState = reducePersistenceProofState(initialPersistenceProofState, {
      kind: "select",
      frame: "restored",
    });

    expect(reducePersistenceProofState(restoredState, { kind: "reset" })).toBe(
      initialPersistenceProofState,
    );
  });
});
