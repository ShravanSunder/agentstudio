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

	test('terminates the worker and rejects pending work when disposed', async () => {
		vi.stubGlobal('Worker', FakeMarkdownWorker);
		const fakeWorker = new FakeMarkdownWorker();
		const client = createBridgeMarkdownRenderWebWorkerClient({
			createRequestId: (): string => 'markdown-request-dispose',
			workerFactory: (): Worker => fakeWorker,
		});
		if (client === null) {
			throw new Error('expected markdown worker client');
		}

		const task = client.startRender(makeMarkdownRenderTaskProps({ sourcePath: 'docs/dispose.md' }));
		await flushMarkdownWorkerTransportMicrotasks();
		client.dispose();

		expect(fakeWorker.terminateCount).toBe(1);
		await expect(task.completed).resolves.toMatchObject({ status: 'stale', reason: 'disposed' });
	});

	test('constructs a fresh worker after the first factory attempt rejects', async () => {
		vi.stubGlobal('Worker', FakeMarkdownWorker);
		const recoveredWorker = new FakeMarkdownWorker();
		let factoryAttemptCount = 0;
		const client = createBridgeMarkdownRenderWebWorkerClient({
			createRequestId: (): string =>
				`markdown-request-retry-${(factoryAttemptCount + 1).toString()}`,
			workerFactory: async (): Promise<Worker> => {
				factoryAttemptCount += 1;
				if (factoryAttemptCount === 1) throw new Error('initial worker load failed');
				return recoveredWorker;
			},
		});
		if (client === null) throw new Error('expected markdown worker client');

		const firstTask = client.startRender(
			makeMarkdownRenderTaskProps({ sourcePath: 'docs/retry.md' }),
		);
		await expect(firstTask.completed).resolves.toMatchObject({ status: 'failure' });
		const secondTask = client.startRender(
			makeMarkdownRenderTaskProps({ sourcePath: 'docs/retry.md' }),
		);
		await flushMarkdownWorkerTransportMicrotasks();
		const secondRequest = recoveredWorker.postedMessages.find(
			(message: unknown): message is BridgeMarkdownRenderWorkerRequest =>
				isRecord(message) && message['requestId'] === secondTask.identity.requestId,
		);
		if (secondRequest === undefined) throw new Error('expected retried markdown request');
		recoveredWorker.emitMessage(successResponseForRequest(secondRequest));

		await expect(secondTask.completed).resolves.toMatchObject({ status: 'success' });
		expect(factoryAttemptCount).toBe(2);
	});

	test('terminates a worker that resolves after disposal without posting work', async () => {
		vi.stubGlobal('Worker', FakeMarkdownWorker);
		const deferredWorker = deferredMarkdownWorker();
		const client = createBridgeMarkdownRenderWebWorkerClient({
			createRequestId: (): string => 'markdown-request-pending-disposal',
			workerFactory: (): Promise<Worker> => deferredWorker.promise,
		});
		if (client === null) throw new Error('expected markdown worker client');

		const task = client.startRender(
			makeMarkdownRenderTaskProps({ sourcePath: 'docs/pending-disposal.md' }),
		);
		client.dispose();
		const resolvedWorker = new FakeMarkdownWorker();
		deferredWorker.resolve(resolvedWorker);
		await flushMarkdownWorkerTransportMicrotasks();

		await expect(task.completed).resolves.toMatchObject({ status: 'stale', reason: 'disposed' });
		expect(resolvedWorker.terminateCount).toBe(1);
		expect(resolvedWorker.postedMessages).toEqual([]);
	});
});

interface MakeMarkdownRenderTaskProps {
	readonly sourcePath: string;
}

function makeMarkdownRenderTaskProps(
	props: MakeMarkdownRenderTaskProps,
): StartBridgeMarkdownRenderWorkerTaskProps {
	return {
		sourceIdentity: {
			surface: 'file',
			sourceId: 'worktree-1',
			sourceGeneration: 1,
			fileId: props.sourcePath,
			fileVersion: 1,
		},
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
		sourceIdentity: request.sourceIdentity,
		contentCacheKey: request.contentCacheKey,
		contentHash: request.contentHash,
		abortKey: request.abortKey,
		htmlCandidate: '<h1>Heading</h1>',
		mermaidDiagrams: [],
		metrics: {
			durationMilliseconds: 1,
			inputBytes: 9,
			outputBytes: 16,
			mermaidDiagramCount: 0,
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

function deferredMarkdownWorker(): {
	readonly promise: Promise<Worker>;
	readonly resolve: (worker: Worker) => void;
} {
	let resolveWorker: ((worker: Worker) => void) | null = null;
	const promise = new Promise<Worker>((resolve): void => {
		resolveWorker = resolve;
	});
	return {
		promise,
		resolve: (worker): void => {
			if (resolveWorker === null) throw new Error('expected deferred worker resolver');
			resolveWorker(worker);
		},
	};
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}
