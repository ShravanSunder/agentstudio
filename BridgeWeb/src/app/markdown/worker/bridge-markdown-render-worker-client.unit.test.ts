import { describe, expect, test } from 'vitest';

import {
	createBridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerTransport,
} from './bridge-markdown-render-worker-client.js';
import { buildBridgeMarkdownRenderWorkerSuccessResponse } from './bridge-markdown-render-worker-renderer.js';
import {
	type BridgeMarkdownRenderWorkerAbortRequest,
	type BridgeMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerResponse,
	type BridgeMarkdownSourceIdentity,
} from './bridge-markdown-render-worker-rpc.js';

describe('Bridge markdown render worker client', () => {
	test('drops stale render responses when the same item receives newer content', async () => {
		const deferredResponses: Array<ReturnType<typeof createDeferred<unknown>>> = [];
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const abortedRequests: BridgeMarkdownRenderWorkerAbortRequest[] = [];
		const transport: BridgeMarkdownRenderWorkerTransport = {
			abort: (abortRequest: BridgeMarkdownRenderWorkerAbortRequest): void => {
				abortedRequests.push(abortRequest);
			},
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				capturedRequests.push(request);
				const deferredResponse = createDeferred<unknown>();
				deferredResponses.push(deferredResponse);
				return deferredResponse.promise;
			},
		};
		const client = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => `markdown-request-${capturedRequests.length + 1}`,
		});

		const firstTask = client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 1, fileVersion: 1 }),
			contentCacheKey: 'docs-plan:head:v1',
			contentHash: 'sha256:v1',
			markdownText: '# First',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});
		const secondTask = client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 2, fileVersion: 2 }),
			contentCacheKey: 'docs-plan:head:v2',
			contentHash: 'sha256:v2',
			markdownText: '# Second',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});

		expect(abortedRequests).toEqual([
			expect.objectContaining({
				abortKey: 'markdown-preview',
				requestId: 'markdown-request-1',
			}),
		]);

		const firstRequest = capturedRequests[0];
		const secondRequest = capturedRequests[1];
		if (firstRequest === undefined || secondRequest === undefined) {
			throw new Error('expected captured markdown render requests');
		}
		deferredResponses[0]?.resolve(await successResponseForRequest(firstRequest, '<h1>First</h1>'));
		deferredResponses[1]?.resolve(
			await successResponseForRequest(secondRequest, '<h1>Second</h1>'),
		);

		await expect(firstTask.completed).resolves.toMatchObject({
			status: 'stale',
			reason: 'superseded',
		});
		await expect(secondTask.completed).resolves.toMatchObject({
			status: 'success',
			response: { htmlCandidate: '<h1>Second</h1>' },
		});
	});

	test('aborts the active render lane when selection is cleared', () => {
		const abortedRequests: BridgeMarkdownRenderWorkerAbortRequest[] = [];
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const transport: BridgeMarkdownRenderWorkerTransport = {
			abort: (abortRequest: BridgeMarkdownRenderWorkerAbortRequest): void => {
				abortedRequests.push(abortRequest);
			},
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				capturedRequests.push(request);
				return new Promise<unknown>(() => undefined);
			},
		};
		const client = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-request-1',
		});

		client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 1, fileVersion: 1 }),
			contentCacheKey: 'docs-plan:head:v1',
			contentHash: 'sha256:v1',
			markdownText: '# First',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});
		client.abort('markdown-preview');
		client.abort('markdown-preview');

		expect(capturedRequests).toHaveLength(1);
		expect(abortedRequests).toEqual([
			expect.objectContaining({
				abortKey: 'markdown-preview',
				requestId: 'markdown-request-1',
			}),
		]);
	});

	test('resolves transport failures as typed worker failures', async () => {
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: async (): Promise<unknown> => {
				throw new Error('worker boot failed');
			},
		};
		const client = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-request-1',
		});

		const task = client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 1, fileVersion: 1 }),
			contentCacheKey: 'docs-plan:head:v1',
			contentHash: 'sha256:v1',
			markdownText: '# First',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});

		await expect(task.completed).resolves.toMatchObject({
			status: 'failure',
			response: {
				ok: false,
				error: {
					code: 'transportFailed',
					message: 'worker boot failed',
				},
			},
		});
	});

	test('resolves an invalid active response as a retryable failure', async () => {
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: async (): Promise<unknown> => ({ unexpected: 'response' }),
		};
		const client = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-request-1',
		});

		const task = client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 1, fileVersion: 1 }),
			contentCacheKey: 'docs-plan:head:v1',
			contentHash: 'sha256:v1',
			markdownText: '# First',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});

		await expect(task.completed).resolves.toMatchObject({
			status: 'failure',
			response: {
				ok: false,
				error: {
					code: 'transportFailed',
					message: 'Markdown worker returned an invalid response',
				},
			},
		});
	});

	test('resolves an identity-mismatched active response as a retryable failure', async () => {
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: async (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => ({
				...(await successResponseForRequest(request, '<h1>First</h1>')),
				requestId: 'different-request',
			}),
		};
		const client = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => 'markdown-request-1',
		});

		const task = client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 1, fileVersion: 1 }),
			contentCacheKey: 'docs-plan:head:v1',
			contentHash: 'sha256:v1',
			markdownText: '# First',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});

		await expect(task.completed).resolves.toMatchObject({
			status: 'failure',
			response: {
				ok: false,
				error: {
					code: 'transportFailed',
					message: 'Markdown worker response identity did not match its request',
				},
			},
		});
	});

	test('treats aborted transport failures as stale after a newer render supersedes the lane', async () => {
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const transport: BridgeMarkdownRenderWorkerTransport = {
			abort: (): void => undefined,
			send: (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				capturedRequests.push(request);
				return request.requestId === 'markdown-request-1'
					? Promise.reject(new Error('Markdown render request aborted'))
					: Promise.resolve(successResponseForRequest(request, '<h1>Second</h1>'));
			},
		};
		const client = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => `markdown-request-${capturedRequests.length + 1}`,
		});

		const firstTask = client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 1, fileVersion: 1 }),
			contentCacheKey: 'docs-plan:head:v1',
			contentHash: 'sha256:v1',
			markdownText: '# First',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});
		const secondTask = client.startRender({
			sourceIdentity: fileSourceIdentity({ sourceGeneration: 2, fileVersion: 2 }),
			contentCacheKey: 'docs-plan:head:v2',
			contentHash: 'sha256:v2',
			markdownText: '# Second',
			sourcePath: 'docs/plan.md',
			abortKey: 'markdown-preview',
		});

		await expect(firstTask.completed).resolves.toMatchObject({
			status: 'stale',
			reason: 'superseded',
		});
		await expect(secondTask.completed).resolves.toMatchObject({
			status: 'success',
		});
	});
});

async function successResponseForRequest(
	request: BridgeMarkdownRenderWorkerRequest,
	html: string,
): Promise<BridgeMarkdownRenderWorkerResponse> {
	return await buildBridgeMarkdownRenderWorkerSuccessResponse({
		request,
		renderMarkdown: async () => ({ htmlCandidate: html, mermaidDiagrams: [] }),
	});
}

function fileSourceIdentity(props: {
	readonly sourceGeneration: number;
	readonly fileVersion: number;
}): BridgeMarkdownSourceIdentity {
	return {
		surface: 'file',
		sourceId: 'worktree-1',
		sourceGeneration: props.sourceGeneration,
		fileId: 'docs-plan',
		fileVersion: props.fileVersion,
	};
}

function createDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly resolve: (value: TValue) => void;
	readonly reject: (error: Error) => void;
} {
	let resolve!: (value: TValue) => void;
	let reject!: (error: Error) => void;
	const promise = new Promise<TValue>((promiseResolve, promiseReject): void => {
		resolve = promiseResolve;
		reject = promiseReject;
	});
	return { promise, resolve, reject };
}
