import type { BridgeCommWorkerPort } from '../bridge-comm-worker-entry.js';
// oxlint-disable unicorn/require-post-message-target-origin -- DedicatedWorkerGlobalScope and MessagePort do not accept targetOrigin.
import { registerBridgeCommWorkerRuntimePortProtocol } from '../bridge-comm-worker-runtime-protocol.js';
import { makeReviewProductTransport } from '../bridge-comm-worker-runtime-protocol.review-product-transport.test-support.js';
import { BridgeProductBoundedAsyncQueue } from '../bridge-product-async-queue.js';
import type {
	BridgeProductMetadataApplicationEvent,
	BridgeProductMetadataDataFrame,
} from '../bridge-product-metadata-application-protocol.js';
import { bridgeProductReviewMetadataApplicationProtocol } from '../bridge-product-metadata-application-registry.js';
import type { BridgeProductMetadataApplicationSubscription } from '../bridge-product-transport-contract.js';

type ReviewMetadataProtocol = typeof bridgeProductReviewMetadataApplicationProtocol;
type ReviewMetadataEvent = BridgeProductMetadataApplicationEvent<ReviewMetadataProtocol>;
export type WindowedReviewMetadataFrame = BridgeProductMetadataDataFrame<ReviewMetadataEvent>;
type ReviewMetadataSubscription =
	BridgeProductMetadataApplicationSubscription<ReviewMetadataProtocol>;
export type WindowedReviewMetadataInterestUpdate = Parameters<
	ReviewMetadataSubscription['update']
>[0];

export type WindowedReviewWorkerControlMessage =
	| {
			readonly controlPort: MessagePort;
			readonly kind: 'windowedReview.install';
	  }
	| {
			readonly frame: WindowedReviewMetadataFrame;
			readonly kind: 'windowedReview.metadata.publish';
	  };

export type WindowedReviewWorkerControlReceipt =
	| {
			readonly kind: 'windowedReview.installed';
	  }
	| {
			readonly kind: 'windowedReview.metadata.processed';
			readonly streamSequence: number;
	  }
	| {
			readonly kind: 'windowedReview.metadata.interests';
			readonly update: WindowedReviewMetadataInterestUpdate;
	  }
	| {
			readonly kind: 'windowedReview.failed';
			readonly message: string;
	  };

interface WindowedReviewWorkerScope extends BridgeCommWorkerPort {
	readonly addEventListener: (
		type: 'message',
		listener: (event: MessageEvent<unknown>) => void,
	) => void;
}

declare const self: WindowedReviewWorkerScope;

self.addEventListener('message', (event: MessageEvent<unknown>): void => {
	if (!isWindowedReviewInstallMessage(event.data)) return;
	event.stopImmediatePropagation();
	installWindowedReviewRuntime(event.data.controlPort);
});

function installWindowedReviewRuntime(controlPort: MessagePort): void {
	const metadataEvents = new WorkerControlledReviewMetadataQueue(controlPort, 64);
	const reviewSubscription: ReviewMetadataSubscription = {
		cancel: async (): Promise<void> => metadataEvents.close(),
		events: metadataEvents,
		subscriptionId: 'review-windowed-runtime-subscription',
		subscriptionKind: 'review.metadata',
		update: async (update): Promise<void> => {
			controlPort.postMessage({
				kind: 'windowedReview.metadata.interests',
				update,
			} satisfies WindowedReviewWorkerControlReceipt);
		},
	};
	controlPort.addEventListener('message', (event: MessageEvent<unknown>): void => {
		const message = event.data;
		if (!isWindowedReviewMetadataPublishMessage(message)) return;
		try {
			metadataEvents.push(message.frame);
		} catch (error) {
			controlPort.postMessage({
				kind: 'windowedReview.failed',
				message: error instanceof Error ? error.message : String(error),
			} satisfies WindowedReviewWorkerControlReceipt);
		}
	});
	controlPort.start();
	registerBridgeCommWorkerRuntimePortProtocol(self, {
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
		productTransport: makeReviewProductTransport({
			reviewSubscription,
			subscribedKinds: [],
		}),
	});
	controlPort.postMessage({
		kind: 'windowedReview.installed',
	} satisfies WindowedReviewWorkerControlReceipt);
}

class WorkerControlledReviewMetadataQueue implements AsyncIterableIterator<WindowedReviewMetadataFrame> {
	readonly #controlPort: MessagePort;
	readonly #events: BridgeProductBoundedAsyncQueue<WindowedReviewMetadataFrame>;
	#previousStreamSequence: number | null = null;

	constructor(controlPort: MessagePort, capacity: number) {
		this.#controlPort = controlPort;
		this.#events = new BridgeProductBoundedAsyncQueue(capacity);
	}

	[Symbol.asyncIterator](): AsyncIterableIterator<WindowedReviewMetadataFrame> {
		return this;
	}

	async next(): Promise<IteratorResult<WindowedReviewMetadataFrame>> {
		if (this.#previousStreamSequence !== null) {
			this.#controlPort.postMessage({
				kind: 'windowedReview.metadata.processed',
				streamSequence: this.#previousStreamSequence,
			} satisfies WindowedReviewWorkerControlReceipt);
			this.#previousStreamSequence = null;
		}
		const next = await this.#events.next();
		if (!next.done) this.#previousStreamSequence = next.value.streamSequence;
		return next;
	}

	push(frame: WindowedReviewMetadataFrame): void {
		this.#events.push(frame);
	}

	close(): void {
		this.#events.close(true);
	}
}

function isWindowedReviewInstallMessage(
	value: unknown,
): value is Extract<
	WindowedReviewWorkerControlMessage,
	{ readonly kind: 'windowedReview.install' }
> {
	return (
		typeof value === 'object' &&
		value !== null &&
		'kind' in value &&
		value.kind === 'windowedReview.install' &&
		'controlPort' in value &&
		value.controlPort instanceof MessagePort
	);
}

function isWindowedReviewMetadataPublishMessage(
	value: unknown,
): value is Extract<
	WindowedReviewWorkerControlMessage,
	{ readonly kind: 'windowedReview.metadata.publish' }
> {
	return (
		typeof value === 'object' &&
		value !== null &&
		'kind' in value &&
		value.kind === 'windowedReview.metadata.publish' &&
		'frame' in value
	);
}
