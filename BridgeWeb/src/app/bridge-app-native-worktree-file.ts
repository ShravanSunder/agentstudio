import { z } from 'zod';

import {
	installBridgeIntakeEventCarrier,
	type BridgeIntakeCarrierDrop,
} from '../core/intake/bridge-intake-carrier.js';
import type {
	BridgeIntakeReceiveResult,
	BridgeIntakeReceiver,
	BridgeIntakeReceiverState,
	BridgeIntakeReceiveDropReason,
} from '../core/intake/bridge-intake-receiver.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { loadBridgeTextResourceWithTiming } from '../core/resources/bridge-resource-stream.js';
import {
	worktreeFileSurfaceOpenSourceOutcomeSchema,
	worktreeFileDescriptorRequestSchema,
	worktreeFileProtocolFrameSchema,
	worktreeFileSurfaceSourceSpecSchema,
	type WorktreeFileDescriptorRequest,
	type WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	createBridgeTelemetryRecorder,
	type BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
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
import {
	createNativeWorktreeFileTelemetrySink,
	extractNativeWorktreeFileTelemetryConfig,
	recordNativeWorktreeFileIntakeRejectTelemetry,
} from './bridge-app-native-worktree-file-telemetry.js';

export interface BridgeAppNativeWorktreeFileBackend {
	readonly fetchWorktreeFileResource: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly loadWorktreeFileSurface: () => Promise<WorktreeFileInitialSurface>;
	readonly requestWorktreeFileDescriptor: (request: WorktreeFileDescriptorRequest) => Promise<void>;
	readonly registerWorktreeFileStreamResetRequiredCallback: (callback: () => void) => () => void;
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
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
}

const nativeWorktreeFileSourceSpecAttribute = 'data-bridge-worktree-file-source-spec';
const nativeWorktreeFileOpenSourceStreamMethod = 'worktreeFileSurface.openSourceStream';
const nativeWorktreeFileRequestDescriptorMethod = 'worktreeFileSurface.requestFileDescriptor';
const bridgeIntakeReadyMethod = 'bridge.intakeReady';
const defaultResponseTimeoutMilliseconds = 10_000;
const defaultMaxFrameBytes = 8 * 1024 * 1024;
let fallbackRequestIdSequence = 0;

type NativeWorktreeFileProbeReason =
	| 'drop_frame_too_large'
	| 'drop_identity_mismatch'
	| 'drop_missing_push_nonce'
	| 'drop_nonce_mismatch'
	| 'drop_parse_failed'
	| 'drop_reset_required'
	| 'drop_sequence_gap'
	| 'frame_buffered_initial_surface'
	| 'frame_published'
	| 'handshake_received'
	| 'listener_installed'
	| 'open_accepted'
	| 'open_response_error'
	| 'open_response_parse_failed'
	| 'open_response_received'
	| 'open_response_timeout'
	| 'replay_requested'
	| 'snapshot_resolved';

interface NativeWorktreeFileProbeEntry {
	readonly reason: NativeWorktreeFileProbeReason;
	readonly frameKind?: string;
	readonly generation?: number;
	readonly receiverGeneration?: number;
	readonly receiverReason?: BridgeIntakeReceiveDropReason;
	readonly reopenSignaled?: boolean;
	readonly sequence?: number;
	readonly streamIdMatches?: boolean;
}

interface InitialWorktreeFileSurfaceReplayBuffer {
	readonly generation: number;
	readonly streamId: string;
	readonly frames: WorktreeFileProtocolFrame[];
}

declare global {
	interface Window {
		__bridgeNativeWorktreeFileProbe?: NativeWorktreeFileProbeEntry[];
	}
}

const bridgeRPCErrorPayloadSchema = z
	.object({
		code: z.number().int(),
		message: z.string(),
	})
	.passthrough();
const bridgeRPCResponseSchema = z
	.object({
		id: z.union([z.string(), z.number()]),
		result: z.unknown().optional(),
		error: bridgeRPCErrorPayloadSchema.optional(),
	})
	.passthrough();
const bridgeRPCNoResponseResultSchema = z.object({}).strict();

export function createBridgeAppNativeWorktreeFileBackend(
	props: CreateBridgeAppNativeWorktreeFileBackendProps = {},
): BridgeAppNativeWorktreeFileBackend | null {
	const target = props.target ?? document;
	const sourceSpec = readNativeWorktreeFileSourceSpec(target);
	if (sourceSpec === null) {
		return null;
	}

	const subscribers = new Set<WorktreeFileFrameSubscriber>();
	const streamResetRequiredCallbacks = new Set<() => void>();
	const pendingFrames: WorktreeFileProtocolFrame[] = [];
	const pendingOpenResolvers = new Set<{
		readonly streamId: string;
		readonly generation: number;
		readonly resolve: (
			frame: Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }>,
		) => void;
		readonly reject: (error: Error) => void;
	}>();
	let pushNonce: string | null = null;
	let disposeIntakeListener: (() => void) | null = null;
	let initialSurfaceReplayBuffer: InitialWorktreeFileSurfaceReplayBuffer | null = null;
	let resolvedStreamIdentity: { readonly streamId: string; readonly generation: number } | null =
		null;
	let pendingOpenCount = 0;
	let streamResetRequiredEpisodeKey: string | null = null;
	let telemetryRecorder = props.telemetryRecorder ?? createBridgeTelemetryRecorder(null);
	let didConfigureTelemetryRecorder = props.telemetryRecorder !== undefined;
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
	const notifyWorktreeFileStreamResetRequired = (): void => {
		for (const callback of streamResetRequiredCallbacks) {
			queueMicrotask(callback);
		}
	};
	const signalResolvedStreamResetRequired = (): boolean => {
		if (resolvedStreamIdentity === null || pendingOpenCount > 0) {
			return false;
		}
		const episodeKey = `${resolvedStreamIdentity.streamId}:generation-${resolvedStreamIdentity.generation}`;
		if (streamResetRequiredEpisodeKey === episodeKey) {
			return false;
		}
		streamResetRequiredEpisodeKey = episodeKey;
		notifyWorktreeFileStreamResetRequired();
		return true;
	};
	const signalStreamResetRequiredForReceiverRejection = (
		receiverReason: BridgeIntakeReceiveDropReason,
	): boolean => {
		switch (receiverReason) {
			case 'sequence_gap':
				notifyWorktreeFileStreamResetRequired();
				return true;
			case 'generation_mismatch':
			case 'stream_mismatch':
				return signalResolvedStreamResetRequired();
			case 'closed':
			case 'duplicate_sequence':
			case 'reset_required':
			case 'stale_sequence':
				return false;
		}
		return assertNever(receiverReason);
	};

	const installIntakeListener = (streamIdentity: {
		readonly streamId: string;
		readonly generation: number;
	}): void => {
		disposeIntakeListener?.();
		const publishWorktreeFileFrame = (frame: WorktreeFileProtocolFrame): void => {
			if (frame.streamId !== streamIdentity.streamId) {
				recordNativeWorktreeFileProbe({
					reason: 'drop_identity_mismatch',
					frameKind: frame.frameKind,
					generation: frame.generation,
					sequence: frame.sequence,
					streamIdMatches: false,
				});
				return;
			}
			if (frame.frameKind === 'worktree.snapshot') {
				for (const resolver of pendingOpenResolvers) {
					if (resolver.streamId === frame.streamId && resolver.generation === frame.generation) {
						pendingOpenResolvers.delete(resolver);
						recordNativeWorktreeFileProbe({
							reason: 'snapshot_resolved',
							frameKind: frame.frameKind,
							generation: frame.generation,
							sequence: frame.sequence,
							streamIdMatches: true,
						});
						resolver.resolve(frame);
						return;
					}
				}
			}
			if (
				initialSurfaceReplayBuffer !== null &&
				initialSurfaceReplayBuffer.streamId === frame.streamId &&
				initialSurfaceReplayBuffer.generation === frame.generation
			) {
				initialSurfaceReplayBuffer.frames.push(frame);
				recordNativeWorktreeFileProbe({
					reason: 'frame_buffered_initial_surface',
					frameKind: frame.frameKind,
					generation: frame.generation,
					sequence: frame.sequence,
					streamIdMatches: true,
				});
				return;
			}
			recordNativeWorktreeFileProbe({
				reason: 'frame_published',
				frameKind: frame.frameKind,
				generation: frame.generation,
				sequence: frame.sequence,
				streamIdMatches: true,
			});
			publishFrames([frame]);
		};
		const receiver = createNativeWorktreeFileIntakeReceiver({
			generation: streamIdentity.generation,
			onFrame: publishWorktreeFileFrame,
			streamId: streamIdentity.streamId,
		});
		disposeIntakeListener = installBridgeIntakeEventCarrier({
			target,
			eventName: '__bridge_intake_json',
			getNonce: (): string | null => pushNonce,
			receiver,
			maxFrameBytes: props.maxFrameBytes ?? defaultMaxFrameBytes,
			requestReplayOnInstall: false,
			onDroppedFrame: (drop: BridgeIntakeCarrierDrop): void => {
				const receiverGeneration = receiver.state.generation;
				const reopenSignaled =
					drop.reason === 'receiver_rejected_frame'
						? signalStreamResetRequiredForReceiverRejection(drop.receiverReason)
						: false;
				recordNativeWorktreeFileCarrierDrop(drop, {
					receiverGeneration,
					reopenSignaled,
					telemetryRecorder,
				});
			},
		});
		recordNativeWorktreeFileProbe({ reason: 'listener_installed' });
	};

	const handleHandshake = (event: Event): void => {
		const detail = extractEventDetail(event);
		if (typeof detail === 'object' && detail !== null && 'pushNonce' in detail) {
			const nextPushNonce = detail.pushNonce;
			if (typeof nextPushNonce === 'string' && nextPushNonce.length > 0) {
				pushNonce = nextPushNonce;
				recordNativeWorktreeFileProbe({ reason: 'handshake_received' });
			}
		}
		if (!didConfigureTelemetryRecorder) {
			const telemetryConfig = extractNativeWorktreeFileTelemetryConfig(event);
			if (telemetryConfig !== null) {
				telemetryRecorder = createBridgeTelemetryRecorder(
					telemetryConfig,
					createNativeWorktreeFileTelemetrySink({
						endpointUrl: telemetryConfig.endpointUrl,
					}),
				);
				didConfigureTelemetryRecorder = true;
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
			return await loadBridgeTextResourceWithTiming({
				integrity: resourceProps.descriptor.content.integrity,
				maxBytes: resourceProps.descriptor.content.maxBytes,
				onTextChunk: resourceProps.onTextChunk,
				performFetch: async (): Promise<Response> =>
					await fetchResource(resourceProps.resourceUrl, {
						signal: resourceProps.signal,
					}),
				probe: resourceProps.probe,
				signal: resourceProps.signal,
			});
		},
		loadWorktreeFileSurface: async (): Promise<WorktreeFileInitialSurface> => {
			if (isDisposed) {
				throw new Error('Native Worktree/File backend is disposed');
			}
			pendingOpenCount += 1;
			try {
				const requestId = props.createRequestId?.() ?? createNativeWorktreeFileRequestId();
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
				const parsedOutcome = worktreeFileSurfaceOpenSourceOutcomeSchema.safeParse(response);
				if (!parsedOutcome.success) {
					recordNativeWorktreeFileProbe({
						reason: 'open_response_parse_failed',
						streamIdMatches: false,
					});
					throw new Error('Native Worktree/File open stream returned invalid outcome');
				}
				const outcome = parsedOutcome.data;
				recordNativeWorktreeFileProbe({
					reason: 'open_accepted',
					generation: outcome.generation,
					streamIdMatches: true,
				});
				installIntakeListener({
					streamId: outcome.streamId,
					generation: outcome.generation,
				});
				initialSurfaceReplayBuffer = {
					streamId: outcome.streamId,
					generation: outcome.generation,
					frames: [],
				};
				const snapshotFramePromise = waitForNativeWorktreeSnapshot({
					generation: outcome.generation,
					pendingOpenResolvers,
					streamId: outcome.streamId,
					target,
					timeoutMilliseconds:
						props.responseTimeoutMilliseconds ?? defaultResponseTimeoutMilliseconds,
				});
				target.dispatchEvent(new CustomEvent('__bridge_intake_replay_request'));
				recordNativeWorktreeFileProbe({
					reason: 'replay_requested',
					generation: outcome.generation,
					streamIdMatches: true,
				});
				sendNativeBridgeIntakeReadyCommand({
					generation: outcome.generation,
					streamId: outcome.streamId,
					target,
				});
				const snapshotFrame = await snapshotFramePromise;
				const replayedFrames = initialSurfaceReplayBuffer?.frames ?? [];
				initialSurfaceReplayBuffer = null;
				resolvedStreamIdentity = {
					generation: outcome.generation,
					streamId: outcome.streamId,
				};
				streamResetRequiredEpisodeKey = null;
				return {
					frames: [snapshotFrame, ...replayedFrames],
					provenance: nativeWorktreeFileSurfaceProvenance(sourceSpec.rootPathToken),
					source: snapshotFrame.source,
				};
			} finally {
				pendingOpenCount -= 1;
			}
		},
		requestWorktreeFileDescriptor: async (
			request: WorktreeFileDescriptorRequest,
		): Promise<void> => {
			if (isDisposed) {
				throw new Error('Native Worktree/File backend is disposed');
			}
			const parsedRequest = worktreeFileDescriptorRequestSchema.safeParse(request);
			if (!parsedRequest.success) {
				throw new Error('Native Worktree/File descriptor request is invalid');
			}
			const requestId = props.createRequestId?.() ?? createNativeWorktreeFileRequestId();
			try {
				await sendNativeWorktreeFileDescriptorRequestCommand({
					request: parsedRequest.data,
					requestId,
					target,
					timeoutMilliseconds:
						props.responseTimeoutMilliseconds ?? defaultResponseTimeoutMilliseconds,
				});
			} catch (error) {
				if (nativeWorktreeFileDescriptorErrorRequiresStreamReset(error)) {
					signalResolvedStreamResetRequired();
				}
				throw error;
			}
		},
		registerWorktreeFileStreamResetRequiredCallback: (callback: () => void): (() => void) => {
			streamResetRequiredCallbacks.add(callback);
			return (): void => {
				streamResetRequiredCallbacks.delete(callback);
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
			for (const resolver of pendingOpenResolvers) {
				resolver.reject(new Error('Native Worktree/File backend is disposed'));
			}
			pendingOpenResolvers.clear();
			subscribers.clear();
			streamResetRequiredCallbacks.clear();
			pendingFrames.length = 0;
			initialSurfaceReplayBuffer = null;
			resolvedStreamIdentity = null;
			streamResetRequiredEpisodeKey = null;
		},
	};
}

export function createNativeWorktreeFileRequestId(): string {
	fallbackRequestIdSequence = (fallbackRequestIdSequence + 1) % Number.MAX_SAFE_INTEGER;
	return `worktree-file-${Date.now().toString(36)}-${fallbackRequestIdSequence.toString(36)}`;
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
			recordNativeWorktreeFileProbe({ reason: 'open_response_timeout' });
			reject(new Error('Native Worktree/File open stream timed out'));
		}, props.timeoutMilliseconds);
		const handleResponse = (event: Event): void => {
			const detail = extractEventDetail(event);
			const parsedResponse = bridgeRPCResponseSchema.safeParse(detail);
			if (!parsedResponse.success || String(parsedResponse.data.id) !== props.requestId) {
				return;
			}
			cleanup();
			recordNativeWorktreeFileProbe({ reason: 'open_response_received' });
			if (parsedResponse.data.error !== undefined) {
				recordNativeWorktreeFileProbe({ reason: 'open_response_error' });
				reject(
					new Error(
						`Native Worktree/File open stream failed: ${nativeWorktreeFileOpenStreamErrorClass(parsedResponse.data.error)}`,
					),
				);
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

async function sendNativeWorktreeFileDescriptorRequestCommand(props: {
	readonly request: WorktreeFileDescriptorRequest;
	readonly requestId: string;
	readonly target: Document;
	readonly timeoutMilliseconds: number;
}): Promise<void> {
	const bridgeNonce = props.target.documentElement.getAttribute('data-bridge-nonce');
	if (bridgeNonce === null || bridgeNonce.length === 0) {
		throw new Error('Native Worktree/File command nonce is unavailable');
	}
	await new Promise<void>((resolve, reject): void => {
		const timeoutId = window.setTimeout((): void => {
			cleanup();
			reject(new Error('Native Worktree/File descriptor request timed out'));
		}, props.timeoutMilliseconds);
		const handleResponse = (event: Event): void => {
			const detail = extractEventDetail(event);
			const parsedResponse = bridgeRPCResponseSchema.safeParse(detail);
			if (!parsedResponse.success || String(parsedResponse.data.id) !== props.requestId) {
				return;
			}
			cleanup();
			if (parsedResponse.data.error !== undefined) {
				reject(
					new Error(
						`Native Worktree/File descriptor request failed: ${nativeWorktreeFileOpenStreamErrorClass(parsedResponse.data.error)}`,
					),
				);
				return;
			}
			const parsedAck = bridgeRPCNoResponseResultSchema.safeParse(parsedResponse.data.result);
			if (!parsedAck.success) {
				reject(
					new Error('Native Worktree/File descriptor request returned invalid acknowledgement'),
				);
				return;
			}
			resolve();
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
					method: nativeWorktreeFileRequestDescriptorMethod,
					params: props.request,
					__nonce: bridgeNonce,
					__commandId: props.requestId,
				},
			}),
		);
	});
}

function nativeWorktreeFileOpenStreamErrorClass(
	error: z.infer<typeof bridgeRPCErrorPayloadSchema>,
): string {
	if (/^worktree_file\.[a-z0-9_.-]+$/u.test(error.message)) {
		return error.message;
	}
	switch (error.code) {
		case -32_004:
			return 'bridge_not_ready';
		case -32_600:
			return 'invalid_request';
		case -32_601:
			return 'method_not_found';
		case -32_602:
			return 'invalid_params';
		case -32_603:
			return 'internal_error';
		case -32_700:
			return 'parse_error';
		default:
			return 'jsonrpc_error';
	}
}

function nativeWorktreeFileDescriptorErrorRequiresStreamReset(error: unknown): boolean {
	if (!(error instanceof Error)) {
		return false;
	}
	return (
		error.message.endsWith('worktree_file.source_identity_mismatch') ||
		error.message.endsWith('worktree_file.stale_source_generation')
	);
}

function sendNativeBridgeIntakeReadyCommand(props: {
	readonly generation: number;
	readonly streamId: string;
	readonly target: Document;
}): void {
	const bridgeNonce = props.target.documentElement.getAttribute('data-bridge-nonce');
	if (bridgeNonce === null || bridgeNonce.length === 0) {
		throw new Error('Native Worktree/File command nonce is unavailable');
	}
	props.target.dispatchEvent(
		new CustomEvent('__bridge_command', {
			detail: {
				jsonrpc: '2.0',
				method: bridgeIntakeReadyMethod,
				params: {
					generation: props.generation,
					protocolId: 'worktree-file',
					streamId: props.streamId,
				},
				__nonce: bridgeNonce,
				__commandId: `${props.streamId}:generation-${props.generation}:intake-ready`,
			},
		}),
	);
}

function waitForNativeWorktreeSnapshot(props: {
	readonly streamId: string;
	readonly generation: number;
	readonly pendingOpenResolvers: Set<{
		readonly streamId: string;
		readonly generation: number;
		readonly resolve: (
			frame: Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }>,
		) => void;
		readonly reject: (error: Error) => void;
	}>;
	readonly target: Document;
	readonly timeoutMilliseconds: number;
}): Promise<Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }>> {
	return new Promise((resolve, reject): void => {
		let timeoutId = 0;
		const requestReplayAfterTimeout = (): void => {
			props.target.dispatchEvent(new CustomEvent('__bridge_intake_replay_request'));
			recordNativeWorktreeFileProbe({
				reason: 'replay_requested',
				generation: props.generation,
				streamIdMatches: true,
			});
			timeoutId = window.setTimeout(requestReplayAfterTimeout, props.timeoutMilliseconds);
		};
		const resolver = {
			streamId: props.streamId,
			generation: props.generation,
			resolve: (
				frame: Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }>,
			): void => {
				window.clearTimeout(timeoutId);
				resolve(frame);
			},
			reject: (error: Error): void => {
				window.clearTimeout(timeoutId);
				reject(error);
			},
		};
		props.pendingOpenResolvers.add(resolver);
		timeoutId = window.setTimeout(requestReplayAfterTimeout, props.timeoutMilliseconds);
	});
}

function createNativeWorktreeFileIntakeReceiver(props: {
	readonly streamId: string;
	readonly generation: number;
	readonly onFrame: (frame: WorktreeFileProtocolFrame) => void;
}): BridgeIntakeReceiver {
	let status: BridgeIntakeReceiverState['status'] = 'opening';
	let currentGeneration = props.generation;
	let nextSequence = 0;

	const reject = (
		reason: Extract<BridgeIntakeReceiveResult, { readonly ok: false }>['reason'],
	): BridgeIntakeReceiveResult => ({
		ok: false,
		reason,
		status,
	});

	return {
		get state(): BridgeIntakeReceiverState {
			return {
				status,
				streamId: props.streamId,
				generation: currentGeneration,
				nextSequence,
			};
		},
		receive(frame: BridgeIntakeFrame): BridgeIntakeReceiveResult {
			if (status === 'closed') {
				return reject('closed');
			}
			if (frame.streamId !== props.streamId) {
				recordNativeWorktreeFileProbe({
					reason: 'drop_identity_mismatch',
					generation: frame.generation,
					streamIdMatches: false,
				});
				return reject('stream_mismatch');
			}
			if (
				frame.kind === 'reset' &&
				(frame.generation > currentGeneration ||
					(frame.generation === currentGeneration && frame.sequence >= nextSequence))
			) {
				const resetFrame = worktreeFileProtocolFrameFromIntakeFrame(frame);
				if (
					resetFrame === null ||
					!worktreeFileIntakeFrameMatchesProtocolFrame(frame, resetFrame)
				) {
					recordNativeWorktreeFileProbe({
						reason: 'drop_parse_failed',
						generation: frame.generation,
						streamIdMatches: true,
					});
					return reject('generation_mismatch');
				}
				currentGeneration = frame.generation;
				nextSequence = frame.sequence + 1;
				status = 'active';
				props.onFrame(resetFrame);
				return { ok: true, status };
			}
			if (status === 'resetRequired') {
				return reject('reset_required');
			}
			if (frame.generation !== currentGeneration) {
				recordNativeWorktreeFileProbe({
					reason: 'drop_identity_mismatch',
					generation: frame.generation,
					streamIdMatches: true,
				});
				return reject('generation_mismatch');
			}
			if (frame.sequence < nextSequence) {
				return reject(
					frame.sequence === nextSequence - 1 ? 'duplicate_sequence' : 'stale_sequence',
				);
			}
			if (frame.sequence > nextSequence) {
				status = 'resetRequired';
				return reject('sequence_gap');
			}
			if (frame.kind === 'close') {
				nextSequence += 1;
				status = 'closed';
				return { ok: true, status };
			}
			const protocolFrame = worktreeFileProtocolFrameFromIntakeFrame(frame);
			if (
				protocolFrame === null ||
				!worktreeFileIntakeFrameMatchesProtocolFrame(frame, protocolFrame)
			) {
				recordNativeWorktreeFileProbe({
					reason: 'drop_parse_failed',
					generation: frame.generation,
					streamIdMatches: true,
				});
				return reject('generation_mismatch');
			}
			nextSequence += 1;
			status = 'active';
			props.onFrame(protocolFrame);
			return { ok: true, status };
		},
		close(): void {
			status = 'closed';
		},
	};
}

function worktreeFileProtocolFrameFromIntakeFrame(
	frame: BridgeIntakeFrame,
): WorktreeFileProtocolFrame | null {
	if (!('payload' in frame)) {
		return null;
	}
	const parsedFrame = worktreeFileProtocolFrameSchema.safeParse(frame.payload);
	return parsedFrame.success ? parsedFrame.data : null;
}

function worktreeFileIntakeFrameMatchesProtocolFrame(
	frame: BridgeIntakeFrame,
	protocolFrame: WorktreeFileProtocolFrame,
): boolean {
	return (
		frame.kind === expectedWorktreeFileIntakeKind(protocolFrame) &&
		frame.streamId === protocolFrame.streamId &&
		frame.generation === protocolFrame.generation &&
		frame.sequence === protocolFrame.sequence
	);
}

function expectedWorktreeFileIntakeKind(
	frame: WorktreeFileProtocolFrame,
): Extract<BridgeIntakeFrame, { readonly payload: unknown }>['kind'] | 'reset' {
	switch (frame.frameKind) {
		case 'worktree.snapshot':
			return 'snapshot';
		case 'worktree.reset':
			return 'reset';
		case 'worktree.fileDescriptor':
		case 'worktree.fileInvalidated':
		case 'worktree.statusPatch':
		case 'worktree.treeDelta':
		case 'worktree.treeWindow':
			return 'delta';
	}
	return assertNever(frame);
}

function nativeWorktreeFileProbeReasonForReceiverRejection(
	receiverReason: BridgeIntakeReceiveDropReason,
): NativeWorktreeFileProbeReason {
	switch (receiverReason) {
		case 'stream_mismatch':
		case 'generation_mismatch':
			return 'drop_identity_mismatch';
		case 'sequence_gap':
			return 'drop_sequence_gap';
		case 'reset_required':
			return 'drop_reset_required';
		case 'closed':
		case 'duplicate_sequence':
		case 'stale_sequence':
			return 'drop_parse_failed';
	}
	return assertNever(receiverReason);
}

function assertNever(value: never): never {
	throw new Error(`Unhandled native Worktree/File variant: ${String(value)}`);
}

function recordNativeWorktreeFileCarrierDrop(
	drop: BridgeIntakeCarrierDrop,
	context: {
		readonly receiverGeneration: number;
		readonly reopenSignaled: boolean;
		readonly telemetryRecorder: BridgeTelemetryRecorder;
	},
): void {
	switch (drop.reason) {
		case 'frame_too_large':
			recordNativeWorktreeFileProbe({ reason: 'drop_frame_too_large' });
			return;
		case 'missing_carrier_nonce':
			recordNativeWorktreeFileProbe({ reason: 'drop_missing_push_nonce' });
			return;
		case 'carrier_nonce_mismatch':
			recordNativeWorktreeFileProbe({ reason: 'drop_nonce_mismatch' });
			return;
		case 'receiver_rejected_frame':
			recordNativeWorktreeFileIntakeRejectTelemetry({
				frameGeneration: drop.frame.generation,
				reason: drop.receiverReason,
				receiverGeneration: context.receiverGeneration,
				reopenSignaled: context.reopenSignaled,
				streamIdMatches: drop.receiverReason !== 'stream_mismatch',
				telemetryRecorder: context.telemetryRecorder,
			});
			recordNativeWorktreeFileProbe({
				reason: nativeWorktreeFileProbeReasonForReceiverRejection(drop.receiverReason),
				generation: drop.frame.generation,
				receiverGeneration: context.receiverGeneration,
				receiverReason: drop.receiverReason,
				reopenSignaled: context.reopenSignaled,
				sequence: drop.frame.sequence,
				streamIdMatches: drop.receiverReason !== 'stream_mismatch',
			});
			return;
		case 'frame_decode_failed':
		case 'host_port_message_invalid':
			recordNativeWorktreeFileProbe({ reason: 'drop_parse_failed' });
			return;
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

function recordNativeWorktreeFileProbe(entry: NativeWorktreeFileProbeEntry): void {
	if (typeof window === 'undefined') {
		return;
	}
	const probe = window.__bridgeNativeWorktreeFileProbe ?? [];
	probe.push(entry);
	if (probe.length > 40) {
		probe.splice(0, probe.length - 40);
	}
	window.__bridgeNativeWorktreeFileProbe = probe;
}
