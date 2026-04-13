import { describe, it, expect, beforeEach } from "vitest";
import { createStore } from "zustand/vanilla";
import {
  processPush,
  resetBridgeReceiver,
  type PushEnvelope,
  type StoreEntry,
} from "../src/bridge-receiver.js";

// Import shared contract fixtures via Vite's JSON import (browser-safe).
import pushReplace from "../../BridgeContractFixtures/valid/push-envelope-replace.json";
import pushMerge from "../../BridgeContractFixtures/valid/push-envelope-merge.json";
import rpcNotification from "../../BridgeContractFixtures/valid/rpc-command-notification.json";
import rpcWithId from "../../BridgeContractFixtures/valid/rpc-command-with-id.json";
import staleRevision from "../../BridgeContractFixtures/edge/push-stale-revision.json";
import epochMismatch from "../../BridgeContractFixtures/edge/push-epoch-mismatch.json";
import missingRevision from "../../BridgeContractFixtures/invalid/push-missing-revision.json";

function makeTestStore(
  initial: Record<string, unknown> = {},
): StoreEntry {
  return {
    store: createStore<Record<string, unknown>>(() => ({ ...initial })),
    reset: () => {},
  };
}

/**
 * Extract the PushEnvelope-compatible fields from a full push fixture.
 * Fixtures use the full envelope format with __v, __pushId, store, level
 * but the receiver processes op, data, __revision, __epoch.
 */
function toPushEnvelope(
  fixture: Record<string, unknown>,
): PushEnvelope {
  return {
    op: fixture.op as "merge" | "replace",
    data: fixture.data,
    __revision: fixture.__revision as number,
    __epoch: fixture.__epoch as number,
  };
}

describe("contract fixtures", () => {
  beforeEach(() => {
    resetBridgeReceiver();
  });

  describe("valid fixtures", () => {
    it("push-envelope-replace.json parses and applies correctly", () => {
      const fixture = pushReplace as Record<string, unknown>;

      expect(fixture.__v).toBe(1);
      expect(fixture.op).toBe("replace");
      expect(fixture.store).toBe("diff");
      expect(fixture.__revision).toBe(1);
      expect(fixture.__epoch).toBe(1);

      const entry = makeTestStore();
      const stores = { [fixture.store as string]: entry };

      const accepted = processPush(toPushEnvelope(fixture), stores);
      expect(accepted).toBe(true);

      const state = entry.store.getState();
      expect(state.status).toBe("idle");
      expect(state.error).toBeNull();
    });

    it("push-envelope-merge.json parses and applies correctly", () => {
      const fixture = pushMerge as Record<string, unknown>;

      expect(fixture.op).toBe("merge");
      expect(fixture.store).toBe("diff");
      expect(fixture.__revision).toBe(2);

      const entry = makeTestStore({ status: "idle", extra: "keep" });
      const stores = { [fixture.store as string]: entry };

      const accepted = processPush(toPushEnvelope(fixture), stores);
      expect(accepted).toBe(true);

      const state = entry.store.getState();
      expect(state.status).toBe("running");
      expect(state.extra).toBe("keep");
    });

    it("rpc-command-notification.json has correct shape", () => {
      const fixture = rpcNotification as Record<string, unknown>;

      expect(fixture.jsonrpc).toBe("2.0");
      expect(fixture.method).toBe("diff.requestFileContents");
      expect(fixture.params).toEqual({ fileId: "abc123" });
      expect(fixture.__commandId).toEqual(expect.any(String));
      // Notifications have no id field
      expect(fixture.id).toBeUndefined();
    });

    it("rpc-command-with-id.json has correct shape", () => {
      const fixture = rpcWithId as Record<string, unknown>;

      expect(fixture.jsonrpc).toBe("2.0");
      expect(fixture.method).toEqual(expect.any(String));
      // Requests have an id field
      expect(fixture.id).toBeDefined();
    });
  });

  describe("edge case fixtures", () => {
    it("push-stale-revision.json — dropped after higher revision seen", () => {
      const entry = makeTestStore({ status: "ready" });
      const stores = { diff: entry };

      // First: accept revision 5
      processPush(
        {
          op: "replace",
          data: { status: "ready" },
          __revision: 5,
          __epoch: 1,
        },
        stores,
      );

      // Then: the stale fixture (revision 1) should be dropped
      const fixture = staleRevision as Record<string, unknown>;
      const accepted = processPush(toPushEnvelope(fixture), stores);
      expect(accepted).toBe(false);
      expect(entry.store.getState().status).toBe("ready");
    });

    it("push-epoch-mismatch.json — triggers store reset on epoch advance", () => {
      const initialState = { status: "old-data" };
      let wasReset = false;
      const entry: StoreEntry = {
        store: createStore<Record<string, unknown>>(() => ({
          ...initialState,
        })),
        reset: () => {
          wasReset = true;
          entry.store.setState(initialState, true);
        },
      };
      const stores = { diff: entry };

      // Establish epoch 1
      processPush(
        {
          op: "replace",
          data: { status: "old-data" },
          __revision: 1,
          __epoch: 1,
        },
        stores,
      );

      // Epoch mismatch fixture (epoch 2) should trigger reset
      const fixture = epochMismatch as Record<string, unknown>;
      const accepted = processPush(toPushEnvelope(fixture), stores);
      expect(accepted).toBe(true);
      expect(wasReset).toBe(true);
    });
  });

  describe("invalid fixtures", () => {
    it("push-missing-revision.json — has no __revision field", () => {
      const fixture = missingRevision as Record<string, unknown>;

      // The fixture should lack __revision
      expect(fixture.__revision).toBeUndefined();

      // When processed, revision will be undefined/NaN — guard should reject
      const entry = makeTestStore();
      const stores = { diff: entry };
      const envelope = toPushEnvelope(fixture);

      // undefined revision becomes NaN, which fails the > comparison
      const accepted = processPush(envelope, stores);
      // NaN <= 0 is false in JS, so shouldAcceptRevision sees NaN > 0 = false
      // This validates that missing revision is handled gracefully
      expect(accepted).toBe(false);
    });
  });
});
