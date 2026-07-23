import type { BridgeProductContentResponseStartControl } from './bridge-product-transport-contract.js';

export const BRIDGE_PRODUCT_MAXIMUM_CONCURRENT_CONTENT_RESPONSES = 12;

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

type BridgeProductContentResponseStartState = 'paused' | 'started' | 'waiting';

interface BridgeProductContentResponseResumeWaiter {
	readonly resume: () => void;
}

const bridgeProductContentResponseStartPaused = Symbol(
	'bridge-product-content-response-start-paused',
);

export class BridgeProductContentResponseStartAdmission {
	readonly control: BridgeProductContentResponseStartControl = {
		pauseBeforeStart: (): void => {
			if (this.#state !== 'waiting') return;
			this.#state = 'paused';
			this.#admissionAbortController?.abort(bridgeProductContentResponseStartPaused);
		},
		resumeBeforeStart: (): void => {
			if (this.#state !== 'paused') return;
			this.#state = 'waiting';
			this.#resumeWaiter?.resume();
		},
	};
	#admissionAbortController: AbortController | null = null;
	#resumeWaiter: BridgeProductContentResponseResumeWaiter | null = null;
	#state: BridgeProductContentResponseStartState = 'waiting';

	async acquire(
		admission: BridgeProductContentResponseAdmission,
		abortSignal: AbortSignal,
	): Promise<BridgeProductContentResponseAdmissionLease> {
		while (true) {
			abortSignal.throwIfAborted();
			// eslint-disable-next-line no-await-in-loop -- A paused logical stream waits for its own resume before reacquiring.
			await this.#waitUntilResumed(abortSignal);
			abortSignal.throwIfAborted();
			const admissionAbortController = new AbortController();
			const abortAdmission = (): void => {
				admissionAbortController.abort(abortSignal.reason);
			};
			this.#admissionAbortController = admissionAbortController;
			abortSignal.addEventListener('abort', abortAdmission, { once: true });
			if (this.#state === 'paused') {
				admissionAbortController.abort(bridgeProductContentResponseStartPaused);
			}
			let lease: BridgeProductContentResponseAdmissionLease;
			try {
				// eslint-disable-next-line no-await-in-loop -- A resumed logical stream reacquires one withdrawn admission waiter.
				lease = await admission.acquire(admissionAbortController.signal);
			} catch (error) {
				if (abortSignal.aborted) abortSignal.throwIfAborted();
				if (error === bridgeProductContentResponseStartPaused) continue;
				throw error;
			} finally {
				abortSignal.removeEventListener('abort', abortAdmission);
				if (this.#admissionAbortController === admissionAbortController) {
					this.#admissionAbortController = null;
				}
			}
			if (this.#state === 'paused') {
				lease.release();
				continue;
			}
			this.#state = 'started';
			return lease;
		}
	}

	async #waitUntilResumed(abortSignal: AbortSignal): Promise<void> {
		if (this.#state !== 'paused') return;
		await new Promise<void>((resolve, reject): void => {
			const abortWaiter = (): void => {
				clearWaiter();
				reject(abortSignal.reason);
			};
			const resumeWaiter: BridgeProductContentResponseResumeWaiter = {
				resume: (): void => {
					clearWaiter();
					resolve();
				},
			};
			const clearWaiter = (): void => {
				abortSignal.removeEventListener('abort', abortWaiter);
				if (this.#resumeWaiter === resumeWaiter) this.#resumeWaiter = null;
			};
			this.#resumeWaiter = resumeWaiter;
			abortSignal.addEventListener('abort', abortWaiter, { once: true });
			if (abortSignal.aborted) {
				abortWaiter();
			} else if (this.#state !== 'paused') {
				resumeWaiter.resume();
			}
		});
	}
}
