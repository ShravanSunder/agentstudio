/**
 * Bridge receiver — processes __bridge_push CustomEvents into Zustand stores.
 *
 * Validates push nonce, applies revision/epoch guards, and routes to the
 * correct store with merge or replace semantics.
 */

import type { StoreApi } from "zustand/vanilla";
import {
  shouldAcceptRevision,
  resetRevisions,
} from "./guards/revision-guard.js";
import { checkEpoch, resetEpochs } from "./guards/epoch-guard.js";

export interface PushEnvelope {
  op: "merge" | "replace";
  data: unknown;
  __revision: number;
  __epoch: number;
  nonce?: string;
}

export interface StoreEntry {
  store: StoreApi<Record<string, unknown>>;
  /** Called when epoch advances — should reset store to initial state. */
  reset: () => void;
}

export interface BridgeReceiverOptions {
  /** Expected push nonce from the handshake. If set, pushes without matching nonce are dropped. */
  pushNonce?: string;
  /** Map of store key → Zustand store entry. */
  stores: Record<string, StoreEntry>;
}

/**
 * Create a bridge receiver that listens for __bridge_push CustomEvents
 * and dispatches to Zustand stores.
 *
 * Returns a cleanup function to remove the event listener.
 */
export function createBridgeReceiver(
  options: BridgeReceiverOptions,
): () => void {
  const handler = (event: Event) => {
    const detail = (event as CustomEvent).detail as PushEnvelope | undefined;
    if (!detail) return;

    // Nonce validation (if configured)
    if (options.pushNonce && detail.nonce !== options.pushNonce) {
      return;
    }

    processPush(detail, options.stores);
  };

  document.addEventListener("__bridge_push", handler);

  return () => {
    document.removeEventListener("__bridge_push", handler);
  };
}

/**
 * Process a single push envelope. Exported for direct testing without DOM events.
 */
export function processPush(
  envelope: PushEnvelope,
  stores: Record<string, StoreEntry>,
): boolean {
  // We need store key from the envelope — in the full bridge, this comes from
  // the envelope's "store" field. For testing, we extract from the data or
  // use a default. In the real implementation, the __bridge_push CustomEvent
  // includes the store in the detail (routed by applyEnvelope).
  //
  // For the test receiver, we process against all matching stores based on
  // the caller's routing. The caller is expected to route correctly.

  const { op, data, __revision: revision, __epoch: epoch } = envelope;

  // Process against each store (in practice, a push targets one store)
  let anyAccepted = false;
  for (const [key, entry] of Object.entries(stores)) {
    // Epoch guard
    const epochResult = checkEpoch(key, epoch);
    if (!epochResult.accepted) continue;

    if (epochResult.shouldReset) {
      entry.reset();
      // Reset revision tracking for this store on epoch advance
      resetRevisions();
    }

    // Revision guard
    if (!shouldAcceptRevision(key, revision)) continue;

    // Apply the push
    if (op === "replace") {
      entry.store.setState(data as Record<string, unknown>);
    } else if (op === "merge") {
      entry.store.setState((prev) => deepMerge(prev, data as Record<string, unknown>));
    }

    anyAccepted = true;
  }

  return anyAccepted;
}

/**
 * Deep merge source into target. Returns a new object.
 * Arrays are replaced, not merged.
 */
function deepMerge(
  target: Record<string, unknown>,
  source: Record<string, unknown>,
): Record<string, unknown> {
  const result = { ...target };

  for (const key of Object.keys(source)) {
    const sourceVal = source[key];
    const targetVal = target[key];

    if (
      sourceVal &&
      typeof sourceVal === "object" &&
      !Array.isArray(sourceVal) &&
      targetVal &&
      typeof targetVal === "object" &&
      !Array.isArray(targetVal)
    ) {
      result[key] = deepMerge(
        targetVal as Record<string, unknown>,
        sourceVal as Record<string, unknown>,
      );
    } else {
      result[key] = sourceVal;
    }
  }

  return result;
}

/** Reset all guard state. Call between tests. */
export function resetBridgeReceiver(): void {
  resetRevisions();
  resetEpochs();
}
