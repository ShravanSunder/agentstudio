import { afterEach, describe, expect, test, vi } from 'vitest';

import { makeBridgeReviewProjectionInput } from '../../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../../test-support/review-viewer-fixtures.js';
import { createBridgeReviewProjectionWebWorkerClient } from './review-projection-worker-transport.js';

describe('Bridge review projection web worker transport', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
		RecordingProjectionWorker.constructedUrls = [];
	});

	test('creates the default module worker from the Vite-served entrypoint', () => {
		vi.stubGlobal('Worker', RecordingProjectionWorker);
		const client = createBridgeReviewProjectionWebWorkerClient();

		expect(client).not.toBeNull();
		expect(RecordingProjectionWorker.constructedUrls).toEqual([]);

		const reviewPackage = makeBridgeViewerProjectionFixture();
		client?.startProjection({
			projectionInput: makeBridgeReviewProjectionInput(reviewPackage),
			projectionRequest: { base: { kind: 'allFiles' }, refinements: [] },
			visibleItemIds: [],
			workloadId: 'interactive',
		});

		expect(RecordingProjectionWorker.constructedUrls[0]?.pathname).toMatch(
			/review-projection-worker-entry\.ts$/u,
		);
	});

	test('rejects pending projection requests when the worker posts a malformed response', async () => {
		vi.stubGlobal('Worker', FakeProjectionWorker);
		const fakeWorker = new FakeProjectionWorker();
		const client = createBridgeReviewProjectionWebWorkerClient({
			createRequestId: (): string => 'request-invalid-response',
			workerFactory: (): Worker => fakeWorker,
		});
		if (client === null) {
			throw new Error('expected worker client');
		}
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const task = client.startProjection({
			projectionInput: makeBridgeReviewProjectionInput(reviewPackage),
			projectionRequest: { base: { kind: 'allFiles' }, refinements: [] },
			visibleItemIds: [],
			workloadId: 'interactive',
		});

		fakeWorker.emitMessage({ schemaVersion: 1, ok: true, requestId: task.identity.requestId });

		await expect(task.completed).rejects.toThrow('Projection worker sent invalid response');
	});

	test('rejects pending projection requests when the worker error event has no message', async () => {
		vi.stubGlobal('Worker', FakeProjectionWorker);
		const fakeWorker = new FakeProjectionWorker();
		const client = createBridgeReviewProjectionWebWorkerClient({
			createRequestId: (): string => 'request-error-without-message',
			workerFactory: (): Worker => fakeWorker,
		});
		if (client === null) {
			throw new Error('expected worker client');
		}
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const task = client.startProjection({
			projectionInput: makeBridgeReviewProjectionInput(reviewPackage),
			projectionRequest: { base: { kind: 'allFiles' }, refinements: [] },
			visibleItemIds: [],
			workloadId: 'interactive',
		});

		expect(() => {
			fakeWorker.emitError(new Event('error'));
		}).not.toThrow();

		await expect(task.completed).rejects.toThrow('Projection worker failed');
	});
});

class FakeProjectionWorker extends EventTarget implements Worker {
	onmessage: ((this: Worker, event: MessageEvent) => void) | null = null;
	onmessageerror: ((this: Worker, event: MessageEvent) => void) | null = null;
	onerror: ((this: AbstractWorker, event: ErrorEvent) => void) | null = null;

	override addEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void;
	override addEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | AddEventListenerOptions,
	): void {
		super.addEventListener(type, listener, options);
	}

	override removeEventListener<KEventName extends keyof WorkerEventMap>(
		type: KEventName,
		listener: (this: Worker, event: WorkerEventMap[KEventName]) => void,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void;
	override removeEventListener(
		type: string,
		listener: EventListenerOrEventListenerObject | null,
		options?: boolean | EventListenerOptions,
	): void {
		super.removeEventListener(type, listener, options);
	}

	postMessage(message: unknown, transfer: Transferable[]): void;
	postMessage(message: unknown, options?: StructuredSerializeOptions): void;
	postMessage(): void {}

	terminate(): void {}

	emitMessage(data: unknown): void {
		this.dispatchEvent(new MessageEvent('message', { data }));
	}

	emitError(event: Event): void {
		this.dispatchEvent(event);
	}
}

class RecordingProjectionWorker extends FakeProjectionWorker {
	static constructedUrls: URL[] = [];

	constructor(scriptURL: string | URL, _options?: WorkerOptions) {
		super();
		RecordingProjectionWorker.constructedUrls.push(new URL(scriptURL));
	}
}
