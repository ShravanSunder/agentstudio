import { parseBridgeContentResourceUrl } from '../bridge/bridge-resource-url.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import {
	bridgeReviewPackageSchema,
	type BridgeReviewPackageFromSchema,
} from '../foundation/review-package/bridge-review-package-schema.js';

export interface BridgeAppDevWorktreeBackend {
	readonly fetchContent: BridgeContentFetch;
	readonly pushPackage: () => Promise<void>;
}

const bridgeWorktreePushNonce = 'dev-worktree-push-nonce';
const worktreePackageEndpoint = '/__bridge-worktree/package';
const worktreeContentEndpointPrefix = '/__bridge-worktree/content/';

export function installBridgeAppDevWorktreeBackend(): BridgeAppDevWorktreeBackend {
	let didReceiveHandshakeRequest = false;
	const handshakeRequestListener = (): void => {
		didReceiveHandshakeRequest = true;
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: { pushNonce: bridgeWorktreePushNonce },
			}),
		);
	};
	document.addEventListener('__bridge_handshake_request', handshakeRequestListener);
	window.addEventListener(
		'beforeunload',
		(): void => {
			document.removeEventListener('__bridge_handshake_request', handshakeRequestListener);
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
				`${worktreeContentEndpointPrefix}${encodeURIComponent(resourceUrl.handleId)}`,
				init,
			);
		},
		pushPackage: async (): Promise<void> => {
			await waitForBridgeHandshakeRequest((): boolean => didReceiveHandshakeRequest);
			const response = await fetch(worktreePackageEndpoint);
			if (!response.ok) {
				throw new Error(`Bridge worktree package request failed: ${response.status}`);
			}
			const reviewPackage: BridgeReviewPackageFromSchema = bridgeReviewPackageSchema.parse(
				await response.json(),
			);
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: `push-${reviewPackage.packageId}-${reviewPackage.revision}`,
						__revision: reviewPackage.revision,
						__epoch: reviewPackage.reviewGeneration,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						slice: 'diff_package_metadata',
						nonce: bridgeWorktreePushNonce,
						data: { package: reviewPackage },
					},
				}),
			);
		},
	};
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
