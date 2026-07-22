export interface BridgeBodyRegistryProps {
	readonly maxBytes: number;
}

export interface BridgeBodyRegistryPutProps<TBody> {
	readonly cacheKey: string;
	readonly freshnessKey: string;
	readonly body: TBody;
	readonly byteLength: number;
}

export interface BridgeBodyRegistryGetProps {
	readonly cacheKey: string;
	readonly freshnessKey: string;
}

export interface BridgeBodyRegistryEvictStaleProps {
	readonly cacheKey: string;
	readonly keepFreshnessKey: string;
}

export interface BridgeBodyRegistrySnapshot {
	readonly entryCount: number;
	readonly totalBytes: number;
}

export interface BridgeBodyRegistry<TBody = unknown> {
	put(props: BridgeBodyRegistryPutProps<TBody>): void;
	get(props: BridgeBodyRegistryGetProps): TBody | null;
	evictStale(props: BridgeBodyRegistryEvictStaleProps): number;
	snapshot(): BridgeBodyRegistrySnapshot;
}

interface BridgeBodyRegistryEntry<TBody> {
	readonly cacheKey: string;
	readonly freshnessKey: string;
	readonly body: TBody;
	readonly byteLength: number;
	lastAccessSequence: number;
}

export function createBridgeBodyRegistry<TBody = unknown>(
	props: BridgeBodyRegistryProps,
): BridgeBodyRegistry<TBody> {
	const entriesByKey = new Map<string, BridgeBodyRegistryEntry<TBody>>();
	let totalBytes = 0;
	let nextAccessSequence = 0;

	const touch = (entry: BridgeBodyRegistryEntry<TBody>): void => {
		entry.lastAccessSequence = nextAccessSequence;
		nextAccessSequence += 1;
	};

	const evictUntilWithinBudget = (): void => {
		while (totalBytes > props.maxBytes && entriesByKey.size > 0) {
			const lruEntry = Array.from(entriesByKey.values()).toSorted(
				(left, right): number => left.lastAccessSequence - right.lastAccessSequence,
			)[0];
			if (lruEntry === undefined) {
				return;
			}
			entriesByKey.delete(makeEntryKey(lruEntry.cacheKey, lruEntry.freshnessKey));
			totalBytes -= lruEntry.byteLength;
		}
	};

	return {
		put(putProps: BridgeBodyRegistryPutProps<TBody>): void {
			const entryKey = makeEntryKey(putProps.cacheKey, putProps.freshnessKey);
			const previousEntry = entriesByKey.get(entryKey);
			if (previousEntry !== undefined) {
				totalBytes -= previousEntry.byteLength;
			}
			const nextEntry: BridgeBodyRegistryEntry<TBody> = {
				cacheKey: putProps.cacheKey,
				freshnessKey: putProps.freshnessKey,
				body: putProps.body,
				byteLength: putProps.byteLength,
				lastAccessSequence: nextAccessSequence,
			};
			touch(nextEntry);
			entriesByKey.set(entryKey, nextEntry);
			totalBytes += putProps.byteLength;
			evictUntilWithinBudget();
		},
		get(getProps: BridgeBodyRegistryGetProps): TBody | null {
			const entry = entriesByKey.get(makeEntryKey(getProps.cacheKey, getProps.freshnessKey));
			if (entry === undefined) {
				return null;
			}
			touch(entry);
			return entry.body;
		},
		evictStale(evictProps: BridgeBodyRegistryEvictStaleProps): number {
			let evictedCount = 0;
			for (const [entryKey, entry] of entriesByKey) {
				if (
					entry.cacheKey !== evictProps.cacheKey ||
					entry.freshnessKey === evictProps.keepFreshnessKey
				) {
					continue;
				}
				entriesByKey.delete(entryKey);
				totalBytes -= entry.byteLength;
				evictedCount += 1;
			}
			return evictedCount;
		},
		snapshot(): BridgeBodyRegistrySnapshot {
			return {
				entryCount: entriesByKey.size,
				totalBytes,
			};
		},
	};
}

function makeEntryKey(cacheKey: string, freshnessKey: string): string {
	return `${cacheKey}\u0000${freshnessKey}`;
}
