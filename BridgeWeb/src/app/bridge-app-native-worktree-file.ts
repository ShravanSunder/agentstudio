import { z } from 'zod';

import { readBridgeTextResourceStream } from '../core/resources/bridge-resource-stream.js';
import {
	worktreeFileProtocolFrameSchema,
	worktreeFileSurfaceSourceSpecSchema,
	type WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type {
	WorktreeFileFrameSubscriber,
	WorktreeFileFrameSubscriptionDispose,
	WorktreeFileInitialSurface,
	WorktreeFileSurfaceProvenance,
} from '../worktree-file-surface/worktree-file-app.js';
import type {
	WorktreeFileSurfaceRuntimeFetchedResource,
	WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';

export interface BridgeAppNativeWorktreeFileBackend {
	readonly fetchWorktreeFileResource: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly loadWorktreeFileSurface: () => Promise<WorktreeFileInitialSurface>;
	readonly subscribeWorktreeFileFrames: (
		subscriber: WorktreeFileFrameSubscriber,
	) => WorktreeFileFrameSubscriptionDispose;
	readonly dispose: () => void;
}

export interface CreateBridgeAppNativeWorktreeFileBackendProps {
	readonly target?: Document;
	readonly createRequestId?: () => string;
	readonly fetchResource?: typeof fetch;
	readonly responseTimeoutMilliseconds?: number;
	readonly maxFrameBytes?: number;
}

const nativeWorktreeFileSourceSpecAttribute = 'data-bridge-worktree-file-source-spec';
const nativeWorktreeFileOpenSourceStreamMethod = 'worktreeFileSurface.openSourceStream';
const defaultResponseTimeoutMilliseconds = 10_000;
const defaultMaxFrameBytes = 8 * 1024 * 1024;

const bridgeRPCResponseSchema = z
	.object({
		id: z.union([z.string(), z.number()]),
		result: z.unknown().optional(),
		error: z.unknown().optional(),
	})
	.passthrough();

export function createBridgeAppNativeWorktreeFileBackend(
	props: CreateBridgeAppNativeWorktreeFileBackendProps = {},
): BridgeAppNativeWorktreeFileBackend | null {
	const target = props.target ?? document;
	const sourceSpec = readNativeWorktreeFileSourceSpec(target);
	if (sourceSpec === null) {
		return null;
	}

	const subscribers = new Set<WorktreeFileFrameSubscriber>();
	const pendingFrames: WorktreeFileProtocolFrame[] = [];
	let pushNonce: string | null = null;
	let disposeIntakeListener: (() => void) | null = null;
	let isDisposed = false;

	const publishFrames = (frames: readonly WorktreeFileProtocolFrame[]): void => {
		if (subscribers.size === 0) {
			pendingFrames.push(...frames);
			return;
		}
		for (const subscriber of subscribers) {
			subscriber(frames);
		}
	};

	const installIntakeListener = (streamIdentity: {
		readonly streamId: string;
		readonly generation: number;
	}): void => {
		disposeIntakeListener?.();
		const handleIntake = (event: Event): void => {
			const expectedPushNonce = pushNonce;
			if (expectedPushNonce === null) {
				return;
			}
			const detail = extractEventDetail(event);
			if (!eventDetailHasNonceAndJSON(detail, expectedPushNonce)) {
				return;
			}
			if (
				new TextEncoder().encode(detail.json).byteLength >
				(props.maxFrameBytes ?? defaultMaxFrameBytes)
			) {
				return;
			}
			const frame = parseWorktreeFileFrame(detail.json);
			if (
				frame === null ||
				frame.streamId !== streamIdentity.streamId ||
				frame.generation !== streamIdentity.generation
			) {
				return;
			}
			publishFrames([frame]);
		};
		target.addEventListener('__bridge_intake_json', handleIntake);
		disposeIntakeListener = (): void => {
			target.removeEventListener('__bridge_intake_json', handleIntake);
		};
	};

	const handleHandshake = (event: Event): void => {
		const detail = extractEventDetail(event);
		if (typeof detail === 'object' && detail !== null && 'pushNonce' in detail) {
			const nextPushNonce = detail.pushNonce;
			if (typeof nextPushNonce === 'string' && nextPushNonce.length > 0) {
				pushNonce = nextPushNonce;
			}
		}
	};
	target.addEventListener('__bridge_handshake', handleHandshake);
	target.dispatchEvent(new CustomEvent('__bridge_handshake_request'));

	return {
		fetchWorktreeFileResource: async (
			resourceProps: WorktreeFileSurfaceRuntimeFetchResourceProps,
		): Promise<WorktreeFileSurfaceRuntimeFetchedResource> => {
			const fetchResource = props.fetchResource ?? fetch;
			const response = await fetchResource(resourceProps.resourceUrl, {
				signal: resourceProps.signal,
			});
			if (!response.ok) {
				throw new Error(`Native Worktree/File resource request failed: ${response.status}`);
			}
			return await readBridgeTextResourceStream(response, {
				integrity: resourceProps.descriptor.content.integrity,
				maxBytes: resourceProps.descriptor.content.maxBytes,
				onTextChunk: resourceProps.onTextChunk,
				signal: resourceProps.signal,
			});
		},
		loadWorktreeFileSurface: async (): Promise<WorktreeFileInitialSurface> => {
			if (isDisposed) {
				throw new Error('Native Worktree/File backend is disposed');
			}
			const requestId = props.createRequestId?.() ?? `worktree-file-${crypto.randomUUID()}`;
			const response = await sendNativeWorktreeFileOpenStreamCommand({
				requestId,
				sourceSpec: {
					...sourceSpec,
					clientRequestId: requestId,
				},
				target,
				timeoutMilliseconds:
					props.responseTimeoutMilliseconds ?? defaultResponseTimeoutMilliseconds,
			});
			const snapshotFrame = worktreeFileProtocolFrameSchema.parse(response);
			if (snapshotFrame.frameKind !== 'worktree.snapshot') {
				throw new Error('Native Worktree/File open stream did not return a snapshot frame');
			}
			installIntakeListener({
				streamId: snapshotFrame.streamId,
				generation: snapshotFrame.generation,
			});
			return {
				frames: [snapshotFrame],
				provenance: nativeWorktreeFileSurfaceProvenance(sourceSpec.rootPathToken),
				source: snapshotFrame.source,
			};
		},
		subscribeWorktreeFileFrames: (
			subscriber: WorktreeFileFrameSubscriber,
		): WorktreeFileFrameSubscriptionDispose => {
			subscribers.add(subscriber);
			if (pendingFrames.length > 0) {
				const frames = pendingFrames.splice(0, pendingFrames.length);
				subscriber(frames);
			}
			return (): void => {
				subscribers.delete(subscriber);
			};
		},
		dispose: (): void => {
			isDisposed = true;
			target.removeEventListener('__bridge_handshake', handleHandshake);
			disposeIntakeListener?.();
			disposeIntakeListener = null;
			subscribers.clear();
			pendingFrames.length = 0;
		},
	};
}

function readNativeWorktreeFileSourceSpec(
	target: Document,
): z.infer<typeof worktreeFileSurfaceSourceSpecSchema> | null {
	const rawSpec = target.documentElement.getAttribute(nativeWorktreeFileSourceSpecAttribute);
	if (rawSpec === null) {
		return null;
	}
	try {
		return worktreeFileSurfaceSourceSpecSchema.parse(JSON.parse(rawSpec));
	} catch {
		return null;
	}
}

async function sendNativeWorktreeFileOpenStreamCommand(props: {
	readonly requestId: string;
	readonly sourceSpec: z.infer<typeof worktreeFileSurfaceSourceSpecSchema>;
	readonly target: Document;
	readonly timeoutMilliseconds: number;
}): Promise<unknown> {
	const bridgeNonce = props.target.documentElement.getAttribute('data-bridge-nonce');
	if (bridgeNonce === null || bridgeNonce.length === 0) {
		throw new Error('Native Worktree/File command nonce is unavailable');
	}
	return await new Promise((resolve, reject): void => {
		const timeoutId = window.setTimeout((): void => {
			cleanup();
			reject(new Error('Native Worktree/File open stream timed out'));
		}, props.timeoutMilliseconds);
		const handleResponse = (event: Event): void => {
			const detail = extractEventDetail(event);
			const parsedResponse = bridgeRPCResponseSchema.safeParse(detail);
			if (!parsedResponse.success || String(parsedResponse.data.id) !== props.requestId) {
				return;
			}
			cleanup();
			if (parsedResponse.data.error !== undefined) {
				reject(new Error('Native Worktree/File open stream failed'));
				return;
			}
			resolve(parsedResponse.data.result);
		};
		const cleanup = (): void => {
			window.clearTimeout(timeoutId);
			props.target.removeEventListener('__bridge_response', handleResponse);
		};
		props.target.addEventListener('__bridge_response', handleResponse);
		props.target.dispatchEvent(
			new CustomEvent('__bridge_command', {
				detail: {
					jsonrpc: '2.0',
					id: props.requestId,
					method: nativeWorktreeFileOpenSourceStreamMethod,
					params: props.sourceSpec,
					__nonce: bridgeNonce,
					__commandId: props.requestId,
				},
			}),
		);
	});
}

function parseWorktreeFileFrame(json: string): WorktreeFileProtocolFrame | null {
	try {
		return worktreeFileProtocolFrameSchema.parse(JSON.parse(json));
	} catch {
		return null;
	}
}

function nativeWorktreeFileSurfaceProvenance(rootPathToken: string): WorktreeFileSurfaceProvenance {
	return {
		baseRef: 'native-current-worktree',
		scenarioName: 'current-worktree',
		worktreeRootToken: rootPathToken,
	};
}

function extractEventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}

function eventDetailHasNonceAndJSON(
	value: unknown,
	nonce: string,
): value is { readonly json: string; readonly nonce: string } {
	return (
		typeof value === 'object' &&
		value !== null &&
		'nonce' in value &&
		value.nonce === nonce &&
		'json' in value &&
		typeof value.json === 'string'
	);
}
