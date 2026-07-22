export const BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES = 4;

export interface BridgeProductContentResponseAdmissionLease {
	release(): void;
}

interface BridgeProductContentResponseAdmissionWaiter {
	readonly abortWaiter: () => void;
	readonly abortSignal: AbortSignal;
	readonly reject: (reason: unknown) => void;
	readonly resolve: (lease: BridgeProductContentResponseAdmissionLease) => void;
}

export class BridgeProductContentResponseAdmission {
	readonly #maximumConcurrentResponses: number;
	readonly #waiters: BridgeProductContentResponseAdmissionWaiter[] = [];
	#activeResponseCount = 0;

	constructor(maximumConcurrentResponses = BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES) {
		if (!Number.isSafeInteger(maximumConcurrentResponses) || maximumConcurrentResponses <= 0) {
			throw new Error(
				'Bridge product content response admission requires a positive integer limit.',
			);
		}
		this.#maximumConcurrentResponses = maximumConcurrentResponses;
	}

	acquire(abortSignal: AbortSignal): Promise<BridgeProductContentResponseAdmissionLease> {
		abortSignal.throwIfAborted();
		if (this.#activeResponseCount < this.#maximumConcurrentResponses) {
			this.#activeResponseCount += 1;
			return Promise.resolve(this.#createLease());
		}
		return new Promise((resolve, reject): void => {
			const abortWaiter = (): void => {
				const waiterIndex = this.#waiters.indexOf(waiter);
				if (waiterIndex < 0) return;
				this.#waiters.splice(waiterIndex, 1);
				abortSignal.removeEventListener('abort', abortWaiter);
				reject(abortSignal.reason);
			};
			const waiter: BridgeProductContentResponseAdmissionWaiter = {
				abortWaiter,
				abortSignal,
				reject,
				resolve,
			};
			abortSignal.addEventListener('abort', abortWaiter, { once: true });
			this.#waiters.push(waiter);
			if (abortSignal.aborted) abortWaiter();
		});
	}

	#createLease(): BridgeProductContentResponseAdmissionLease {
		let released = false;
		return {
			release: (): void => {
				if (released) return;
				released = true;
				this.#activeResponseCount -= 1;
				this.#admitNextWaiter();
			},
		};
	}

	#admitNextWaiter(): void {
		while (
			this.#activeResponseCount < this.#maximumConcurrentResponses &&
			this.#waiters.length > 0
		) {
			const waiter = this.#waiters.shift();
			if (waiter === undefined) return;
			waiter.abortSignal.removeEventListener('abort', waiter.abortWaiter);
			if (waiter.abortSignal.aborted) {
				waiter.reject(waiter.abortSignal.reason);
				continue;
			}
			this.#activeResponseCount += 1;
			waiter.resolve(this.#createLease());
		}
	}
}
