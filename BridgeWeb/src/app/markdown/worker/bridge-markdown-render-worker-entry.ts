import { buildBridgeMarkdownRenderWorkerSuccessResponse } from './bridge-markdown-render-worker-renderer.js';
// oxlint-disable unicorn/require-post-message-target-origin -- Dedicated worker postMessage does not accept a targetOrigin argument.
import {
	bridgeMarkdownRenderWorkerAbortRequestSchema,
	bridgeMarkdownRenderWorkerRequestSchema,
	bridgeMarkdownRenderWorkerResponseSchema,
	identityFromMarkdownRenderWorkerRequest,
	markdownRenderIdentitiesMatch,
	type BridgeMarkdownRenderRequestIdentity,
	type BridgeMarkdownRenderWorkerAbortRequest,
	type BridgeMarkdownRenderWorkerFailureResponse,
	type BridgeMarkdownRenderWorkerRequest,
} from './bridge-markdown-render-worker-rpc.js';

const activeIdentityByAbortKey = new Map<string, BridgeMarkdownRenderRequestIdentity>();
const abortedRequestIds = new Set<string>();

self.addEventListener('message', (event: MessageEvent<unknown>): void => {
	const abortRequest = parseAbortMessage(event.data);
	if (abortRequest !== null) {
		abortedRequestIds.add(abortRequest.requestId);
		return;
	}

	const parsedRequest = bridgeMarkdownRenderWorkerRequestSchema.safeParse(event.data);
	if (!parsedRequest.success) {
		return;
	}

	void handleMarkdownRenderRequest(parsedRequest.data);
});

async function handleMarkdownRenderRequest(
	request: BridgeMarkdownRenderWorkerRequest,
): Promise<void> {
	if (request.abortKey !== undefined) {
		activeIdentityByAbortKey.set(
			request.abortKey,
			identityFromMarkdownRenderWorkerRequest(request),
		);
	}
	if (abortedRequestIds.has(request.requestId)) {
		clearActiveRequest(request);
		postMarkdownRenderFailure(request, 'aborted', 'Markdown render request was aborted');
		return;
	}

	try {
		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({ request });
		if (abortedRequestIds.has(request.requestId)) {
			clearActiveRequest(request);
			postMarkdownRenderFailure(request, 'aborted', 'Markdown render request was aborted');
			return;
		}
		clearActiveRequest(request);
		self.postMessage(response);
	} catch {
		clearActiveRequest(request);
		postMarkdownRenderFailure(request, 'renderFailed', 'Markdown render worker failed');
	}
}

function parseAbortMessage(value: unknown): BridgeMarkdownRenderWorkerAbortRequest | null {
	const parsedAbortRequest = bridgeMarkdownRenderWorkerAbortRequestSchema.safeParse(value);
	return parsedAbortRequest.success ? parsedAbortRequest.data : null;
}

function postMarkdownRenderFailure(
	request: BridgeMarkdownRenderWorkerRequest,
	code: BridgeMarkdownRenderWorkerFailureResponse['error']['code'],
	message: string,
): void {
	const response = {
		schemaVersion: 1,
		method: request.method,
		ok: false,
		...identityFromMarkdownRenderWorkerRequest(request),
		error: { code, message },
	} satisfies BridgeMarkdownRenderWorkerFailureResponse;

	self.postMessage(bridgeMarkdownRenderWorkerResponseSchema.parse(response));
}

function clearActiveRequest(request: BridgeMarkdownRenderWorkerRequest): void {
	abortedRequestIds.delete(request.requestId);
	if (request.abortKey === undefined) {
		return;
	}
	if (
		markdownRenderIdentitiesMatch(
			activeIdentityByAbortKey.get(request.abortKey) ?? null,
			identityFromMarkdownRenderWorkerRequest(request),
		)
	) {
		activeIdentityByAbortKey.delete(request.abortKey);
	}
}
