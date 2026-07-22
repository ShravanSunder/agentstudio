export interface BridgeProductDeferred<TValue> {
	readonly promise: Promise<TValue>;
	reject(reason?: unknown): void;
	resolve(value: TValue): void;
}

export function createBridgeProductDeferred<TValue>(): BridgeProductDeferred<TValue> {
	let rejectPromise!: (reason?: unknown) => void;
	let resolvePromise!: (value: TValue) => void;
	const promise = new Promise<TValue>((resolve, reject): void => {
		rejectPromise = reject;
		resolvePromise = resolve;
	});
	return { promise, reject: rejectPromise, resolve: resolvePromise };
}

export class BridgeProductBoundedAsyncQueue<TValue> implements AsyncIterableIterator<TValue> {
	readonly #capacity: number;
	#failure: unknown = null;
	#finished = false;
	readonly #items: TValue[] = [];
	readonly #waiters: BridgeProductDeferred<IteratorResult<TValue>>[] = [];

	constructor(capacity: number) {
		if (!Number.isSafeInteger(capacity) || capacity <= 0) {
			throw new Error('Bridge product async queue requires a positive safe capacity.');
		}
		this.#capacity = capacity;
	}

	[Symbol.asyncIterator](): AsyncIterableIterator<TValue> {
		return this;
	}

	next(): Promise<IteratorResult<TValue>> {
		if (this.#failure !== null) return Promise.reject(this.#failure);
		const item = this.#items.shift();
		if (item !== undefined) return Promise.resolve({ done: false, value: item });
		if (this.#finished) return Promise.resolve({ done: true, value: undefined });
		const waiter = createBridgeProductDeferred<IteratorResult<TValue>>();
		this.#waiters.push(waiter);
		return waiter.promise;
	}

	return(): Promise<IteratorResult<TValue>> {
		this.close(true);
		return Promise.resolve({ done: true, value: undefined });
	}

	push(value: TValue): void {
		if (this.#finished || this.#failure !== null) {
			throw new Error('Bridge product async queue received a post-terminal item.');
		}
		const waiter = this.#waiters.shift();
		if (waiter !== undefined) {
			waiter.resolve({ done: false, value });
			return;
		}
		if (this.#items.length >= this.#capacity) {
			throw new Error('Bridge product async queue exceeded its bounded capacity.');
		}
		this.#items.push(value);
	}

	close(discardQueuedItems: boolean): void {
		if (this.#finished) return;
		this.#finished = true;
		if (discardQueuedItems) this.#items.splice(0, this.#items.length);
		for (const waiter of this.#waiters.splice(0, this.#waiters.length)) {
			waiter.resolve({ done: true, value: undefined });
		}
	}

	fail(error: unknown, discardQueuedItems: boolean): void {
		if (this.#finished || this.#failure !== null) return;
		this.#failure = error;
		if (discardQueuedItems) this.#items.splice(0, this.#items.length);
		for (const waiter of this.#waiters.splice(0, this.#waiters.length)) waiter.reject(error);
	}
}
