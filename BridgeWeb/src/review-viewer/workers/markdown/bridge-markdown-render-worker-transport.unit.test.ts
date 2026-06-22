import { afterEach, describe, expect, test, vi } from 'vitest';

import type { StartBridgeMarkdownRenderWorkerTaskProps } from './bridge-markdown-render-worker-client.js';
import type {
	BridgeMarkdownRenderWorkerRequest,
	BridgeMarkdownRenderWorkerResponse,
} from './bridge-markdown-render-worker-rpc.js';
import { createBridgeMarkdownRenderWebWorkerClient } from './bridge-markdown-render-worker-transport.js';

describe('Bridge markdown render web worker transport', () => {
	afterEach(() => {
		vi.unstubAllGlobals();
	});

	test('posts cooperative abort requests without terminating the warm worker', async () => {
		vi.stubGlobal('Worker', FakeMarkdownWorker);
		const fakeWorker = new FakeMarkdownWorker();
		let nextRequestId = 0;
		const client = createBridgeMarkdownRenderWebWorkerClient({
			createRequestId: (): string => `markdown-request-${(nextRequestId += 1).toString()}`,
			workerFactory: (): Worker => fakeWorker,
		});
		if (client === null) {
			throw new Error('expected markdown worker client');
		}

		const firstTask = client.startRender(
			makeMarkdownRenderTaskProps({ sourcePath: 'docs/one.md' }),
		);
		await flushMarkdownWorkerTransportMicrotasks();
		const secondTask = client.startRender(
			makeMarkdownRenderTaskProps({ sourcePath: 'docs/two.md' }),
		);
		await flushMarkdownWorkerTransportMicrotasks();
		const secondRequest = fakeWorker.postedMessages.find(
			(message: unknown): message is BridgeMarkdownRenderWorkerRequest =>
				isRecord(message) && message['requestId'] === secondTask.identity.requestId,
		);
		if (secondRequest === undefined) {
			throw new Error('expected second markdown request');
		}
		fakeWorker.emitMessage(successResponseForRequest(secondRequest));

		const firstCompletion = await firstTask.completed;
		const secondCompletion = await secondTask.completed;

		expect(fakeWorker.terminateCount).toBe(0);
		expect(fakeWorker.postedMessages).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					method: 'markdown.render.abort',
					requestId: firstTask.identity.requestId,
					abortKey: 'selected-markdown',
				}),
			]),
		);
		expect(firstCompletion.status).toBe('stale');
		expect(secondCompletion.status).toBe('success');
	});
});

interface MakeMarkdownRenderTaskProps {
	readonly sourcePath: string;
}

function makeMarkdownRenderTaskProps(
	props: MakeMarkdownRenderTaskProps,
): StartBridgeMarkdownRenderWorkerTaskProps {
	return {
		packageId: 'package-1',
		reviewGeneration: 1,
		revision: 1,
		itemId: props.sourcePath,
		itemVersion: 1,
		contentCacheKey: `${props.sourcePath}:head`,
		contentHash: `${props.sourcePath}:hash`,
		markdownText: '# Heading',
		sourcePath: props.sourcePath,
		abortKey: 'selected-markdown',
	};
}

function successResponseForRequest(
	request: BridgeMarkdownRenderWorkerRequest,
): BridgeMarkdownRenderWorkerResponse {
	return {
		schemaVersion: 1,
		method: 'markdown.render',
		ok: true,
		requestId: request.requestId,
		packageId: request.packageId,
		reviewGeneration: request.reviewGeneration,
		revision: request.revision,
		itemId: request.itemId,
		itemVersion: request.itemVersion,
		contentCacheKey: request.contentCacheKey,
		contentHash: request.contentHash,
		abortKey: request.abortKey,
		html: '<h1>Heading</h1>',
		metrics: {
			durationMilliseconds: 1,
			inputBytes: 9,
			outputBytes: 16,
		},
	};
}

class FakeMarkdownWorker extends EventTarget implements Worker {
	onmessage: ((this: Worker, event: MessageEvent) => void) | null = null;
	onmessageerror: ((this: Worker, event: MessageEvent) => void) | null = null;
	onerror: ((this: AbstractWorker, event: ErrorEvent) => void) | null = null;
	readonly postedMessages: unknown[] = [];
	terminateCount = 0;

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
	postMessage(message?: unknown): void {
		this.postedMessages.push(message);
	}

	terminate(): void {
		this.terminateCount += 1;
	}

	emitMessage(data: unknown): void {
		this.dispatchEvent(new MessageEvent('message', { data }));
	}
}

async function flushMarkdownWorkerTransportMicrotasks(): Promise<void> {
	await Promise.resolve();
	await Promise.resolve();
	await Promise.resolve();
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}
