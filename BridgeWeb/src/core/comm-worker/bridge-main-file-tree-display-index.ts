import type { BridgeWorkerFileDisplayPatch } from './bridge-worker-contracts.js';

export type BridgeMainFileTreeDisplayRow = Extract<
	Extract<
		BridgeWorkerFileDisplayPatch,
		{ readonly operation: 'batch'; readonly slice: 'fileTree' }
	>['payload']['operations'][number],
	{ readonly operation: 'upsert' }
>['row'];

type FileTreeOperation = Extract<
	BridgeWorkerFileDisplayPatch,
	{ readonly operation: 'batch'; readonly slice: 'fileTree' }
>['payload']['operations'][number];

const bridgeMainFileTreeIndexBucketCount = 256;

export interface BridgeMainFileTreeIndexApplyResult {
	readonly index: BridgeMainFileTreeDisplayIndex;
	readonly pierreOperations: readonly BridgeMainPierreFileTreeOperation[];
}

export type BridgeMainPierreFileTreeOperation =
	| { readonly path: string; readonly type: 'add' }
	| { readonly path: string; readonly recursive: true; readonly type: 'remove' };

export class BridgeMainFileTreeDisplayIndex {
	static empty(): BridgeMainFileTreeDisplayIndex {
		return new BridgeMainFileTreeDisplayIndex(
			PersistentStringMap.empty(),
			PersistentStringMap.empty(),
			null,
		);
	}

	readonly #rowsById: PersistentStringMap<BridgeMainFileTreeDisplayRow>;
	readonly #rowsByPath: PersistentStringMap<BridgeMainFileTreeDisplayRow>;
	readonly #firstFileRow: BridgeMainFileTreeDisplayRow | null;

	private constructor(
		rowsById: PersistentStringMap<BridgeMainFileTreeDisplayRow>,
		rowsByPath: PersistentStringMap<BridgeMainFileTreeDisplayRow>,
		firstFileRow: BridgeMainFileTreeDisplayRow | null,
	) {
		this.#rowsById = rowsById;
		this.#rowsByPath = rowsByPath;
		this.#firstFileRow = firstFileRow;
	}

	get size(): number {
		return this.#rowsById.size;
	}

	rowForId(rowId: string): BridgeMainFileTreeDisplayRow | undefined {
		return this.#rowsById.get(rowId);
	}

	rowForPath(path: string): BridgeMainFileTreeDisplayRow | undefined {
		return this.#rowsByPath.get(path);
	}

	firstFileRow(): BridgeMainFileTreeDisplayRow | null {
		return this.#firstFileRow;
	}

	applyOperations(operations: readonly FileTreeOperation[]): BridgeMainFileTreeIndexApplyResult {
		let rowsById = this.#rowsById;
		let rowsByPath = this.#rowsByPath;
		let firstFileRow = this.#firstFileRow;
		const pierreOperations: BridgeMainPierreFileTreeOperation[] = [];
		for (const operation of operations) {
			if (operation.operation === 'remove') {
				const previousRow = rowsById.get(operation.rowId);
				if (previousRow === undefined) continue;
				rowsById = rowsById.delete(previousRow.rowId);
				rowsByPath = rowsByPath.delete(previousRow.path);
				if (firstFileRow?.rowId === previousRow.rowId) firstFileRow = null;
				pierreOperations.push({
					path: pierrePathForFileTreeRow(previousRow),
					recursive: true,
					type: 'remove',
				});
				continue;
			}
			const nextRow = operation.row;
			const previousRow = rowsById.get(nextRow.rowId);
			if (previousRow !== undefined && previousRow.path !== nextRow.path) {
				rowsByPath = rowsByPath.delete(previousRow.path);
				pierreOperations.push({
					path: pierrePathForFileTreeRow(previousRow),
					recursive: true,
					type: 'remove',
				});
			}
			rowsById = rowsById.set(nextRow.rowId, nextRow);
			rowsByPath = rowsByPath.set(nextRow.path, nextRow);
			if (
				!nextRow.isDirectory &&
				nextRow.fileId !== null &&
				(firstFileRow === null || nextRow.projectionIndex < firstFileRow.projectionIndex)
			) {
				firstFileRow = nextRow;
			}
			if (previousRow === undefined || previousRow.path !== nextRow.path) {
				pierreOperations.push({ path: pierrePathForFileTreeRow(nextRow), type: 'add' });
			}
		}
		return {
			index: new BridgeMainFileTreeDisplayIndex(rowsById, rowsByPath, firstFileRow),
			pierreOperations,
		};
	}
}

export interface BridgeMainFileItemDisplayIndex<TValue> {
	readonly size: number;
	readonly get: (key: string) => TValue | undefined;
}

export class BridgeMainImmutableStringMap<
	TValue,
> implements BridgeMainFileItemDisplayIndex<TValue> {
	static empty<TValue>(): BridgeMainImmutableStringMap<TValue> {
		return new BridgeMainImmutableStringMap(PersistentStringMap.empty());
	}

	readonly #values: PersistentStringMap<TValue>;

	private constructor(values: PersistentStringMap<TValue>) {
		this.#values = values;
	}

	get size(): number {
		return this.#values.size;
	}

	get = (key: string): TValue | undefined => this.#values.get(key);

	set(key: string, value: TValue): BridgeMainImmutableStringMap<TValue> {
		return new BridgeMainImmutableStringMap(this.#values.set(key, value));
	}

	delete(key: string): BridgeMainImmutableStringMap<TValue> {
		return new BridgeMainImmutableStringMap(this.#values.delete(key));
	}
}

class PersistentStringMap<TValue> {
	static empty<TValue>(): PersistentStringMap<TValue> {
		return new PersistentStringMap(
			Array.from({ length: bridgeMainFileTreeIndexBucketCount }, () => new Map()),
			0,
		);
	}

	readonly #buckets: readonly ReadonlyMap<string, TValue>[];
	readonly size: number;

	private constructor(buckets: readonly ReadonlyMap<string, TValue>[], size: number) {
		this.#buckets = buckets;
		this.size = size;
	}

	get(key: string): TValue | undefined {
		return this.#buckets[bucketIndexForString(key)]?.get(key);
	}

	set(key: string, value: TValue): PersistentStringMap<TValue> {
		const bucketIndex = bucketIndexForString(key);
		const previousBucket = this.#buckets[bucketIndex] ?? new Map();
		const hadKey = previousBucket.has(key);
		if (hadKey && previousBucket.get(key) === value) return this;
		const nextBucket = new Map(previousBucket);
		nextBucket.set(key, value);
		const nextBuckets = this.#buckets.slice();
		nextBuckets[bucketIndex] = nextBucket;
		return new PersistentStringMap(nextBuckets, hadKey ? this.size : this.size + 1);
	}

	delete(key: string): PersistentStringMap<TValue> {
		const bucketIndex = bucketIndexForString(key);
		const previousBucket = this.#buckets[bucketIndex];
		if (previousBucket === undefined || !previousBucket.has(key)) return this;
		const nextBucket = new Map(previousBucket);
		nextBucket.delete(key);
		const nextBuckets = this.#buckets.slice();
		nextBuckets[bucketIndex] = nextBucket;
		return new PersistentStringMap(nextBuckets, this.size - 1);
	}
}

function bucketIndexForString(value: string): number {
	let hash = 2_166_136_261;
	for (let index = 0; index < value.length; index += 1) {
		hash ^= value.charCodeAt(index);
		hash = Math.imul(hash, 16_777_619);
	}
	return (hash >>> 0) % bridgeMainFileTreeIndexBucketCount;
}

function pierrePathForFileTreeRow(row: BridgeMainFileTreeDisplayRow): string {
	return row.isDirectory && !row.path.endsWith('/') ? `${row.path}/` : row.path;
}
