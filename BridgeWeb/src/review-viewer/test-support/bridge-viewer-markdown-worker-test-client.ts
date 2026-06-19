import {
	createBridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerTransport,
} from '../workers/markdown/bridge-markdown-render-worker-client.js';
import {
	identityFromMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerAbortRequest,
	type BridgeMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerResponse,
} from '../workers/markdown/bridge-markdown-render-worker-rpc.js';

export interface ImmediateMarkdownWorkerClient {
	readonly client: BridgeMarkdownRenderWorkerClient;
	readonly requests: readonly BridgeMarkdownRenderWorkerRequest[];
}

export interface DeferredMarkdownWorkerPendingRequest {
	readonly request: BridgeMarkdownRenderWorkerRequest;
	readonly resolve: (response: BridgeMarkdownRenderWorkerResponse) => void;
}

export interface DeferredMarkdownWorkerClient {
	readonly client: BridgeMarkdownRenderWorkerClient;
	readonly abortedRequests: readonly BridgeMarkdownRenderWorkerAbortRequest[];
	readonly waitForPendingRequest: () => Promise<DeferredMarkdownWorkerPendingRequest>;
}

export function createImmediateMarkdownWorkerClient(): ImmediateMarkdownWorkerClient {
	const requests: BridgeMarkdownRenderWorkerRequest[] = [];
	const transport: BridgeMarkdownRenderWorkerTransport = {
		abort: (): void => {},
		send: (
			request: BridgeMarkdownRenderWorkerRequest,
		): Promise<BridgeMarkdownRenderWorkerResponse> => {
			requests.push(request);
			return Promise.resolve(markdownResponseForRequest(request));
		},
	};
	return {
		client: createBridgeMarkdownRenderWorkerClient({
			createRequestId: (): string => `browser-markdown-${requests.length + 1}`,
			transport,
		}),
		requests,
	};
}

export function createDeferredMarkdownWorkerClient(props: {
	readonly waitForAnimationFrame: () => Promise<void>;
}): DeferredMarkdownWorkerClient {
	const pendingRequests: DeferredMarkdownWorkerPendingRequest[] = [];
	const abortedRequests: BridgeMarkdownRenderWorkerAbortRequest[] = [];
	const transport: BridgeMarkdownRenderWorkerTransport = {
		abort: (request: BridgeMarkdownRenderWorkerAbortRequest): void => {
			abortedRequests.push(request);
		},
		send: (
			request: BridgeMarkdownRenderWorkerRequest,
		): Promise<BridgeMarkdownRenderWorkerResponse> =>
			new Promise<BridgeMarkdownRenderWorkerResponse>((resolve): void => {
				pendingRequests.push({ request, resolve });
			}),
	};
	const waitForPendingRequest = async (
		attempt: number,
	): Promise<DeferredMarkdownWorkerPendingRequest> => {
		const pendingRequest = pendingRequests[0];
		if (pendingRequest !== undefined) {
			return pendingRequest;
		}
		if (attempt >= 180) {
			throw new Error('expected pending markdown worker request');
		}
		await props.waitForAnimationFrame();
		return await waitForPendingRequest(attempt + 1);
	};
	return {
		client: createBridgeMarkdownRenderWorkerClient({
			createRequestId: (): string => `browser-markdown-${pendingRequests.length + 1}`,
			transport,
		}),
		abortedRequests,
		waitForPendingRequest: async (): Promise<DeferredMarkdownWorkerPendingRequest> =>
			await waitForPendingRequest(0),
	};
}

export function markdownResponseForRequest(
	request: BridgeMarkdownRenderWorkerRequest,
): BridgeMarkdownRenderWorkerResponse {
	const html = [
		'<h1>Browser fixture</h1>',
		'<p>Rendered markdown preview</p>',
		'<pre><code><span style="color: #79c0ff">const fixture = true;</span></code></pre>',
		'<a href="javascript:alert(1)">unsafe link</a>',
		'<img src="https://example.com/unsafe.png" alt="unsafe" />',
		'<form action="/unsafe"><input autofocus value="secret"><button onclick="alert(1)">Run</button></form>',
		'<details open><summary>Reveal</summary><p>Hidden text</p></details>',
		'<dialog open>Modal</dialog>',
		'<p contenteditable="true" tabindex="0">editable</p>',
	].join('');
	return {
		schemaVersion: 1,
		method: 'markdown.render',
		ok: true,
		...identityFromMarkdownRenderWorkerRequest(request),
		html,
		metrics: {
			durationMilliseconds: 2,
			inputBytes: request.markdownText.length,
			outputBytes: html.length,
		},
	};
}
