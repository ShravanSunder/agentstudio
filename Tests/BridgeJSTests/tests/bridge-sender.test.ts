import { describe, it, expect, beforeEach } from "vitest";
import { sendCommand, resetSender } from "../src/bridge-sender.js";

describe("bridge-sender", () => {
  beforeEach(() => {
    resetSender();
  });

  it("dispatches __bridge_command CustomEvent", () => {
    let captured: Record<string, unknown> | null = null;
    const listener = (e: Event) => {
      captured = (e as CustomEvent).detail as Record<string, unknown>;
    };
    document.addEventListener("__bridge_command", listener);

    sendCommand("test-nonce", {
      method: "diff.requestFileContents",
      params: { fileId: "abc123" },
    });

    document.removeEventListener("__bridge_command", listener);

    expect(captured).not.toBeNull();
    expect(captured!.jsonrpc).toBe("2.0");
    expect(captured!.method).toBe("diff.requestFileContents");
    expect(captured!.__nonce).toBe("test-nonce");
    expect(captured!.__commandId).toEqual(expect.any(String));
    expect(captured!.params).toEqual({ fileId: "abc123" });
  });

  it("includes custom commandId when provided", () => {
    let captured: Record<string, unknown> | null = null;
    const listener = (e: Event) => {
      captured = (e as CustomEvent).detail as Record<string, unknown>;
    };
    document.addEventListener("__bridge_command", listener);

    const returnedId = sendCommand("nonce", {
      method: "test.echo",
      commandId: "my-cmd-id",
    });

    document.removeEventListener("__bridge_command", listener);

    expect(captured!.__commandId).toBe("my-cmd-id");
    expect(returnedId).toBe("my-cmd-id");
  });

  it("includes request id when provided", () => {
    let captured: Record<string, unknown> | null = null;
    const listener = (e: Event) => {
      captured = (e as CustomEvent).detail as Record<string, unknown>;
    };
    document.addEventListener("__bridge_command", listener);

    sendCommand("nonce", {
      method: "test.add",
      params: { a: 1, b: 2 },
      id: 42,
    });

    document.removeEventListener("__bridge_command", listener);

    expect(captured!.id).toBe(42);
  });

  it("auto-generates unique commandIds", () => {
    const ids: string[] = [];
    const listener = (e: Event) => {
      const detail = (e as CustomEvent).detail as Record<string, unknown>;
      ids.push(detail.__commandId as string);
    };
    document.addEventListener("__bridge_command", listener);

    sendCommand("nonce", { method: "a" });
    sendCommand("nonce", { method: "b" });
    sendCommand("nonce", { method: "c" });

    document.removeEventListener("__bridge_command", listener);

    expect(ids.length).toBe(3);
    expect(new Set(ids).size).toBe(3);
  });

  it("defaults params to empty object", () => {
    let captured: Record<string, unknown> | null = null;
    const listener = (e: Event) => {
      captured = (e as CustomEvent).detail as Record<string, unknown>;
    };
    document.addEventListener("__bridge_command", listener);

    sendCommand("nonce", { method: "test.noparams" });

    document.removeEventListener("__bridge_command", listener);

    expect(captured!.params).toEqual({});
  });
});
