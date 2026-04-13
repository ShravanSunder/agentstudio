/**
 * Epoch guard for store state transitions.
 *
 * When epoch advances (new diff source loaded), the store must reset
 * and revision tracking must restart. Pushes from older epochs are dropped.
 */

const lastEpochs = new Map<string, number>();

export interface EpochCheckResult {
  /** Whether this push should be processed. */
  accepted: boolean;
  /** Whether the store should be reset before applying the push (epoch advanced). */
  shouldReset: boolean;
}

/**
 * Check whether a push with the given epoch should be accepted.
 * Returns whether to accept and whether the store needs resetting.
 */
export function checkEpoch(store: string, epoch: number): EpochCheckResult {
  const lastEpoch = lastEpochs.get(store) ?? -1;

  if (epoch < lastEpoch) {
    // Stale epoch — drop
    return { accepted: false, shouldReset: false };
  }

  if (epoch > lastEpoch) {
    // Epoch advanced — accept and signal reset
    lastEpochs.set(store, epoch);
    return { accepted: true, shouldReset: true };
  }

  // Same epoch — accept without reset
  return { accepted: true, shouldReset: false };
}

/** Get the last accepted epoch for a store. */
export function getLastEpoch(store: string): number {
  return lastEpochs.get(store) ?? -1;
}

/** Reset all tracked epochs. Used between tests. */
export function resetEpochs(): void {
  lastEpochs.clear();
}
