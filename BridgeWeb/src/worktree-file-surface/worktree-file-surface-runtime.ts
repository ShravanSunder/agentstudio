import { createBridgeBodyRegistry } from '../core/demand/bridge-body-registry.js';
import { bridgeContentDemandExecutionPolicy } from '../core/demand/bridge-content-demand-policy.js';
import { createBridgeResourceExecutor } from '../core/demand/bridge-resource-executor.js';
import type { BridgeDemandIntent, BridgeDemandLane } from '../core/models/bridge-demand-models.js';
import type { BridgeResourceDescriptor } from '../core/models/bridge-resource-descriptor.js';
import { createBridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamChunk } from '../core/resources/bridge-resource-stream.js';
import type { BridgeTextResourceLoadTimingProbe } from '../core/resources/bridge-resource-stream.js';
import { mapWorktreeFileDemandStimulusToIntents } from '../features/worktree-file/demand/worktree-file-demand-policy.js';
import {
	applyWorktreeFileProtocolFrame,
	type WorktreeFileMaterializerDelta,
} from '../features/worktree-file/materialization/worktree-file-materializer.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDemandStimulus,
	WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	applyWorktreeFileInvalidationToState,
	createWorktreeFileSurfaceState,
	openWorktreeFileSession,
	refreshWorktreeOpenFileSession,
	type WorktreeFileSurfaceState,
} from '../features/worktree-file/state/worktree-file-state.js';
import {
	applyReplacementDescriptorToOpenSessions,
	cancelSourceDemand,
	canFetchWorktreeFileBody,
	deleteResetReplacementDescriptorKeysForSource,
	isDescriptorFromSourceLessResetAnchor,
	isDescriptorRefBlockedByReset,
	isOpenFileRefreshStillCurrent,
	loadPreloadIntent,
	loadStimulus,
	makeWorktreeFileDemandReadContext,
	markAllOpenSessionsStale,
	markOpenSessionsStaleForReplacementSource,
	markSourceOpenSessionsStale,
	recordExecutorLifecycleTiming,
	resetDescriptorKeyForBridgeDescriptorRef,
	resourceWithMutableLoadTiming,
	settlePreloadLoads,
	stateWithOpenSessionStatus,
	streamConsumerKeyForIntent,
	type WorktreeFileDemandLifecycleTiming,
	type WorktreeFileSourceLessResetScope,
} from './worktree-file-surface-runtime-support.js';

export interface WorktreeFileSurfaceRuntimeFetchResourceProps {
	readonly descriptor: BridgeResourceDescriptor;
	readonly onTextChunk?: ((chunk: BridgeTextResourceStreamChunk) => void) | undefined;
	readonly probe?: BridgeTextResourceLoadTimingProbe | undefined;
	readonly resourceUrl: string;
	readonly signal: AbortSignal;
}

export interface WorktreeFileSurfaceRuntimeFetchedResource {
	readonly authoritative: boolean;
	readonly byteLength: number;
	readonly timing?: WorktreeFileSurfaceResourceLoadTiming | undefined;
	readText(): string;
}

export interface WorktreeFileSurfaceResourceLoadTiming {
	readonly bodyRegistryCommitMilliseconds?: number | null | undefined;
	readonly firstChunkWaitMilliseconds?: number | null | undefined;
	readonly responseWaitMilliseconds?: number | null | undefined;
	readonly streamReadMilliseconds?: number | null | undefined;
}

export function makeWorktreeFileSurfaceRuntimeFetchedResource(
	props:
		| string
		| {
				readonly authoritative?: boolean;
				readonly text: string;
				readonly timing?: WorktreeFileSurfaceResourceLoadTiming | undefined;
		  },
): WorktreeFileSurfaceRuntimeFetchedResource {
	const text = typeof props === 'string' ? props : props.text;
	return {
		authoritative: typeof props === 'string' ? true : (props.authoritative ?? true),
		byteLength: new TextEncoder().encode(text).byteLength,
		...(typeof props === 'string' || props.timing === undefined ? {} : { timing: props.timing }),
		readText: (): string => text,
	};
}

export interface WorktreeFileSurfaceRuntimeProps {
	readonly paneId: string;
	readonly fetchResource: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly now?: () => number;
	readonly onResourceTextChunk?: ((chunk: BridgeTextResourceStreamChunk) => void) | undefined;
	readonly resourceLoadProbe?: WorktreeFileSurfaceResourceLoadProbe | undefined;
}

export interface WorktreeFileSurfaceResourceLoadProbe {
	readonly isEnabled: () => boolean;
	readonly now: () => number;
	readonly record: (sample: WorktreeFileSurfaceResourceLoadProbeSample) => void;
}

export interface WorktreeFileSurfaceResourceLoadProbeSample {
	readonly byteLength: number;
	readonly estimatedBytes: number | null;
	readonly firstChunkWaitMilliseconds: number | null;
	readonly lane: BridgeDemandLane;
	readonly responseWaitMilliseconds: number | null;
	readonly result: 'failed' | 'success';
	readonly resultReason: string | null;
	readonly streamReadMilliseconds: number | null;
	readonly totalDurationMilliseconds: number;
}

export type WorktreeFileSurfaceLoadDisposition =
	| 'active-preloaded'
	| 'cache-hit'
	| 'cold-loaded'
	| 'idle-preloaded'
	| 'nearby-preloaded'
	| 'refreshed'
	| 'speculative-preloaded'
	| 'visible-preloaded';

export interface WorktreeFileSurfaceLoadTelemetry {
	readonly disposition: WorktreeFileSurfaceLoadDisposition;
	readonly durationMilliseconds: number;
	readonly estimatedBytes: number | null;
	readonly executorInFlightBytesAfter: number;
	readonly executorInFlightBytesBefore: number;
	readonly executorInFlightCountAfter: number;
	readonly executorInFlightCountBefore: number;
	readonly executorInFlightMilliseconds: number | null;
	readonly executorPendingWaitMilliseconds: number | null;
	readonly executorQueuedBytesAfter: number;
	readonly executorQueuedBytesBefore: number;
	readonly executorQueuedLoadCountAfter: number;
	readonly executorQueuedLoadCountBefore: number;
	readonly lane: BridgeDemandLane;
	readonly resourceBodyRegistryCommitMilliseconds: number | null;
	readonly resourceFetchResponseWaitMilliseconds: number | null;
	readonly resourceFirstChunkWaitMilliseconds: number | null;
	readonly resourceStreamReadMilliseconds: number | null;
	readonly demandQueueWaitMilliseconds: number | null;
}

export type WorktreeFileSurfaceApplyFrameResult =
	| {
			readonly ok: true;
			readonly deltaKind: WorktreeFileMaterializerDelta['kind'];
			readonly autoDemandCount?: number;
			readonly cancelledDemandCount?: number;
	  }
	| {
			readonly ok: false;
			readonly reason: 'invalid_frame' | 'descriptor_rejected' | 'unsupported_frame';
	  };

export interface WorktreeFileSurfaceOpenFileProps {
	readonly descriptor: WorktreeFileDescriptor;
	readonly onProvisionalTextChunk?:
		| ((chunk: WorktreeFileSurfaceProvisionalTextChunk) => void)
		| undefined;
	readonly openFileSessionId: string;
}

export interface WorktreeFileSurfaceRefreshOpenFileProps {
	readonly onProvisionalTextChunk?:
		| ((chunk: WorktreeFileSurfaceProvisionalTextChunk) => void)
		| undefined;
	readonly openFileSessionId: string;
}

export interface WorktreeFileSurfaceProvisionalTextChunk {
	readonly byteLength: number;
	readonly descriptorId: string;
	readonly text: string;
	readonly totalBytesRead: number;
}

export type WorktreeFileSurfaceLoadResult =
	| {
			readonly ok: true;
			readonly authoritative: boolean;
			readonly byteLength: number;
			readonly content: WorktreeFileSurfaceRuntimeFetchedResource;
			readonly descriptorId: string;
			readonly loadTelemetry: WorktreeFileSurfaceLoadTelemetry;
	  }
	| {
			readonly ok: false;
			readonly reason:
				| 'aborted'
				| 'byte_budget_exceeded'
				| 'concurrency_exceeded'
				| 'content_unavailable'
				| 'descriptor_missing'
				| 'descriptor_rejected'
				| 'load_failed'
				| 'no_demand'
				| 'preview_only'
				| 'source_reset'
				| 'stale_completion';
	  };

export type WorktreeFileSurfaceDemandDispatchLoadResult =
	| {
			readonly dedupeKey: string;
			readonly ok: true;
			readonly authoritative: boolean;
			readonly byteLength: number;
			readonly descriptorId: string;
			readonly freshnessKey: string;
			readonly loadTelemetry: WorktreeFileSurfaceLoadTelemetry;
	  }
	| {
			readonly ok: false;
			readonly descriptorId: string | null;
			readonly lane: BridgeDemandLane;
			readonly reason:
				| 'aborted'
				| 'byte_budget_exceeded'
				| 'concurrency_exceeded'
				| 'descriptor_missing'
				| 'load_failed'
				| 'preview_only'
				| 'stale_completion';
	  };

export interface WorktreeFileSurfaceDemandDispatchResult {
	readonly stimulusCount: number;
	readonly intentCount: number;
	readonly enqueueAcceptedCount: number;
	readonly enqueueRejectedCount: number;
	readonly loadedCount: number;
	readonly failedCount: number;
	readonly loadResults: readonly WorktreeFileSurfaceDemandDispatchLoadResult[];
	readonly executorInFlightBytesAfter: number;
	readonly executorInFlightCountAfter: number;
	readonly executorQueuedBytesAfter: number;
	readonly executorQueuedLoadCountAfter: number;
}

export interface WorktreeFileSurfaceRuntime {
	applyFrame(frame: WorktreeFileProtocolFrame): WorktreeFileSurfaceApplyFrameResult;
	dispatchDemandStimuli(
		stimuli: readonly WorktreeFileDemandStimulus[],
	): Promise<WorktreeFileSurfaceDemandDispatchResult>;
	openFile(props: WorktreeFileSurfaceOpenFileProps): Promise<WorktreeFileSurfaceLoadResult>;
	refreshOpenFile(
		props: WorktreeFileSurfaceRefreshOpenFileProps,
	): Promise<WorktreeFileSurfaceLoadResult>;
	getState(): WorktreeFileSurfaceState;
	getBodyRegistrySnapshot(): ReturnType<
		ReturnType<
			typeof createBridgeBodyRegistry<WorktreeFileSurfaceRuntimeFetchedResource>
		>['snapshot']
	>;
}

const worktreeFileBodyRegistryMaxBytes = 24 * 1024 * 1024;
const worktreeFileResourceExecutorMaxConcurrentLoads =
	bridgeContentDemandExecutionPolicy.immediateStartConcurrency;
const worktreeFileResourceExecutorMaxInFlightBytes = 8 * 1024 * 1024;
const worktreeFileResourceExecutorMaxQueuedLoads = 128;
const worktreeFileResourceExecutorMaxQueuedBytes = 8 * 1024 * 1024;

export function createWorktreeFileSurfaceRuntime(
	props: WorktreeFileSurfaceRuntimeProps,
): WorktreeFileSurfaceRuntime {
	const registry = createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: {
			'worktree-file': new Set(['worktree.fileContent', 'worktree.fileRange']),
		},
	});
	const bodyRegistry = createBridgeBodyRegistry<WorktreeFileSurfaceRuntimeFetchedResource>({
		maxBytes: worktreeFileBodyRegistryMaxBytes,
	});
	const preloadDispositionByBodyKey = new Map<string, WorktreeFileSurfaceLoadDisposition>();
	const provisionalChunkConsumersByIntentKey = new Map<
		string,
		(chunk: WorktreeFileSurfaceProvisionalTextChunk) => void
	>();
	const resetSourceIds = new Set<string>();
	const resetReplacementDescriptorKeys = new Set<string>();
	const resetScope: WorktreeFileSourceLessResetScope = {
		hasSourceLessReset: false,
		postResetAnchorSource: null,
	};
	let state = createWorktreeFileSurfaceState();
	let demandDispatchTail: Promise<void> = Promise.resolve();
	const now = props.now ?? ((): number => performance.now());
	const resourceLoadProbe =
		props.resourceLoadProbe === undefined
			? undefined
			: {
					isEnabled: props.resourceLoadProbe.isEnabled,
					now: props.resourceLoadProbe.now,
				};
	const lifecycleTimingsByDemandKey = new Map<string, WorktreeFileDemandLifecycleTiming>();
	const executor = createBridgeResourceExecutor<WorktreeFileSurfaceRuntimeFetchedResource>({
		registry,
		maxConcurrentLoads: worktreeFileResourceExecutorMaxConcurrentLoads,
		maxInFlightBytes: worktreeFileResourceExecutorMaxInFlightBytes,
		maxQueuedLoads: worktreeFileResourceExecutorMaxQueuedLoads,
		maxQueuedBytes: worktreeFileResourceExecutorMaxQueuedBytes,
		isFresh: (intent): boolean => {
			if (
				!isDescriptorRefBlockedByReset({
					ref: intent.descriptorRef,
					resetReplacementDescriptorKeys,
					resetScope,
					resetSourceIds,
				})
			) {
				return true;
			}
			return resetReplacementDescriptorKeys.has(
				resetDescriptorKeyForBridgeDescriptorRef(intent.descriptorRef),
			);
		},
		now,
		onLifecycleEvent: (event): void => {
			recordExecutorLifecycleTiming({ event, lifecycleTimingsByDemandKey });
		},
		loadResource: async ({ descriptor, intent, onChunk, signal }) => {
			const cachedBody = bodyRegistry.get({
				cacheKey: descriptor.resourceUrl,
				freshnessKey: intent.freshnessKey,
			});
			if (cachedBody !== null) {
				return {
					authoritative: cachedBody.authoritative,
					content: cachedBody,
					byteLength: cachedBody.byteLength,
				};
			}
			const fetchedResource = await props.fetchResource({
				descriptor,
				onTextChunk: (chunk): void => {
					onChunk({
						byteLength: chunk.byteLength,
						chunk: chunk.text,
						totalBytesRead: chunk.totalBytesRead,
					});
					provisionalChunkConsumersByIntentKey.get(streamConsumerKeyForIntent(intent))?.({
						byteLength: chunk.byteLength,
						descriptorId: descriptor.descriptorId,
						text: chunk.text,
						totalBytesRead: chunk.totalBytesRead,
					});
					props.onResourceTextChunk?.(chunk);
				},
				probe: resourceLoadProbe,
				resourceUrl: descriptor.resourceUrl,
				signal,
			});
			const resourceWithTiming = resourceWithMutableLoadTiming(fetchedResource);
			const content = resourceWithTiming.content;
			if (content.authoritative) {
				const bodyRegistryCommitStartedAtMilliseconds =
					fetchedResource.timing === undefined ? null : now();
				bodyRegistry.put({
					cacheKey: descriptor.resourceUrl,
					freshnessKey: intent.freshnessKey,
					body: content,
					byteLength: content.byteLength,
				});
				if (
					bodyRegistryCommitStartedAtMilliseconds !== null &&
					resourceWithTiming.timing !== null
				) {
					resourceWithTiming.timing.bodyRegistryCommitMilliseconds = Math.max(
						0,
						now() - bodyRegistryCommitStartedAtMilliseconds,
					);
				}
			}
			return {
				authoritative: content.authoritative,
				content,
				byteLength: content.byteLength,
			};
		},
	});
	const readContext = makeWorktreeFileDemandReadContext({
		registry,
		resetScope,
		resetSourceIds,
		resetReplacementDescriptorKeys,
	});

	const applyFrame = (frame: WorktreeFileProtocolFrame): WorktreeFileSurfaceApplyFrameResult => {
		const materializeResult = applyWorktreeFileProtocolFrame({
			frame,
			paneId: props.paneId,
			registry,
		});
		if (!materializeResult.ok) {
			return materializeResult;
		}
		const delta = materializeResult.delta;
		switch (delta.kind) {
			case 'fileInvalidated': {
				const invalidationResult = applyWorktreeFileInvalidationToState({
					state,
					invalidation: delta.invalidation,
				});
				state = invalidationResult.state;
				const autoDemandCount = invalidationResult.stimuli.flatMap((stimulus) =>
					mapWorktreeFileDemandStimulusToIntents({ stimulus, readContext }),
				).length;
				return {
					ok: true,
					deltaKind: delta.kind,
					autoDemandCount,
				};
			}
			case 'reset': {
				const cancelledDemandCount =
					delta.source === undefined
						? 0
						: cancelSourceDemand({
								executor,
								paneId: props.paneId,
								source: delta.source,
							});
				if (delta.source !== undefined) {
					resetSourceIds.add(delta.source.sourceId);
					deleteResetReplacementDescriptorKeysForSource({
						resetReplacementDescriptorKeys,
						sourceId: delta.source.sourceId,
					});
					state = markSourceOpenSessionsStale({
						source: delta.source,
						state,
					});
				} else {
					resetScope.hasSourceLessReset = true;
					resetScope.postResetAnchorSource = null;
					resetReplacementDescriptorKeys.clear();
					state = markAllOpenSessionsStale({ state });
				}
				return {
					ok: true,
					deltaKind: delta.kind,
					cancelledDemandCount,
				};
			}
			case 'fileDescriptor': {
				const isSourceResetReplacement = resetSourceIds.has(
					delta.descriptor.sourceIdentity.sourceId,
				);
				const isSourceLessResetReplacement =
					resetScope.hasSourceLessReset &&
					isDescriptorFromSourceLessResetAnchor({
						descriptor: delta.descriptor,
						resetScope,
					});
				if (isSourceResetReplacement || isSourceLessResetReplacement) {
					resetReplacementDescriptorKeys.add(
						resetDescriptorKeyForBridgeDescriptorRef(delta.descriptor.contentDescriptor.ref),
					);
				}
				if (!resetScope.hasSourceLessReset || isSourceLessResetReplacement) {
					state = applyReplacementDescriptorToOpenSessions({
						descriptor: delta.descriptor,
						state,
					});
				}
				return {
					ok: true,
					deltaKind: delta.kind,
				};
			}
			case 'snapshot':
				if (resetScope.hasSourceLessReset) {
					resetScope.postResetAnchorSource = delta.source;
				} else {
					state = markOpenSessionsStaleForReplacementSource({
						source: delta.source,
						state,
					});
					resetScope.postResetAnchorSource = delta.source;
				}
				return {
					ok: true,
					deltaKind: delta.kind,
				};
			case 'statusPatch':
			case 'treeDelta':
			case 'treeWindow':
				return {
					ok: true,
					deltaKind: delta.kind,
				};
		}
		return { ok: false, reason: 'unsupported_frame' };
	};

	const dispatchDemandStimuli = async (
		stimuli: readonly WorktreeFileDemandStimulus[],
	): Promise<WorktreeFileSurfaceDemandDispatchResult> => {
		const dispatchResult = demandDispatchTail.then(
			async (): Promise<WorktreeFileSurfaceDemandDispatchResult> =>
				await runDemandDispatchStimuli(stimuli),
			async (): Promise<WorktreeFileSurfaceDemandDispatchResult> =>
				await runDemandDispatchStimuli(stimuli),
		);
		demandDispatchTail = dispatchResult.then(
			(): void => {},
			(): void => {},
		);
		return await dispatchResult;
	};

	const runDemandDispatchStimuli = async (
		stimuli: readonly WorktreeFileDemandStimulus[],
	): Promise<WorktreeFileSurfaceDemandDispatchResult> => {
		const intents = stimuli.flatMap((stimulus): readonly BridgeDemandIntent[] =>
			mapWorktreeFileDemandStimulusToIntents({ stimulus, readContext }),
		);
		let enqueueAcceptedCount = 0;
		const enqueueRejectedCount = 0;
		const loadResults: WorktreeFileSurfaceDemandDispatchLoadResult[] = [];
		const acceptedBatch: BridgeDemandIntent[] = [];
		let acceptedBatchExecutorBytes = 0;
		const flushAcceptedBatch = async (): Promise<void> => {
			if (acceptedBatch.length === 0) {
				return;
			}
			const pendingPreloadLoads: {
				readonly intent: BridgeDemandIntent;
				readonly promise: Promise<WorktreeFileSurfaceDemandDispatchLoadResult>;
			}[] = [];
			for (const batchIntent of acceptedBatch.splice(0, acceptedBatch.length)) {
				pendingPreloadLoads.push({
					intent: batchIntent,
					promise: loadPreloadIntent({
						bodyRegistry,
						executor,
						intent: batchIntent,
						lifecycleTimingsByDemandKey,
						now,
						preloadDispositionByBodyKey,
						registry,
						resourceLoadProbe: props.resourceLoadProbe,
					}),
				});
			}
			acceptedBatchExecutorBytes = 0;
			loadResults.push(
				...(await settlePreloadLoads({
					pendingPreloadLoads,
					registry,
				})),
			);
		};
		for (const intent of intents) {
			const descriptor = registry.lookup(intent.descriptorRef);
			const executorBytes = descriptor?.content.expectedBytes ?? descriptor?.content.maxBytes ?? 0;
			if (
				acceptedBatch.length > 0 &&
				(acceptedBatch.length >= executor.maxConcurrentLoads ||
					acceptedBatchExecutorBytes + executorBytes > executor.maxInFlightBytes)
			) {
				await flushAcceptedBatch();
			}
			enqueueAcceptedCount += 1;
			acceptedBatch.push(intent);
			acceptedBatchExecutorBytes += executorBytes;
		}
		await flushAcceptedBatch();
		return {
			stimulusCount: stimuli.length,
			intentCount: intents.length,
			enqueueAcceptedCount,
			enqueueRejectedCount,
			loadedCount: loadResults.filter((loadResult): boolean => loadResult.ok).length,
			failedCount: loadResults.filter((loadResult): boolean => !loadResult.ok).length,
			loadResults,
			executorInFlightBytesAfter: executor.inFlightBytes,
			executorInFlightCountAfter: executor.inFlightCount,
			executorQueuedBytesAfter: executor.queuedBytes,
			executorQueuedLoadCountAfter: executor.queuedLoadCount,
		};
	};

	const openFile = async (
		openProps: WorktreeFileSurfaceOpenFileProps,
	): Promise<WorktreeFileSurfaceLoadResult> => {
		state = openWorktreeFileSession({
			state,
			descriptor: openProps.descriptor,
			openFileSessionId: openProps.openFileSessionId,
		});
		if (!canFetchWorktreeFileBody(openProps.descriptor)) {
			state = stateWithOpenSessionStatus({
				state,
				openFileSessionId: openProps.openFileSessionId,
				status: 'failed',
			});
			return { ok: false, reason: 'content_unavailable' };
		}
		const loadResult = await loadStimulus({
			bodyRegistry,
			executor,
			lifecycleTimingsByDemandKey,
			now,
			preloadDispositionByBodyKey,
			provisionalChunkConsumersByIntentKey,
			readContext,
			resourceLoadProbe: props.resourceLoadProbe,
			onProvisionalTextChunk: openProps.onProvisionalTextChunk,
			stimulusDescriptor: openProps.descriptor,
			stimulusKind: 'fileSelected',
		});
		state = stateWithOpenSessionStatus({
			state,
			openFileSessionId: openProps.openFileSessionId,
			status: loadResult.ok ? 'fresh' : 'failed',
		});
		return loadResult;
	};

	const refreshOpenFile = async (
		refreshProps: WorktreeFileSurfaceRefreshOpenFileProps,
	): Promise<WorktreeFileSurfaceLoadResult> => {
		const session = state.openFileSessionsById[refreshProps.openFileSessionId];
		if (session?.latestDescriptor === undefined) {
			if (session?.status === 'stale' && session.staleReason === 'sourceReset') {
				return { ok: false, reason: 'source_reset' };
			}
			return { ok: false, reason: 'no_demand' };
		}
		if (
			isDescriptorRefBlockedByReset({
				ref: session.latestDescriptor.contentDescriptor.ref,
				resetReplacementDescriptorKeys,
				resetScope,
				resetSourceIds,
			}) &&
			!resetReplacementDescriptorKeys.has(
				resetDescriptorKeyForBridgeDescriptorRef(session.latestDescriptor.contentDescriptor.ref),
			)
		) {
			return { ok: false, reason: 'source_reset' };
		}
		if (!canFetchWorktreeFileBody(session.latestDescriptor)) {
			return { ok: false, reason: 'content_unavailable' };
		}
		const refreshDescriptor = session.latestDescriptor;
		const refreshDescriptorRef = refreshDescriptor.contentDescriptor.ref;
		const registerResult = registry.register(refreshDescriptor.contentDescriptor);
		if (!registerResult.ok) {
			return { ok: false, reason: 'descriptor_rejected' };
		}
		const refreshResult = refreshWorktreeOpenFileSession({
			state,
			openFileSessionId: refreshProps.openFileSessionId,
		});
		state = refreshResult.state;
		if (refreshResult.stimulus === undefined) {
			return { ok: false, reason: 'no_demand' };
		}
		const loadResult = await loadStimulus({
			bodyRegistry,
			executor,
			lifecycleTimingsByDemandKey,
			now,
			preloadDispositionByBodyKey,
			provisionalChunkConsumersByIntentKey,
			readContext,
			resourceLoadProbe: props.resourceLoadProbe,
			onProvisionalTextChunk: refreshProps.onProvisionalTextChunk,
			stimulusDescriptor: refreshDescriptor,
			stimulusKind: 'explicitRefresh',
		});
		if (
			loadResult.ok &&
			!isOpenFileRefreshStillCurrent({
				state,
				openFileSessionId: refreshProps.openFileSessionId,
				refreshDescriptorRef,
			})
		) {
			return { ok: false, reason: 'stale_completion' };
		}
		state = stateWithOpenSessionStatus({
			state,
			openFileSessionId: refreshProps.openFileSessionId,
			status: loadResult.ok ? 'fresh' : 'stale',
		});
		return loadResult;
	};

	return {
		applyFrame,
		dispatchDemandStimuli,
		openFile,
		refreshOpenFile,
		getState: (): WorktreeFileSurfaceState => state,
		getBodyRegistrySnapshot: () => bodyRegistry.snapshot(),
	};
}
