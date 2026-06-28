import { z } from 'zod';

import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { parseBridgeCoreResourceUrl } from '../core/resources/bridge-resource-url.js';
import type { ReviewSnapshotFrame } from '../features/review/models/review-protocol-models.js';
import { reviewProtocolFrameSchema } from '../features/review/models/review-protocol-models.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';

export interface BridgeAppDevWorktreeReviewBackend {
	readonly fetchContent: BridgeContentFetch;
	readonly pushPackage: () => Promise<void>;
}

const worktreeReviewPackageEndpoint = '/__bridge-worktree/review-package';
const worktreeReviewContentEndpointPrefix = '/__bridge-worktree/review-content/';
const bridgeWorktreeReviewPaneId = 'bridge-worktree-review-dev-pane';
const bridgeWorktreeReviewStreamId = `review:${bridgeWorktreeReviewPaneId}`;
const bridgeReviewPaneIdAttribute = 'data-bridge-review-pane-id';
const bridgeReviewStreamIdAttribute = 'data-bridge-review-stream-id';
const bridgeWorktreeReviewAllowedResourceKindsByProtocol = {
	review: new Set(['content', 'review-package', 'review-delta']),
};

const bridgeWorktreeReviewSnapshotResponseSchema = z
	.object({
		protocolFrame: reviewProtocolFrameSchema,
	})
	.strict();

export function installBridgeAppDevWorktreeReviewBackend(): BridgeAppDevWorktreeReviewBackend {
	const forwardedSearchParams = bridgeWorktreeReviewForwardedSearchParams(window.location.search);
	const previousPaneId = document.documentElement.getAttribute(bridgeReviewPaneIdAttribute);
	const previousStreamId = document.documentElement.getAttribute(bridgeReviewStreamIdAttribute);
	document.documentElement.setAttribute(bridgeReviewPaneIdAttribute, bridgeWorktreeReviewPaneId);
	document.documentElement.setAttribute(
		bridgeReviewStreamIdAttribute,
		bridgeWorktreeReviewStreamId,
	);
	let resolveHandshakeRequest: (() => void) | null = null;
	const handshakeRequestPromise = new Promise<void>((resolve): void => {
		resolveHandshakeRequest = resolve;
	});
	let packagePushPromise: Promise<void> | null = null;
	const handleHandshakeRequest = (): void => {
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push' } }),
		);
		resolveHandshakeRequest?.();
		resolveHandshakeRequest = null;
	};
	document.addEventListener('__bridge_handshake_request', handleHandshakeRequest);
	window.addEventListener(
		'beforeunload',
		(): void => {
			document.removeEventListener('__bridge_handshake_request', handleHandshakeRequest);
			restoreDocumentElementAttribute(bridgeReviewPaneIdAttribute, previousPaneId);
			restoreDocumentElementAttribute(bridgeReviewStreamIdAttribute, previousStreamId);
		},
		{ once: true },
	);

	return {
		fetchContent: async (url: string, init?: RequestInit): Promise<Response> => {
			const parsedResourceUrl = parseBridgeCoreResourceUrl(url, {
				allowedResourceKindsByProtocol: bridgeWorktreeReviewAllowedResourceKindsByProtocol,
			});
			if (parsedResourceUrl === null) {
				return new Response('Invalid Bridge worktree review content URL', {
					status: 400,
				});
			}
			if (
				parsedResourceUrl.resourceKind === 'review-package' ||
				parsedResourceUrl.resourceKind === 'review-delta'
			) {
				return await fetchWorktreeReviewProtocolResource({
					forwardedSearchParams,
					init,
					opaqueId: parsedResourceUrl.opaqueId,
					resourceKind: parsedResourceUrl.resourceKind,
					generation: parsedResourceUrl.generation,
					revision: parsedResourceUrl.revision,
				});
			}
			if (parsedResourceUrl.resourceKind !== 'content') {
				return new Response('Invalid Bridge worktree review content URL', {
					status: 400,
				});
			}
			return await fetch(
				bridgeWorktreeReviewEndpoint(
					`${worktreeReviewContentEndpointPrefix}${encodeURIComponent(parsedResourceUrl.opaqueId)}`,
					bridgeWorktreeReviewContentSearchParams({
						cursor: parsedResourceUrl.cursor,
						forwardedSearchParams,
						generation: parsedResourceUrl.generation,
						revision: parsedResourceUrl.revision,
					}),
				),
				init,
			);
		},
		pushPackage: async (): Promise<void> => {
			packagePushPromise ??= pushWorktreeReviewPackageAfterHandshake({
				forwardedSearchParams,
				handshakeRequestPromise,
			});
			await packagePushPromise;
		},
	};
}

async function fetchWorktreeReviewProtocolResource(props: {
	readonly forwardedSearchParams: URLSearchParams;
	readonly generation: number | undefined;
	readonly init?: RequestInit | undefined;
	readonly opaqueId: string;
	readonly resourceKind: 'review-package' | 'review-delta';
	readonly revision: number | undefined;
}): Promise<Response> {
	return await fetch(
		bridgeWorktreeReviewEndpoint(
			worktreeReviewPackageEndpoint,
			bridgeWorktreeReviewPackageResourceSearchParams({
				forwardedSearchParams: props.forwardedSearchParams,
				generation: props.generation,
				opaqueId: props.opaqueId,
				resourceKind: props.resourceKind,
				revision: props.revision,
			}),
		),
		props.init,
	);
}

async function pushWorktreeReviewPackageAfterHandshake(props: {
	readonly forwardedSearchParams: URLSearchParams;
	readonly handshakeRequestPromise: Promise<void>;
}): Promise<void> {
	await props.handshakeRequestPromise;
	const protocolFrame = await loadWorktreeReviewSnapshotFrame(props.forwardedSearchParams);
	const intakeFrame: BridgeIntakeFrame = {
		kind: 'snapshot',
		streamId: protocolFrame.streamId,
		generation: protocolFrame.generation,
		sequence: protocolFrame.sequence,
		payload: protocolFrame,
	};
	document.dispatchEvent(
		new CustomEvent('__bridge_intake_json', {
			detail: {
				json: JSON.stringify(intakeFrame),
				nonce: 'push',
			},
		}),
	);
	await Promise.resolve();
	await Promise.resolve();
}

async function loadWorktreeReviewSnapshotFrame(
	forwardedSearchParams: URLSearchParams,
): Promise<ReviewSnapshotFrame> {
	const response = await fetch(
		bridgeWorktreeReviewEndpoint(
			worktreeReviewPackageEndpoint,
			bridgeWorktreeReviewSnapshotSearchParams(forwardedSearchParams),
		),
	);
	if (!response.ok) {
		throw new Error(`Bridge worktree review snapshot request failed: ${response.status}`);
	}
	const parsed = bridgeWorktreeReviewSnapshotResponseSchema.parse(await response.json());
	if (parsed.protocolFrame.frameKind !== 'review.snapshot') {
		throw new Error('Bridge worktree review bootstrap returned a non-snapshot frame');
	}
	return parsed.protocolFrame;
}

function bridgeWorktreeReviewSnapshotSearchParams(
	forwardedSearchParams: URLSearchParams,
): URLSearchParams {
	const searchParams = new URLSearchParams(forwardedSearchParams);
	searchParams.set('frame', 'review-snapshot');
	return searchParams;
}

function bridgeWorktreeReviewForwardedSearchParams(search: string): URLSearchParams {
	const incomingSearchParams = new URLSearchParams(search);
	const forwardedSearchParams = new URLSearchParams();
	const scenario = incomingSearchParams.get('scenario');
	if (scenario !== null) {
		forwardedSearchParams.set('scenario', scenario);
	}
	return forwardedSearchParams;
}

function bridgeWorktreeReviewContentSearchParams(props: {
	readonly cursor: string | undefined;
	readonly forwardedSearchParams: URLSearchParams;
	readonly generation: number | undefined;
	readonly revision: number | undefined;
}): URLSearchParams {
	const searchParams = new URLSearchParams(props.forwardedSearchParams);
	if (props.cursor !== undefined) {
		searchParams.set('cursor', props.cursor);
	}
	if (props.generation !== undefined) {
		searchParams.set('generation', String(props.generation));
	}
	if (props.revision !== undefined) {
		searchParams.set('revision', String(props.revision));
	}
	return searchParams;
}

function bridgeWorktreeReviewPackageResourceSearchParams(props: {
	readonly forwardedSearchParams: URLSearchParams;
	readonly generation: number | undefined;
	readonly opaqueId: string;
	readonly resourceKind: 'review-package' | 'review-delta';
	readonly revision: number | undefined;
}): URLSearchParams {
	const searchParams = new URLSearchParams(props.forwardedSearchParams);
	searchParams.set('resource', props.resourceKind);
	searchParams.set('opaqueId', props.opaqueId);
	if (props.generation !== undefined) {
		searchParams.set('generation', String(props.generation));
	}
	if (props.revision !== undefined) {
		searchParams.set('revision', String(props.revision));
	}
	return searchParams;
}

function bridgeWorktreeReviewEndpoint(path: string, searchParams: URLSearchParams): string {
	const query = searchParams.toString();
	return query.length === 0 ? path : `${path}?${query}`;
}

function restoreDocumentElementAttribute(name: string, previousValue: string | null): void {
	if (previousValue === null) {
		document.documentElement.removeAttribute(name);
		return;
	}
	document.documentElement.setAttribute(name, previousValue);
}
