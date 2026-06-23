import { dispatchBridgeDevHostAdmittedEnvelope } from '../bridge/bridge-dev-host-push-carrier.js';
import { parseBridgeContentResourceUrl } from '../bridge/bridge-resource-url.js';
import { buildReviewSnapshotFrame } from '../features/review/protocol/review-snapshot-frame-builder.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import {
	bridgeReviewPackageSchema,
	type BridgeReviewPackageFromSchema,
} from '../foundation/review-package/bridge-review-package-schema.js';
import type { BridgeTelemetryBootstrapHandshakeConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';

export interface BridgeAppDevWorktreeBackend {
	readonly fetchContent: BridgeContentFetch;
	readonly pushPackage: () => Promise<void>;
}

export interface InstallBridgeAppDevWorktreeBackendProps {
	readonly telemetryConfig?: BridgeTelemetryBootstrapHandshakeConfig;
}

const bridgeWorktreePushNonce = 'dev-worktree-push-nonce';
const bridgeWorktreeCommandNonce = 'dev-worktree-command-nonce';
const bridgeWorktreeReviewPaneId = 'bridge-worktree-dev-pane';
const bridgeWorktreeReviewStreamId = `review:${bridgeWorktreeReviewPaneId}`;
const worktreePackageEndpoint = '/__bridge-worktree/package';
const worktreeContentEndpointPrefix = '/__bridge-worktree/content/';
const worktreeForwardedSearchParamNames = ['scenario'] as const;

export function installBridgeAppDevWorktreeBackend(
	props: InstallBridgeAppDevWorktreeBackendProps = {},
): BridgeAppDevWorktreeBackend {
	let didReceiveHandshakeRequest = false;
	const forwardedSearchParams = bridgeWorktreeForwardedSearchParams(window.location.search);
	document.documentElement.setAttribute('data-bridge-nonce', bridgeWorktreeCommandNonce);
	document.documentElement.setAttribute('data-bridge-review-pane-id', bridgeWorktreeReviewPaneId);
	document.documentElement.setAttribute(
		'data-bridge-review-stream-id',
		bridgeWorktreeReviewStreamId,
	);
	const handshakeRequestListener = (): void => {
		didReceiveHandshakeRequest = true;
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: {
					pushNonce: bridgeWorktreePushNonce,
					...(props.telemetryConfig === undefined
						? {}
						: { telemetryConfig: props.telemetryConfig }),
				},
			}),
		);
	};
	document.addEventListener('__bridge_handshake_request', handshakeRequestListener);
	window.addEventListener(
		'beforeunload',
		(): void => {
			document.removeEventListener('__bridge_handshake_request', handshakeRequestListener);
			document.documentElement.removeAttribute('data-bridge-nonce');
			document.documentElement.removeAttribute('data-bridge-review-pane-id');
			document.documentElement.removeAttribute('data-bridge-review-stream-id');
		},
		{ once: true },
	);
	return {
		fetchContent: async (url: string, init?: RequestInit): Promise<Response> => {
			const resourceUrl = parseBridgeContentResourceUrl(url);
			if (resourceUrl === null) {
				return new Response(`Invalid Bridge worktree content URL: ${url}`, { status: 400 });
			}
			return await fetch(
				bridgeWorktreeEndpoint(
					`${worktreeContentEndpointPrefix}${encodeURIComponent(resourceUrl.handleId)}`,
					bridgeWorktreeContentSearchParams({
						forwardedSearchParams,
						resourceUrl: url,
					}),
				),
				init,
			);
		},
		pushPackage: async (): Promise<void> => {
			await waitForBridgeHandshakeRequest((): boolean => didReceiveHandshakeRequest);
			const response = await fetch(
				bridgeWorktreeEndpoint(worktreePackageEndpoint, forwardedSearchParams),
			);
			if (!response.ok) {
				throw new Error(`Bridge worktree package request failed: ${response.status}`);
			}
			const reviewPackage: BridgeReviewPackageFromSchema = bridgeReviewPackageSchema.parse(
				await response.json(),
			);
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
		},
	};
}

export function bridgeWorktreeForwardedSearchParams(search: string): URLSearchParams {
	const sourceSearchParams = new URLSearchParams(search);
	const forwardedSearchParams = new URLSearchParams();
	for (const searchParamName of worktreeForwardedSearchParamNames) {
		const value = sourceSearchParams.get(searchParamName);
		if (value !== null && value.length > 0) {
			forwardedSearchParams.set(searchParamName, value);
		}
	}
	return forwardedSearchParams;
}

function bridgeWorktreeContentSearchParams(props: {
	readonly forwardedSearchParams: URLSearchParams;
	readonly resourceUrl: string;
}): URLSearchParams {
	const contentSearchParams = new URLSearchParams(props.forwardedSearchParams);
	const parsedResourceUrl = new URL(props.resourceUrl);
	const generation = parsedResourceUrl.searchParams.get('generation');
	const revision = parsedResourceUrl.searchParams.get('revision');
	if (generation !== null) {
		contentSearchParams.set('generation', generation);
	}
	if (revision !== null) {
		contentSearchParams.set('revision', revision);
	}
	return contentSearchParams;
}

function bridgeWorktreeEndpoint(path: string, searchParams: URLSearchParams): string {
	const query = searchParams.toString();
	return query.length === 0 ? path : `${path}?${query}`;
}

async function waitForBridgeHandshakeRequest(
	didReceiveHandshakeRequest: () => boolean,
	remainingAttempts = 180,
): Promise<void> {
	if (didReceiveHandshakeRequest()) {
		return;
	}
	if (remainingAttempts <= 0) {
		throw new Error('expected Bridge handshake request before worktree package push');
	}
	await Promise.resolve();
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => resolve());
	});
	await waitForBridgeHandshakeRequest(didReceiveHandshakeRequest, remainingAttempts - 1);
}
