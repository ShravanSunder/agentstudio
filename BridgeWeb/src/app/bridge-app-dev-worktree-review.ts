import { z } from 'zod';

import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { parseBridgeCoreResourceUrl } from '../core/resources/bridge-resource-url.js';
import type {
	ReviewMetadataSnapshotFrame,
	ReviewMetadataWindowFrame,
} from '../features/review/models/review-protocol-models.js';
import { reviewProtocolFrameSchema } from '../features/review/models/review-protocol-models.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeTelemetryBootstrapHandshakeConfig } from '../foundation/telemetry/bridge-telemetry-bootstrap-config.js';

export interface BridgeAppDevWorktreeReviewBackend {
	readonly fetchContent: BridgeContentFetch;
	readonly pushMetadata: () => Promise<void>;
}

export interface InstallBridgeAppDevWorktreeReviewBackendProps {
	readonly telemetryConfig?: BridgeTelemetryBootstrapHandshakeConfig;
}

const worktreeReviewMetadataEndpoint = '/__bridge-worktree/review-metadata';
const worktreeReviewContentEndpointPrefix = '/__bridge-worktree/review-content/';
const bridgeWorktreeReviewPaneId = 'bridge-worktree-review-dev-pane';
const bridgeWorktreeReviewStreamId = `review:${bridgeWorktreeReviewPaneId}`;
const bridgeReviewPaneIdAttribute = 'data-bridge-review-pane-id';
const bridgeReviewStreamIdAttribute = 'data-bridge-review-stream-id';
const bridgeWorktreeReviewAllowedResourceKindsByProtocol = {
	review: new Set(['content']),
};

const bridgeWorktreeReviewMetadataResponseSchema = z
	.object({
		protocolFrame: reviewProtocolFrameSchema,
		nextWindowCursor: z.string().min(1).nullable().optional(),
	})
	.strict();

export function installBridgeAppDevWorktreeReviewBackend(
	props: InstallBridgeAppDevWorktreeReviewBackendProps = {},
): BridgeAppDevWorktreeReviewBackend {
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
	let resolveIntakeReplayRequest: (() => void) | null = null;
	const intakeReplayRequestPromise = new Promise<void>((resolve): void => {
		resolveIntakeReplayRequest = resolve;
	});
	let metadataPushPromise: Promise<void> | null = null;
	const handleHandshakeRequest = (): void => {
		document.dispatchEvent(
			new CustomEvent('__bridge_handshake', {
				detail: {
					pushNonce: 'push',
					...(props.telemetryConfig === undefined
						? {}
						: { telemetryConfig: props.telemetryConfig }),
				},
			}),
		);
		resolveHandshakeRequest?.();
		resolveHandshakeRequest = null;
	};
	const handleIntakeReplayRequest = (): void => {
		resolveIntakeReplayRequest?.();
		resolveIntakeReplayRequest = null;
	};
	document.addEventListener('__bridge_handshake_request', handleHandshakeRequest);
	document.addEventListener('__bridge_intake_replay_request', handleIntakeReplayRequest);
	window.addEventListener(
		'beforeunload',
		(): void => {
			document.removeEventListener('__bridge_handshake_request', handleHandshakeRequest);
			document.removeEventListener('__bridge_intake_replay_request', handleIntakeReplayRequest);
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
		pushMetadata: async (): Promise<void> => {
			metadataPushPromise ??= pushWorktreeReviewMetadataAfterHandshake({
				forwardedSearchParams,
				handshakeRequestPromise,
				intakeReplayRequestPromise,
			});
			await metadataPushPromise;
		},
	};
}

async function pushWorktreeReviewMetadataAfterHandshake(props: {
	readonly forwardedSearchParams: URLSearchParams;
	readonly handshakeRequestPromise: Promise<void>;
	readonly intakeReplayRequestPromise: Promise<void>;
}): Promise<void> {
	await props.handshakeRequestPromise;
	await props.intakeReplayRequestPromise;
	for await (const protocolFrame of loadWorktreeReviewMetadataFrames(props.forwardedSearchParams)) {
		dispatchWorktreeReviewMetadataFrame(protocolFrame);
		await Promise.resolve();
	}
	await Promise.resolve();
}

async function* loadWorktreeReviewMetadataFrames(
	forwardedSearchParams: URLSearchParams,
): AsyncGenerator<ReviewMetadataSnapshotFrame | ReviewMetadataWindowFrame> {
	const snapshotResponse = await loadWorktreeReviewMetadataResponse(
		bridgeWorktreeReviewMetadataSearchParams(forwardedSearchParams),
	);
	if (snapshotResponse.protocolFrame.frameKind !== 'review.metadataSnapshot') {
		throw new Error('Bridge worktree review bootstrap returned a non-metadata snapshot frame');
	}
	yield snapshotResponse.protocolFrame;
	let nextWindowCursor = snapshotResponse.nextWindowCursor ?? null;
	while (nextWindowCursor !== null) {
		const windowResponse = await loadWorktreeReviewMetadataResponse(
			bridgeWorktreeReviewMetadataWindowSearchParams({
				cursor: nextWindowCursor,
				forwardedSearchParams,
			}),
		);
		if (windowResponse.protocolFrame.frameKind !== 'review.metadataWindow') {
			throw new Error('Bridge worktree review bootstrap returned a non-metadata window frame');
		}
		yield windowResponse.protocolFrame;
		nextWindowCursor = windowResponse.nextWindowCursor ?? null;
	}
}

async function loadWorktreeReviewMetadataResponse(
	searchParams: URLSearchParams,
): Promise<z.infer<typeof bridgeWorktreeReviewMetadataResponseSchema>> {
	const response = await fetch(
		bridgeWorktreeReviewEndpoint(worktreeReviewMetadataEndpoint, searchParams),
	);
	if (!response.ok) {
		throw new Error(`Bridge worktree review metadata request failed: ${response.status}`);
	}
	return bridgeWorktreeReviewMetadataResponseSchema.parse(await response.json());
}

function bridgeWorktreeReviewMetadataSearchParams(
	forwardedSearchParams: URLSearchParams,
): URLSearchParams {
	const searchParams = new URLSearchParams(forwardedSearchParams);
	searchParams.set('frame', 'review-metadata-snapshot');
	return searchParams;
}

function bridgeWorktreeReviewMetadataWindowSearchParams(props: {
	readonly cursor: string;
	readonly forwardedSearchParams: URLSearchParams;
}): URLSearchParams {
	const searchParams = new URLSearchParams(props.forwardedSearchParams);
	searchParams.set('frame', 'review-metadata-window');
	searchParams.set('cursor', props.cursor);
	return searchParams;
}

function dispatchWorktreeReviewMetadataFrame(
	protocolFrame: ReviewMetadataSnapshotFrame | ReviewMetadataWindowFrame,
): void {
	const intakeFrame: BridgeIntakeFrame = {
		kind: protocolFrame.frameKind === 'review.metadataSnapshot' ? 'snapshot' : 'delta',
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
