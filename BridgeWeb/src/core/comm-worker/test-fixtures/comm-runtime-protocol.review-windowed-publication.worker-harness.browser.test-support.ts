import { createBridgeProductDeferred } from '../bridge-product-async-queue.js';
import {
	bridgeWorkerServerToMainMessageSchema,
	type BridgeWorkerServerToMainMessage,
} from '../bridge-worker-contracts.js';
import type {
	WindowedReviewMetadataFrame,
	WindowedReviewMetadataInterestUpdate,
	WindowedReviewWorkerControlMessage,
	WindowedReviewWorkerControlReceipt,
} from './comm-runtime-protocol.review-windowed-publication.worker-test-fixture.js';

export class WindowedReviewWorkerHarness {
	readonly #controlPort: MessagePort;
	readonly #installed = harnessDeferred<void>();
	readonly #interestUpdateReceived = harnessDeferred<void>();
	readonly #messageWaiters: Array<{
		readonly deferred: ReturnType<typeof harnessDeferred<BridgeWorkerServerToMainMessage>>;
		readonly predicate: (message: BridgeWorkerServerToMainMessage) => boolean;
	}> = [];
	readonly #processedByStreamSequence = new Map<number, ReturnType<typeof harnessDeferred<void>>>();
	#failure: Error | null = null;
	#terminated = false;
	onInterestUpdate: (update: WindowedReviewMetadataInterestUpdate) => void = (): void => {};
	readonly observedMessages: BridgeWorkerServerToMainMessage[] = [];
	readonly worker: Worker;

	constructor() {
		this.worker = new Worker(
			new URL(
				'./comm-runtime-protocol.review-windowed-publication.worker-test-fixture.ts',
				import.meta.url,
			),
			{ type: 'module' },
		);
		const controlChannel = new MessageChannel();
		this.#controlPort = controlChannel.port2;
		this.worker.addEventListener('message', (event: MessageEvent<unknown>): void => {
			try {
				const message = bridgeWorkerServerToMainMessageSchema.parse(event.data);
				this.observedMessages.push(message);
				for (
					let waiterIndex = this.#messageWaiters.length - 1;
					waiterIndex >= 0;
					waiterIndex -= 1
				) {
					const waiter = this.#messageWaiters[waiterIndex];
					if (waiter === undefined || !waiter.predicate(message)) continue;
					this.#messageWaiters.splice(waiterIndex, 1);
					waiter.deferred.resolve(message);
				}
			} catch (error) {
				this.#fail(error);
			}
		});
		this.worker.addEventListener('error', (event: ErrorEvent): void => {
			this.#fail(new Error(event.message || 'Windowed Review worker failed.'));
		});
		this.worker.addEventListener('messageerror', (): void => {
			this.#fail(new Error('Windowed Review worker emitted an unreadable message.'));
		});
		this.#controlPort.addEventListener('message', (event: MessageEvent<unknown>): void => {
			if (!isWindowedReviewWorkerControlReceipt(event.data)) {
				this.#fail(new Error('Windowed Review worker emitted an invalid control receipt.'));
				return;
			}
			this.#acceptControlReceipt(event.data);
		});
		this.#controlPort.start();
		this.worker.postMessage(
			{
				controlPort: controlChannel.port1,
				kind: 'windowedReview.install',
			} satisfies WindowedReviewWorkerControlMessage,
			[controlChannel.port1],
		);
	}

	get installed(): Promise<void> {
		return this.#installed.promise;
	}

	publishMetadata(frame: WindowedReviewMetadataFrame): void {
		if (this.#failure !== null) throw this.#failure;
		if (this.#terminated) throw new Error('Windowed Review worker is terminated.');
		if (this.#processedByStreamSequence.has(frame.streamSequence)) {
			throw new Error(`Review metadata sequence ${frame.streamSequence} was already published.`);
		}
		this.#processedByStreamSequence.set(frame.streamSequence, harnessDeferred<void>());
		this.#controlPort.postMessage({
			frame,
			kind: 'windowedReview.metadata.publish',
		} satisfies WindowedReviewWorkerControlMessage);
	}

	waitForInterestUpdate(): Promise<void> {
		if (this.#failure !== null) return Promise.reject(this.#failure);
		return this.#interestUpdateReceived.promise;
	}

	waitForMessage(
		predicate: (message: BridgeWorkerServerToMainMessage) => boolean,
	): Promise<BridgeWorkerServerToMainMessage> {
		if (this.#failure !== null) return Promise.reject(this.#failure);
		const existing = this.observedMessages.find(predicate);
		if (existing !== undefined) return Promise.resolve(existing);
		const deferred = harnessDeferred<BridgeWorkerServerToMainMessage>();
		this.#messageWaiters.push({ deferred, predicate });
		return deferred.promise;
	}

	waitUntilProcessed(streamSequence: number): Promise<void> {
		if (this.#failure !== null) return Promise.reject(this.#failure);
		const processed = this.#processedByStreamSequence.get(streamSequence);
		if (processed === undefined) {
			throw new Error(`Review metadata sequence ${streamSequence} was not published.`);
		}
		return processed.promise;
	}

	terminate(): void {
		if (this.#terminated) return;
		this.#terminated = true;
		this.worker.terminate();
		this.#controlPort.close();
		this.#fail(new Error('Windowed Review worker test harness terminated.'));
	}

	#acceptControlReceipt(value: WindowedReviewWorkerControlReceipt): void {
		switch (value.kind) {
			case 'windowedReview.installed':
				this.#installed.resolve();
				return;
			case 'windowedReview.metadata.processed': {
				const processed = this.#processedByStreamSequence.get(value.streamSequence);
				if (processed === undefined) {
					this.#fail(
						new Error(`Worker acknowledged unknown Review sequence ${value.streamSequence}.`),
					);
					return;
				}
				processed.resolve();
				return;
			}
			case 'windowedReview.metadata.interests':
				this.onInterestUpdate(value.update);
				this.#interestUpdateReceived.resolve();
				return;
			case 'windowedReview.failed':
				this.#fail(new Error(value.message));
		}
	}

	#fail(error: unknown): void {
		const failure = error instanceof Error ? error : new Error(String(error));
		if (this.#failure !== null) return;
		this.#failure = failure;
		this.#installed.reject(failure);
		this.#interestUpdateReceived.reject(failure);
		for (const waiter of this.#messageWaiters.splice(0, this.#messageWaiters.length)) {
			waiter.deferred.reject(failure);
		}
		for (const processed of this.#processedByStreamSequence.values()) processed.reject(failure);
	}
}

function harnessDeferred<TValue>(): ReturnType<typeof createBridgeProductDeferred<TValue>> {
	const deferred = createBridgeProductDeferred<TValue>();
	void deferred.promise.catch((): void => {});
	return deferred;
}

function isWindowedReviewWorkerControlReceipt(
	value: unknown,
): value is WindowedReviewWorkerControlReceipt {
	if (typeof value !== 'object' || value === null || !('kind' in value)) return false;
	switch (value.kind) {
		case 'windowedReview.installed':
			return true;
		case 'windowedReview.metadata.processed':
			return 'streamSequence' in value && typeof value.streamSequence === 'number';
		case 'windowedReview.metadata.interests':
			return 'update' in value;
		case 'windowedReview.failed':
			return 'message' in value && typeof value.message === 'string';
		default:
			return false;
	}
}
