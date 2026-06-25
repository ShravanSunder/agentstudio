import { z } from 'zod';

import { dispatchBridgeDevHostAdmittedEnvelope } from '../bridge/bridge-dev-host-push-carrier.js';
import { parseBridgeCoreResourceUrl } from '../core/resources/bridge-resource-url.js';
import { buildReviewSnapshotFrame } from '../features/review/protocol/review-snapshot-frame-builder.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import {
	bridgeReviewPackageSchema,
	type BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-schema.js';

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
	review: new Set(['content']),
};

const bridgeWorktreeReviewPackageResponseSchema = z
	.object({
		reviewPackage: bridgeReviewPackageSchema,
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
	let didReceiveHandshakeRequest = false;
	const handleHandshakeRequest = (): void => {
		didReceiveHandshakeRequest = true;
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push' } }),
		);
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
			if (parsedResourceUrl === null || parsedResourceUrl.resourceKind !== 'content') {
				return new Response('Invalid Bridge worktree review content URL', { status: 400 });
			}
			return await fetch(
				bridgeWorktreeReviewEndpoint(
					`${worktreeReviewContentEndpointPrefix}${encodeURIComponent(parsedResourceUrl.opaqueId)}`,
					bridgeWorktreeReviewContentSearchParams({
						forwardedSearchParams,
						generation: parsedResourceUrl.generation,
					}),
				),
				init,
			);
		},
		pushPackage: async (): Promise<void> => {
			await waitForBridgeWorktreeReviewHandshake((): boolean => didReceiveHandshakeRequest);
			const reviewPackage = await loadWorktreeReviewPackage(forwardedSearchParams);
			dispatchBridgeDevHostAdmittedEnvelope({
				__v: 1,
				__pushId: `push-${reviewPackage.packageId}-${reviewPackage.revision}`,
				__revision: reviewPackage.revision,
				__epoch: reviewPackage.reviewGeneration,
				store: 'diff',
				op: 'replace',
				level: 'cold',
				slice: 'diff_package_metadata',
				data: {
					package: reviewPackage,
					protocolFrame: buildReviewSnapshotFrame({
						package: reviewPackage,
						paneId: bridgeWorktreeReviewPaneId,
						sourceIdentity: reviewPackage.query.queryId,
						streamId: bridgeWorktreeReviewStreamId,
						sequence: reviewPackage.revision,
					}),
				},
			});
			await Promise.resolve();
			await Promise.resolve();
		},
	};
}

async function loadWorktreeReviewPackage(
	forwardedSearchParams: URLSearchParams,
): Promise<BridgeReviewPackage> {
	const response = await fetch(
		bridgeWorktreeReviewEndpoint(worktreeReviewPackageEndpoint, forwardedSearchParams),
	);
	if (!response.ok) {
		throw new Error(`Bridge worktree review package request failed: ${response.status}`);
	}
	return bridgeWorktreeReviewPackageResponseSchema.parse(await response.json()).reviewPackage;
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
	readonly forwardedSearchParams: URLSearchParams;
	readonly generation: number | undefined;
}): URLSearchParams {
	const searchParams = new URLSearchParams(props.forwardedSearchParams);
	if (props.generation !== undefined) {
		searchParams.set('generation', String(props.generation));
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

async function waitForBridgeWorktreeReviewHandshake(
	didReceiveHandshakeRequest: () => boolean,
	remainingAttempts = 180,
): Promise<void> {
	if (didReceiveHandshakeRequest()) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error('Expected Bridge handshake request before Worktree Review package push');
	}
	await Promise.resolve();
	await new Promise<void>((resolve): void => {
		window.requestAnimationFrame((): void => {
			resolve();
		});
	});
	await waitForBridgeWorktreeReviewHandshake(didReceiveHandshakeRequest, remainingAttempts - 1);
}
