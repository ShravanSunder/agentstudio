/**
 * Revision guard for state push deduplication.
 *
 * Tracks the last-seen revision per store. Drops pushes with
 * `revision <= lastSeen[store]` (stale reorder guard).
 */

const lastRevisions = new Map<string, number>();

/**
 * Check whether a push with the given revision should be accepted.
 * Returns true if the push is fresh (newer than last seen), false if stale.
 */
export function shouldAcceptRevision(
  store: string,
  revision: number,
): boolean {
  const lastSeen = lastRevisions.get(store) ?? 0;
  if (revision <= lastSeen) {
    return false;
  }
  lastRevisions.set(store, revision);
  return true;
}

/** Get the last accepted revision for a store. */
export function getLastRevision(store: string): number {
  return lastRevisions.get(store) ?? 0;
}

/** Reset all tracked revisions. Used between tests. */
export function resetRevisions(): void {
  lastRevisions.clear();
}
