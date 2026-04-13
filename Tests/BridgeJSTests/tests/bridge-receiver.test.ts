import { describe, it, expect, beforeEach } from "vitest";
import { createStore } from "zustand/vanilla";
import {
  processPush,
  resetBridgeReceiver,
  createBridgeReceiver,
  type PushEnvelope,
  type StoreEntry,
} from "../src/bridge-receiver.js";

function makeTestStore(initial: Record<string, unknown> = {}): StoreEntry {
  return {
    store: createStore<Record<string, unknown>>(() => ({ ...initial })),
    reset: () => {},
  };
}

function makeResettableStore(
  initial: Record<string, unknown>,
): StoreEntry & { wasReset: boolean } {
  const entry = {
    store: createStore<Record<string, unknown>>(() => ({ ...initial })),
    reset: () => {
      entry.wasReset = true;
      entry.store.setState(initial, true);
    },
    wasReset: false,
  };
  return entry;
}

describe("bridge-receiver", () => {
  beforeEach(() => {
    resetBridgeReceiver();
  });

  describe("replace semantics", () => {
    it("replaces store state entirely", () => {
      const entry = makeTestStore({ status: "idle", count: 0 });
      const stores = { diff: entry };

      processPush(
        { op: "replace", data: { status: "loading", count: 5 }, __revision: 1, __epoch: 0 },
        stores,
      );

      expect(entry.store.getState()).toEqual(
        expect.objectContaining({ status: "loading", count: 5 }),
      );
    });

    it("overwrites previous state completely", () => {
      const entry = makeTestStore({ status: "idle", extra: "data" });
      const stores = { diff: entry };

      processPush(
        { op: "replace", data: { status: "ready" }, __revision: 1, __epoch: 0 },
        stores,
      );

      const state = entry.store.getState();
      expect(state.status).toBe("ready");
    });
  });

  describe("merge semantics", () => {
    it("deep merges into existing state", () => {
      const entry = makeTestStore({
        status: "idle",
        nested: { a: 1, b: 2 },
      });
      const stores = { diff: entry };

      processPush(
        {
          op: "merge",
          data: { nested: { b: 99, c: 3 } },
          __revision: 1,
          __epoch: 0,
        },
        stores,
      );

      const state = entry.store.getState();
      expect(state.status).toBe("idle");
      expect(state.nested).toEqual({ a: 1, b: 99, c: 3 });
    });

    it("replaces arrays instead of merging them", () => {
      const entry = makeTestStore({ items: [1, 2, 3] });
      const stores = { diff: entry };

      processPush(
        { op: "merge", data: { items: [4, 5] }, __revision: 1, __epoch: 0 },
        stores,
      );

      expect(entry.store.getState().items).toEqual([4, 5]);
    });
  });

  describe("revision guard integration", () => {
    it("drops push with stale revision", () => {
      const entry = makeTestStore({ status: "idle" });
      const stores = { diff: entry };

      processPush(
        { op: "replace", data: { status: "loading" }, __revision: 5, __epoch: 0 },
        stores,
      );
      processPush(
        { op: "replace", data: { status: "stale" }, __revision: 3, __epoch: 0 },
        stores,
      );

      expect(entry.store.getState().status).toBe("loading");
    });

    it("drops push with equal revision", () => {
      const entry = makeTestStore({ status: "idle" });
      const stores = { diff: entry };

      processPush(
        { op: "replace", data: { status: "loading" }, __revision: 5, __epoch: 0 },
        stores,
      );
      processPush(
        { op: "replace", data: { status: "duplicate" }, __revision: 5, __epoch: 0 },
        stores,
      );

      expect(entry.store.getState().status).toBe("loading");
    });
  });

  describe("epoch guard integration", () => {
    it("resets store on epoch advance", () => {
      const entry = makeResettableStore({ status: "idle", count: 0 });
      const stores = { diff: entry };

      processPush(
        { op: "replace", data: { status: "loading" }, __revision: 1, __epoch: 1 },
        stores,
      );
      expect(entry.store.getState().status).toBe("loading");

      // Advance epoch — should reset store and apply new state
      processPush(
        { op: "replace", data: { status: "ready" }, __revision: 1, __epoch: 2 },
        stores,
      );
      expect(entry.wasReset).toBe(true);
      expect(entry.store.getState().status).toBe("ready");
    });

    it("drops push from stale epoch", () => {
      const entry = makeTestStore({ status: "idle" });
      const stores = { diff: entry };

      processPush(
        { op: "replace", data: { status: "loading" }, __revision: 1, __epoch: 5 },
        stores,
      );
      const accepted = processPush(
        { op: "replace", data: { status: "stale" }, __revision: 2, __epoch: 3 },
        stores,
      );

      expect(accepted).toBe(false);
      expect(entry.store.getState().status).toBe("loading");
    });
  });

  describe("CustomEvent integration", () => {
    it("processes __bridge_push events from document", () => {
      const entry = makeTestStore({ health: "disconnected" });
      const stores = { connection: entry };

      const cleanup = createBridgeReceiver({
        stores,
      });

      document.dispatchEvent(
        new CustomEvent("__bridge_push", {
          detail: {
            op: "replace",
            data: { health: "connected", latencyMs: 42 },
            __revision: 1,
            __epoch: 0,
          } satisfies PushEnvelope,
        }),
      );

      expect(entry.store.getState().health).toBe("connected");
      expect(entry.store.getState().latencyMs).toBe(42);

      cleanup();
    });

    it("validates push nonce when configured", () => {
      const entry = makeTestStore({ status: "idle" });
      const stores = { diff: entry };

      const cleanup = createBridgeReceiver({
        pushNonce: "correct-nonce",
        stores,
      });

      // Wrong nonce — should be dropped
      document.dispatchEvent(
        new CustomEvent("__bridge_push", {
          detail: {
            op: "replace",
            data: { status: "bad" },
            __revision: 1,
            __epoch: 0,
            nonce: "wrong-nonce",
          },
        }),
      );
      expect(entry.store.getState().status).toBe("idle");

      // Correct nonce — should be accepted
      document.dispatchEvent(
        new CustomEvent("__bridge_push", {
          detail: {
            op: "replace",
            data: { status: "good" },
            __revision: 1,
            __epoch: 0,
            nonce: "correct-nonce",
          },
        }),
      );
      expect(entry.store.getState().status).toBe("good");

      cleanup();
    });

    it("cleans up listener on dispose", () => {
      const entry = makeTestStore({ status: "idle" });
      const stores = { diff: entry };

      const cleanup = createBridgeReceiver({ stores });
      cleanup();

      document.dispatchEvent(
        new CustomEvent("__bridge_push", {
          detail: {
            op: "replace",
            data: { status: "should-not-arrive" },
            __revision: 1,
            __epoch: 0,
          },
        }),
      );

      expect(entry.store.getState().status).toBe("idle");
    });
  });
});
