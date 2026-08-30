import { describe, expect, it } from "vitest";

import { reduceInstallCommandState } from "../src/install-command/install-command-state";

describe("install command state", () => {
  it("records successful copy feedback", () => {
    expect(reduceInstallCommandState({ kind: "idle" }, { kind: "copy-succeeded" })).toEqual({
      kind: "copied",
    });
  });

  it("keeps a useful manual fallback when clipboard access fails", () => {
    expect(
      reduceInstallCommandState(
        { kind: "idle" },
        { kind: "copy-failed", message: "Select and copy the command" },
      ),
    ).toEqual({ kind: "failed", message: "Select and copy the command" });
  });

  it("resets transient feedback", () => {
    expect(reduceInstallCommandState({ kind: "copied" }, { kind: "reset" })).toEqual({
      kind: "idle",
    });
  });
});
