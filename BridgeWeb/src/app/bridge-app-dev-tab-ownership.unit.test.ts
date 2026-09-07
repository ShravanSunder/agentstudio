import { describe, expect, test, vi } from 'vitest';

import { createBridgeAppDevTabOwnership } from './bridge-app-dev-tab-ownership.js';

describe('Bridge app development-tab ownership', () => {
	test('failed bootstrap does not take ownership from the active tab', async () => {
		// Arrange
		const sharedOwnership = new TestSharedOwnershipStorage();
		const runExclusive = createSerializedRunExclusive();
		const activeSuperseded = vi.fn();
		const active = createOwnership({
			onSuperseded: activeSuperseded,
			ownerId: 'active',
			runExclusive,
			sharedOwnership,
		});
		const candidate = createOwnership({ ownerId: 'candidate', runExclusive, sharedOwnership });
		await active.runBootstrap(async () => 'active-ready', new AbortController().signal);

		// Act
		const bootstrap = candidate.runBootstrap(async () => {
			throw new Error('bootstrap failed');
		}, new AbortController().signal);

		// Assert
		await expect(bootstrap).rejects.toThrow('bootstrap failed');
		expect(activeSuperseded).not.toHaveBeenCalled();
		expect(active.isSuperseded()).toBe(false);
	});

	test('an active tab becomes terminally superseded exactly once', async () => {
		// Arrange
		const sharedOwnership = new TestSharedOwnershipStorage();
		const storage = new TestStorage();
		const onSuperseded = vi.fn();
		const ownership = createOwnership({
			onSuperseded,
			ownerId: 'active',
			sharedOwnership,
			storage,
		});
		await ownership.runBootstrap(async () => undefined, new AbortController().signal);

		// Act
		sharedOwnership.claim('replacement');
		sharedOwnership.claim('replacement-again');

		// Assert
		expect(ownership.isSuperseded()).toBe(true);
		expect(onSuperseded).toHaveBeenCalledTimes(1);
		expect(storage.values.size).toBe(1);
	});

	test('a superseded tab remains blocked after reload until explicitly cleared', async () => {
		// Arrange
		const sharedOwnership = new TestSharedOwnershipStorage();
		const storage = new TestStorage();
		const initial = createOwnership({ ownerId: 'initial', sharedOwnership, storage });
		await initial.runBootstrap(async () => undefined, new AbortController().signal);
		sharedOwnership.claim('replacement');
		initial.dispose();
		const reloaded = createOwnership({ ownerId: 'reloaded', sharedOwnership, storage });
		const operation = vi.fn(async () => undefined);

		// Act / Assert
		await expect(reloaded.runBootstrap(operation, new AbortController().signal)).rejects.toThrow(
			'superseded',
		);
		expect(operation).not.toHaveBeenCalled();
		reloaded.clearSuperseded();
		await expect(
			reloaded.runBootstrap(operation, new AbortController().signal),
		).resolves.toBeUndefined();
		expect(operation).toHaveBeenCalledTimes(1);
	});

	test('an aborted queued bootstrap never executes or claims ownership', async () => {
		// Arrange
		const sharedOwnership = new TestSharedOwnershipStorage();
		const runExclusive = createSerializedRunExclusive();
		const firstOperation = deferred<void>();
		const first = createOwnership({ ownerId: 'first', runExclusive, sharedOwnership });
		const queued = createOwnership({ ownerId: 'queued', runExclusive, sharedOwnership });
		const firstBootstrap = first.runBootstrap(
			() => firstOperation.promise,
			new AbortController().signal,
		);
		const queuedOperation = vi.fn(async () => undefined);
		const queuedAbortController = new AbortController();
		const queuedBootstrap = queued.runBootstrap(queuedOperation, queuedAbortController.signal);

		// Act
		queuedAbortController.abort();
		firstOperation.resolve();

		// Assert
		await expect(queuedBootstrap).rejects.toMatchObject({ name: 'AbortError' });
		await expect(firstBootstrap).resolves.toBeUndefined();
		expect(queuedOperation).not.toHaveBeenCalled();
		expect(sharedOwnership.currentOwner()).toBe('first');
	});

	test('ignores storage events for its own current ownership', async () => {
		// Arrange
		const sharedOwnership = new TestSharedOwnershipStorage();
		const onSuperseded = vi.fn();
		const ownership = createOwnership({ onSuperseded, ownerId: 'sole-owner', sharedOwnership });

		// Act
		await ownership.runBootstrap(async () => undefined, new AbortController().signal);

		// Assert
		expect(ownership.isSuperseded()).toBe(false);
		expect(onSuperseded).not.toHaveBeenCalled();
	});

	test('ignores delayed stale ownership events after serialized bootstraps', async () => {
		// Arrange
		const events: string[] = [];
		const sharedOwnership = new TestSharedOwnershipStorage({ queueEvents: true });
		const runExclusive = createSerializedRunExclusive();
		const firstSuperseded = vi.fn(() => events.push('superseded:first'));
		const secondSuperseded = vi.fn(() => events.push('superseded:second'));
		const first = createOwnership({
			onSuperseded: firstSuperseded,
			ownerId: 'first',
			runExclusive,
			sharedOwnership,
		});
		const second = createOwnership({
			onSuperseded: secondSuperseded,
			ownerId: 'second',
			runExclusive,
			sharedOwnership,
		});

		// Act
		await first.runBootstrap(
			async () => events.push('operation:first'),
			new AbortController().signal,
		);
		await second.runBootstrap(
			async () => events.push('operation:second'),
			new AbortController().signal,
		);
		sharedOwnership.deliverQueuedEventsInReverseOrder();

		// Assert
		expect(events).toEqual(['operation:first', 'operation:second', 'superseded:first']);
		expect(sharedOwnership.currentOwner()).toBe('second');
		expect(firstSuperseded).toHaveBeenCalledTimes(1);
		expect(secondSuperseded).not.toHaveBeenCalled();
		expect(second.isSuperseded()).toBe(false);
	});

	test('blocks a queued bootstrap from a prior owner before delayed storage delivery', async () => {
		// Arrange
		const sharedOwnership = new TestSharedOwnershipStorage({ queueEvents: true });
		const runExclusive = createSerializedRunExclusive();
		const firstSuperseded = vi.fn();
		const first = createOwnership({
			onSuperseded: firstSuperseded,
			ownerId: 'first',
			runExclusive,
			sharedOwnership,
		});
		const second = createOwnership({ ownerId: 'second', runExclusive, sharedOwnership });
		await first.runBootstrap(async () => undefined, new AbortController().signal);
		const secondOperation = deferred<void>();
		const secondBootstrap = second.runBootstrap(
			() => secondOperation.promise,
			new AbortController().signal,
		);
		await Promise.resolve();
		const staleOperation = vi.fn(async () => undefined);
		const staleBootstrap = first.runBootstrap(staleOperation, new AbortController().signal);

		// Act
		secondOperation.resolve();

		// Assert
		await expect(secondBootstrap).resolves.toBeUndefined();
		await expect(staleBootstrap).rejects.toThrow('superseded');
		expect(staleOperation).not.toHaveBeenCalled();
		expect(first.isSuperseded()).toBe(true);
		expect(firstSuperseded).toHaveBeenCalledTimes(1);
		expect(sharedOwnership.currentOwner()).toBe('second');
	});

	test('dispose removes the storage listener and prevents later callbacks', async () => {
		// Arrange
		const sharedOwnership = new TestSharedOwnershipStorage();
		const onSuperseded = vi.fn();
		const ownership = createOwnership({ onSuperseded, ownerId: 'disposed', sharedOwnership });
		await ownership.runBootstrap(async () => undefined, new AbortController().signal);
		const eventTarget = sharedOwnership.eventTargets[0];
		if (eventTarget === undefined) throw new Error('Expected an ownership event target.');

		// Act
		ownership.dispose();
		sharedOwnership.claim('replacement');

		// Assert
		expect(eventTarget.listenerCount).toBe(0);
		expect(onSuperseded).not.toHaveBeenCalled();
		await expect(
			ownership.runBootstrap(async () => undefined, new AbortController().signal),
		).rejects.toThrow('disposed');
	});

	test('fails visibly instead of bootstrapping without Web Locks', async () => {
		vi.stubGlobal('navigator', {});
		try {
			// Arrange
			const sharedOwnership = new TestSharedOwnershipStorage();
			const operation = vi.fn(async () => undefined);
			const ownership = createBridgeAppDevTabOwnership({
				onSuperseded: (): void => {},
				ownerId: 'unsupported-browser',
				sharedStorage: sharedOwnership,
				storage: new TestStorage(),
				storageEventTarget: sharedOwnership.createEventTarget(),
			});

			// Act / Assert
			await expect(ownership.runBootstrap(operation, new AbortController().signal)).rejects.toThrow(
				'Web Locks API',
			);
			expect(operation).not.toHaveBeenCalled();
		} finally {
			vi.unstubAllGlobals();
		}
	});
});

class TestStorage implements Pick<Storage, 'getItem' | 'removeItem' | 'setItem'> {
	readonly values = new Map<string, string>();

	getItem(key: string): string | null {
		return this.values.get(key) ?? null;
	}

	removeItem(key: string): void {
		this.values.delete(key);
	}

	setItem(key: string, value: string): void {
		this.values.set(key, value);
	}
}

class TestSharedOwnershipStorage implements Pick<Storage, 'getItem' | 'setItem'> {
	readonly eventTargets: TestStorageEventTarget[] = [];
	readonly #queueEvents: boolean;
	readonly #queuedEvents: TestStorageEvent[] = [];
	readonly #values = new Map<string, string>();

	constructor(options: { readonly queueEvents?: boolean } = {}) {
		this.#queueEvents = options.queueEvents ?? false;
	}

	claim(ownerId: string): void {
		this.setItem(this.#requiredOwnershipKey(), ownerId);
	}

	createEventTarget(): TestStorageEventTarget {
		const target = new TestStorageEventTarget();
		this.eventTargets.push(target);
		return target;
	}

	currentOwner(): string | null {
		return this.#values.get(this.#requiredOwnershipKey()) ?? null;
	}

	deliverQueuedEventsInReverseOrder(): void {
		for (const event of this.#queuedEvents.toReversed()) this.#deliver(event);
		this.#queuedEvents.length = 0;
	}

	getItem(key: string): string | null {
		return this.#values.get(key) ?? null;
	}

	setItem(key: string, value: string): void {
		this.#values.set(key, value);
		const event = { key } satisfies TestStorageEvent;
		if (this.#queueEvents) this.#queuedEvents.push(event);
		else this.#deliver(event);
	}

	#deliver(event: TestStorageEvent): void {
		for (const target of this.eventTargets) target.deliver(event);
	}

	#requiredOwnershipKey(): string {
		const ownershipKey = [...this.#values.keys()][0];
		if (ownershipKey === undefined) throw new Error('Expected a current-owner storage marker.');
		return ownershipKey;
	}
}

class TestStorageEventTarget {
	readonly #listeners = new Set<(event: TestStorageEvent) => void>();

	get listenerCount(): number {
		return this.#listeners.size;
	}

	addEventListener(_type: 'storage', listener: (event: TestStorageEvent) => void): void {
		this.#listeners.add(listener);
	}

	deliver(event: TestStorageEvent): void {
		for (const listener of this.#listeners) listener(event);
	}

	removeEventListener(_type: 'storage', listener: (event: TestStorageEvent) => void): void {
		this.#listeners.delete(listener);
	}
}

interface TestStorageEvent {
	readonly key: string | null;
}

function createOwnership(options: {
	readonly onSuperseded?: () => void;
	readonly ownerId: string;
	readonly runExclusive?: TestRunExclusive;
	readonly sharedOwnership: TestSharedOwnershipStorage;
	readonly storage?: TestStorage;
}): ReturnType<typeof createBridgeAppDevTabOwnership> {
	return createBridgeAppDevTabOwnership({
		onSuperseded: options.onSuperseded ?? ((): void => {}),
		ownerId: options.ownerId,
		runExclusive: options.runExclusive ?? createSerializedRunExclusive(),
		sharedStorage: options.sharedOwnership,
		storage: options.storage ?? new TestStorage(),
		storageEventTarget: options.sharedOwnership.createEventTarget(),
	});
}

type TestRunExclusive = <TResult>(
	operation: (signal: AbortSignal) => Promise<TResult>,
	signal: AbortSignal,
) => Promise<TResult>;

function createSerializedRunExclusive(): TestRunExclusive {
	let tail = Promise.resolve();
	return async <TResult>(
		operation: (signal: AbortSignal) => Promise<TResult>,
		signal: AbortSignal,
	): Promise<TResult> => {
		const predecessor = tail;
		let release!: () => void;
		tail = new Promise<void>((resolve): void => {
			release = resolve;
		});
		try {
			await Promise.race([predecessor, rejectWhenAborted(signal)]);
			signal.throwIfAborted();
			return await operation(signal);
		} finally {
			release();
		}
	};
}

function rejectWhenAborted(signal: AbortSignal): Promise<never> {
	return new Promise<never>((_resolve, reject): void => {
		if (signal.aborted) {
			reject(signal.reason);
			return;
		}
		signal.addEventListener('abort', (): void => reject(signal.reason), { once: true });
	});
}

function deferred<TResult>(): {
	readonly promise: Promise<TResult>;
	readonly resolve: (value: TResult) => void;
} {
	let resolve!: (value: TResult) => void;
	const promise = new Promise<TResult>((resolvePromise): void => {
		resolve = resolvePromise;
	});
	return { promise, resolve };
}
