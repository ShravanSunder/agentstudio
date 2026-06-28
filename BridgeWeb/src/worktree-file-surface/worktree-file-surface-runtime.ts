import { createBridgeBodyRegistry } from '../core/demand/bridge-body-registry.js';
import {
	createBridgeDemandScheduler,
	type BridgeDemandScheduler,
} from '../core/demand/bridge-demand-scheduler.js';
import {
	createBridgeResourceExecutor,
	type BridgeResourceExecutor,
} from '../core/demand/bridge-resource-executor.js';
import type { BridgeDemandIntent, BridgeDemandLane } from '../core/models/bridge-demand-models.js';
import type {
	BridgeDescriptorRef,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import {
	createBridgeResourceDescriptorRegistry,
	type BridgeResourceDescriptorRegistry,
} from '../core/resources/bridge-resource-registry.js';
import type { BridgeTextResourceStreamChunk } from '../core/resources/bridge-resource-stream.js';
import {
	mapWorktreeFileDemandStimulusToIntents,
	type WorktreeFileDemandReadContext,
} from '../features/worktree-file/demand/worktree-file-demand-policy.js';
import {
	applyWorktreeFileProtocolFrame,
	type WorktreeFileMaterializerDelta,
} from '../features/worktree-file/materialization/worktree-file-materializer.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDemandStimulus,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	applyWorktreeFileInvalidationToState,
	createWorktreeFileSurfaceState,
	openWorktreeFileSession,
	refreshWorktreeOpenFileSession,
	type WorktreeFileSurfaceState,
} from '../features/worktree-file/state/worktree-file-state.js';

export interface WorktreeFileSurfaceRuntimeFetchResourceProps {
	readonly descriptor: BridgeResourceDescriptor;
	readonly onTextChunk?: ((chunk: BridgeTextResourceStreamChunk) => void) | undefined;
	readonly resourceUrl: string;
	readonly signal: AbortSignal;
}

export interface WorktreeFileSurfaceRuntimeFetchedResource {
	readonly authoritative: boolean;
	readonly byteLength: number;
	readText(): string;
}

export function makeWorktreeFileSurfaceRuntimeFetchedResource(
	props:
		| string
		| {
				readonly authoritative?: boolean;
				readonly text: string;
		  },
): WorktreeFileSurfaceRuntimeFetchedResource {
	const text = typeof props === 'string' ? props : props.text;
	return {
		authoritative: typeof props === 'string' ? true : (props.authoritative ?? true),
		byteLength: new TextEncoder().encode(text).byteLength,
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
	readonly executorQueuedBytesAfter: number;
	readonly executorQueuedBytesBefore: number;
	readonly executorQueuedLoadCountAfter: number;
	readonly executorQueuedLoadCountBefore: number;
	readonly lane: BridgeDemandLane;
	readonly schedulerQueuedEstimatedBytesAfter: number;
	readonly schedulerQueuedEstimatedBytesBefore: number;
	readonly schedulerQueuedIntentCountAfter: number;
	readonly schedulerQueuedIntentCountBefore: number;
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
	readonly schedulerQueuedEstimatedBytesAfter: number;
	readonly schedulerQueuedIntentCountAfter: number;
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
const worktreeFileResourceExecutorMaxConcurrentLoads = 8;
const worktreeFileResourceExecutorMaxInFlightBytes = 8 * 1024 * 1024;
const worktreeFileResourceExecutorMaxQueuedLoads = 128;
const worktreeFileResourceExecutorMaxQueuedBytes = 8 * 1024 * 1024;
const worktreeFileDemandMaxQueuedIntentsPerLane = 128;
const worktreeFileDemandMaxQueuedEstimatedBytes = 8 * 1024 * 1024;
const sourceLessResetIdentity = 'source-less-reset';

interface WorktreeFileSourceLessResetScope {
	hasSourceLessReset: boolean;
	postResetAnchorSource: WorktreeFileSurfaceSourceIdentity | null;
}

export function createWorktreeFileSurfaceRuntime(
	props: WorktreeFileSurfaceRuntimeProps,
): WorktreeFileSurfaceRuntime {
	const registry = createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: {
			'worktree-file': new Set([
				'worktree.treeWindow',
				'worktree.treeDeltaOperations',
				'worktree.status',
				'worktree.fileContent',
				'worktree.fileRange',
			]),
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
	const scheduler = createBridgeDemandScheduler({
		maxQueuedIntentsPerLane: worktreeFileDemandMaxQueuedIntentsPerLane,
		maxQueuedEstimatedBytes: worktreeFileDemandMaxQueuedEstimatedBytes,
	});
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
				resourceUrl: descriptor.resourceUrl,
				signal,
			});
			if (fetchedResource.authoritative) {
				bodyRegistry.put({
					cacheKey: descriptor.resourceUrl,
					freshnessKey: intent.freshnessKey,
					body: fetchedResource,
					byteLength: fetchedResource.byteLength,
				});
			}
			return {
				authoritative: fetchedResource.authoritative,
				content: fetchedResource,
				byteLength: fetchedResource.byteLength,
			};
		},
	});
	const now = props.now ?? ((): number => performance.now());
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
								scheduler,
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
		let enqueueRejectedCount = 0;
		const loadResults: WorktreeFileSurfaceDemandDispatchLoadResult[] = [];
		const acceptedBatch: BridgeDemandIntent[] = [];
		let acceptedBatchSchedulerBytes = 0;
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
				const queuedIntent = scheduler.dequeueNextMatching(
					(candidateIntent): boolean =>
						candidateIntent.dedupeKey === batchIntent.dedupeKey &&
						candidateIntent.freshnessKey === batchIntent.freshnessKey,
				);
				if (queuedIntent === null) {
					const descriptor = registry.lookup(batchIntent.descriptorRef);
					loadResults.push({
						ok: false,
						descriptorId: descriptor?.descriptorId ?? null,
						lane: batchIntent.lane,
						reason: 'stale_completion',
					});
					continue;
				}
				pendingPreloadLoads.push({
					intent: queuedIntent,
					promise: loadPreloadIntent({
						bodyRegistry,
						executor,
						intent: queuedIntent,
						now,
						preloadDispositionByBodyKey,
						registry,
						scheduler,
					}),
				});
			}
			acceptedBatchSchedulerBytes = 0;
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
			const schedulerBytes = descriptor?.content.expectedBytes ?? 0;
			const executorBytes = descriptor?.content.expectedBytes ?? descriptor?.content.maxBytes ?? 0;
			if (
				acceptedBatch.length > 0 &&
				(acceptedBatch.length >= executor.maxConcurrentLoads ||
					acceptedBatchSchedulerBytes + schedulerBytes > scheduler.maxQueuedEstimatedBytes ||
					acceptedBatchExecutorBytes + executorBytes > executor.maxInFlightBytes)
			) {
				await flushAcceptedBatch();
			}
			const enqueueResult = scheduler.enqueue({
				intent,
				...(descriptor?.content.expectedBytes === undefined
					? {}
					: { estimatedBytes: schedulerBytes }),
			});
			if (enqueueResult.ok) {
				enqueueAcceptedCount += 1;
				acceptedBatch.push(intent);
				acceptedBatchSchedulerBytes += schedulerBytes;
				acceptedBatchExecutorBytes += executorBytes;
			} else {
				enqueueRejectedCount += 1;
				loadResults.push({
					ok: false,
					descriptorId: descriptor?.descriptorId ?? null,
					lane: intent.lane,
					reason: pressureReasonForSchedulerRejection(enqueueResult.reason),
				});
			}
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
			schedulerQueuedEstimatedBytesAfter: scheduler.queuedEstimatedBytes,
			schedulerQueuedIntentCountAfter: scheduler.queuedIntentCount,
			executorInFlightBytesAfter: executor.inFlightBytes,
			executorInFlightCountAfter: executor.inFlightCount,
			executorQueuedBytesAfter: executor.queuedBytes,
			executorQueuedLoadCountAfter: executor.queuedLoadCount,
		};
	};

	const openFile = async (
		openProps: WorktreeFileSurfaceOpenFileProps,
	): Promise<WorktreeFileSurfaceLoadResult> => {
		await demandDispatchTail;
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
			scheduler,
			executor,
			now,
			preloadDispositionByBodyKey,
			provisionalChunkConsumersByIntentKey,
			readContext,
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
			scheduler,
			executor,
			now,
			preloadDispositionByBodyKey,
			provisionalChunkConsumersByIntentKey,
			readContext,
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

function isDescriptorFromSourceLessResetAnchor(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly resetScope: WorktreeFileSourceLessResetScope;
}): boolean {
	return (
		props.resetScope.postResetAnchorSource !== null &&
		areWorktreeFileSourceIdentitiesEqual(
			props.descriptor.sourceIdentity,
			props.resetScope.postResetAnchorSource,
		)
	);
}

function areWorktreeFileSourceIdentitiesEqual(
	left: WorktreeFileSurfaceSourceIdentity,
	right: WorktreeFileSurfaceSourceIdentity,
): boolean {
	return (
		left.sourceId === right.sourceId &&
		left.repoId === right.repoId &&
		left.worktreeId === right.worktreeId &&
		left.subscriptionGeneration === right.subscriptionGeneration &&
		left.sourceCursor === right.sourceCursor &&
		left.rootRevisionToken === right.rootRevisionToken
	);
}

function applyReplacementDescriptorToOpenSessions(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly state: WorktreeFileSurfaceState;
}): WorktreeFileSurfaceState {
	return {
		...props.state,
		openFileSessionsById: Object.fromEntries(
			Object.entries(props.state.openFileSessionsById).map(([sessionId, session]) => {
				if (session.fileId !== props.descriptor.fileId && session.path !== props.descriptor.path) {
					return [sessionId, session];
				}
				return [
					sessionId,
					{
						...session,
						latestDescriptor: props.descriptor,
						latestDescriptorRef: props.descriptor.contentDescriptor.ref,
					},
				];
			}),
		),
	};
}

function isOpenFileRefreshStillCurrent(props: {
	readonly state: WorktreeFileSurfaceState;
	readonly openFileSessionId: string;
	readonly refreshDescriptorRef: BridgeDescriptorRef;
}): boolean {
	const session = props.state.openFileSessionsById[props.openFileSessionId];
	return (
		session !== undefined &&
		session.status === 'refreshing' &&
		areBridgeDescriptorRefsEqual(session.descriptorRef, props.refreshDescriptorRef) &&
		(session.latestDescriptorRef === undefined ||
			areBridgeDescriptorRefsEqual(session.latestDescriptorRef, props.refreshDescriptorRef))
	);
}

function areBridgeDescriptorRefsEqual(
	left: BridgeDescriptorRef,
	right: BridgeDescriptorRef,
): boolean {
	return (
		left.descriptorId === right.descriptorId &&
		left.expectedProtocol === right.expectedProtocol &&
		left.expectedResourceKind === right.expectedResourceKind &&
		left.expectedIdentity.paneId === right.expectedIdentity.paneId &&
		left.expectedIdentity.sourceId === right.expectedIdentity.sourceId &&
		left.expectedIdentity.generation === right.expectedIdentity.generation &&
		left.expectedIdentity.cursor === right.expectedIdentity.cursor
	);
}

function makeWorktreeFileDemandReadContext(props: {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly resetScope: WorktreeFileSourceLessResetScope;
	readonly resetSourceIds: ReadonlySet<string>;
	readonly resetReplacementDescriptorKeys: ReadonlySet<string>;
}): WorktreeFileDemandReadContext {
	return {
		getDescriptorState: (ref: BridgeDescriptorRef) => {
			const resetDescriptorKey = resetDescriptorKeyForBridgeDescriptorRef(ref);
			if (
				isDescriptorRefBlockedByReset({
					ref,
					resetReplacementDescriptorKeys: props.resetReplacementDescriptorKeys,
					resetScope: props.resetScope,
					resetSourceIds: props.resetSourceIds,
				}) &&
				!props.resetReplacementDescriptorKeys.has(resetDescriptorKey)
			) {
				return {
					kind: 'reset',
					sourceIdentity: ref.expectedIdentity.sourceId ?? sourceLessResetIdentity,
				};
			}
			const descriptor = props.registry.lookup(ref);
			if (descriptor === null) {
				return { kind: 'missing' };
			}
			return {
				kind: 'valid',
				freshnessKey: demandFreshnessKeyForWorktreeDescriptorRef(ref),
				needsBodyOrWindow: true,
			};
		},
		getViewInterest: () => ({ kind: 'none' }),
		buildDemandKeys: (ref: BridgeDescriptorRef) => ({
			orderingKey: `${ref.expectedResourceKind}:${ref.descriptorId}`,
			dedupeKey: `${ref.expectedIdentity.paneId}:${ref.expectedProtocol}:${ref.expectedResourceKind}:${ref.descriptorId}`,
			freshnessKey: demandFreshnessKeyForWorktreeDescriptorRef(ref),
			cancellationGroup: demandCancellationGroupForWorktreeDescriptorRef(ref),
		}),
	};
}

function isDescriptorRefBlockedByReset(props: {
	readonly ref: BridgeDescriptorRef;
	readonly resetReplacementDescriptorKeys: ReadonlySet<string>;
	readonly resetScope: WorktreeFileSourceLessResetScope;
	readonly resetSourceIds: ReadonlySet<string>;
}): boolean {
	const sourceId = props.ref.expectedIdentity.sourceId;
	if (sourceId !== undefined && props.resetSourceIds.has(sourceId)) {
		return true;
	}
	if (!props.resetScope.hasSourceLessReset) {
		return false;
	}
	return !props.resetReplacementDescriptorKeys.has(
		resetDescriptorKeyForBridgeDescriptorRef(props.ref),
	);
}

function deleteResetReplacementDescriptorKeysForSource(props: {
	readonly resetReplacementDescriptorKeys: Set<string>;
	readonly sourceId: string;
}): void {
	const sourcePrefix = `${props.sourceId}:`;
	for (const descriptorKey of props.resetReplacementDescriptorKeys) {
		if (descriptorKey.startsWith(sourcePrefix)) {
			props.resetReplacementDescriptorKeys.delete(descriptorKey);
		}
	}
}

function resetDescriptorKeyForBridgeDescriptorRef(ref: BridgeDescriptorRef): string {
	return `${ref.expectedIdentity.sourceId ?? 'source-none'}:${demandFreshnessKeyForWorktreeDescriptorRef(ref)}`;
}

async function settlePreloadLoads(props: {
	readonly pendingPreloadLoads: readonly {
		readonly intent: BridgeDemandIntent;
		readonly promise: Promise<WorktreeFileSurfaceDemandDispatchLoadResult>;
	}[];
	readonly registry: BridgeResourceDescriptorRegistry;
}): Promise<readonly WorktreeFileSurfaceDemandDispatchLoadResult[]> {
	const settledResults = await Promise.allSettled(
		props.pendingPreloadLoads.map(({ promise }) => promise),
	);
	return settledResults.map((settledResult, index): WorktreeFileSurfaceDemandDispatchLoadResult => {
		switch (settledResult.status) {
			case 'fulfilled':
				return settledResult.value;
			case 'rejected': {
				const pendingPreloadLoad = props.pendingPreloadLoads[index];
				if (pendingPreloadLoad === undefined) {
					throw new Error('Settled preload result did not have a matching pending intent.');
				}
				const descriptor = props.registry.lookup(pendingPreloadLoad.intent.descriptorRef);
				return {
					ok: false,
					descriptorId: descriptor?.descriptorId ?? null,
					lane: pendingPreloadLoad.intent.lane,
					reason: 'load_failed',
				};
			}
		}
		return assertNever(settledResult);
	});
}

async function loadPreloadIntent(props: {
	readonly bodyRegistry: ReturnType<
		typeof createBridgeBodyRegistry<WorktreeFileSurfaceRuntimeFetchedResource>
	>;
	readonly scheduler: BridgeDemandScheduler;
	readonly executor: BridgeResourceExecutor<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly now: () => number;
	readonly intent: BridgeDemandIntent;
	readonly preloadDispositionByBodyKey: Map<string, WorktreeFileSurfaceLoadDisposition>;
}): Promise<WorktreeFileSurfaceDemandDispatchLoadResult> {
	const queuedIntentCountBefore = props.scheduler.queuedIntentCount;
	const queuedEstimatedBytesBefore = props.scheduler.queuedEstimatedBytes;
	const executorInFlightCountBefore = props.executor.inFlightCount;
	const executorInFlightBytesBefore = props.executor.inFlightBytes;
	const executorQueuedLoadCountBefore = props.executor.queuedLoadCount;
	const executorQueuedBytesBefore = props.executor.queuedBytes;
	const descriptor = props.registry.lookup(props.intent.descriptorRef);
	const estimatedBytes = descriptor?.content.expectedBytes ?? null;
	const wasCachedBeforeLoad =
		descriptor === null
			? false
			: props.bodyRegistry.get({
					cacheKey: descriptor.resourceUrl,
					freshnessKey: props.intent.freshnessKey,
				}) !== null;
	const cachedPreloadDisposition =
		descriptor === null
			? undefined
			: props.preloadDispositionByBodyKey.get(
					bodyProvenanceKey({
						freshnessKey: props.intent.freshnessKey,
						resourceUrl: descriptor.resourceUrl,
					}),
				);
	const loadStartedAtMilliseconds = props.now();
	const result = await props.executor.load(props.intent);
	const loadFinishedAtMilliseconds = props.now();
	if (!result.ok) {
		return {
			ok: false,
			descriptorId: descriptor?.descriptorId ?? null,
			lane: props.intent.lane,
			reason: result.reason,
		};
	}
	if (!result.authoritative) {
		return {
			ok: false,
			descriptorId: result.descriptor.descriptorId,
			lane: props.intent.lane,
			reason: 'preview_only',
		};
	}
	const disposition = preloadDispositionForLane({
		cachedPreloadDisposition,
		lane: props.intent.lane,
		wasCachedBeforeLoad,
	});
	if (disposition !== 'cache-hit') {
		props.preloadDispositionByBodyKey.set(
			bodyProvenanceKey({
				freshnessKey: props.intent.freshnessKey,
				resourceUrl: result.descriptor.resourceUrl,
			}),
			disposition,
		);
	}
	return {
		dedupeKey: props.intent.dedupeKey,
		ok: true,
		authoritative: result.authoritative,
		byteLength: result.byteLength,
		descriptorId: result.descriptor.descriptorId,
		freshnessKey: props.intent.freshnessKey,
		loadTelemetry: {
			disposition,
			durationMilliseconds: Math.max(0, loadFinishedAtMilliseconds - loadStartedAtMilliseconds),
			estimatedBytes,
			executorInFlightBytesAfter: props.executor.inFlightBytes,
			executorInFlightBytesBefore,
			executorInFlightCountAfter: props.executor.inFlightCount,
			executorInFlightCountBefore,
			executorQueuedBytesAfter: props.executor.queuedBytes,
			executorQueuedBytesBefore,
			executorQueuedLoadCountAfter: props.executor.queuedLoadCount,
			executorQueuedLoadCountBefore,
			lane: props.intent.lane,
			schedulerQueuedEstimatedBytesAfter: props.scheduler.queuedEstimatedBytes,
			schedulerQueuedEstimatedBytesBefore: queuedEstimatedBytesBefore,
			schedulerQueuedIntentCountAfter: props.scheduler.queuedIntentCount,
			schedulerQueuedIntentCountBefore: queuedIntentCountBefore,
		},
	};
}

async function loadStimulus(props: {
	readonly bodyRegistry: ReturnType<
		typeof createBridgeBodyRegistry<WorktreeFileSurfaceRuntimeFetchedResource>
	>;
	readonly scheduler: BridgeDemandScheduler;
	readonly executor: BridgeResourceExecutor<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly now: () => number;
	readonly preloadDispositionByBodyKey: Map<string, WorktreeFileSurfaceLoadDisposition>;
	readonly provisionalChunkConsumersByIntentKey: Map<
		string,
		(chunk: WorktreeFileSurfaceProvisionalTextChunk) => void
	>;
	readonly readContext: WorktreeFileDemandReadContext;
	readonly onProvisionalTextChunk?:
		| ((chunk: WorktreeFileSurfaceProvisionalTextChunk) => void)
		| undefined;
	readonly stimulusDescriptor: WorktreeFileDescriptor;
	readonly stimulusKind: 'fileSelected' | 'explicitRefresh';
}): Promise<WorktreeFileSurfaceLoadResult> {
	const queuedIntentCountBefore = props.scheduler.queuedIntentCount;
	const queuedEstimatedBytesBefore = props.scheduler.queuedEstimatedBytes;
	const executorInFlightCountBefore = props.executor.inFlightCount;
	const executorInFlightBytesBefore = props.executor.inFlightBytes;
	const executorQueuedLoadCountBefore = props.executor.queuedLoadCount;
	const executorQueuedBytesBefore = props.executor.queuedBytes;
	const expectedBytes =
		props.stimulusDescriptor.contentDescriptor.descriptor.content.expectedBytes ?? null;
	const wasCachedBeforeLoad =
		props.bodyRegistry.get({
			cacheKey: props.stimulusDescriptor.contentDescriptor.descriptor.resourceUrl,
			freshnessKey: demandFreshnessKeyForWorktreeDescriptorRef(
				props.stimulusDescriptor.contentDescriptor.ref,
			),
		}) !== null;
	const cachedPreloadDisposition = props.preloadDispositionByBodyKey.get(
		bodyProvenanceKey({
			freshnessKey: demandFreshnessKeyForWorktreeDescriptorRef(
				props.stimulusDescriptor.contentDescriptor.ref,
			),
			resourceUrl: props.stimulusDescriptor.contentDescriptor.descriptor.resourceUrl,
		}),
	);
	const intents = mapWorktreeFileDemandStimulusToIntents({
		stimulus: {
			kind: props.stimulusKind,
			descriptorRef: props.stimulusDescriptor.contentDescriptor.ref,
		},
		readContext: props.readContext,
	});
	if (intents.length === 0) {
		const descriptor = props.stimulusDescriptor.contentDescriptor.descriptor;
		const isMissing =
			props.readContext.getDescriptorState(props.stimulusDescriptor.contentDescriptor.ref).kind ===
			'missing';
		return {
			ok: false,
			reason: isMissing
				? 'descriptor_missing'
				: descriptor.identity.sourceId === undefined
					? 'no_demand'
					: 'source_reset',
		};
	}
	for (const intent of intents) {
		const estimatedBytes =
			props.stimulusDescriptor.contentDescriptor.descriptor.content.expectedBytes;
		const enqueueResult = props.scheduler.enqueue({
			intent,
			...(estimatedBytes === undefined ? {} : { estimatedBytes }),
		});
		if (!enqueueResult.ok) {
			return {
				ok: false,
				reason: pressureReasonForSchedulerRejection(enqueueResult.reason),
			};
		}
	}
	const nextIntent = props.scheduler.dequeueNext();
	if (nextIntent === null) {
		return { ok: false, reason: 'no_demand' };
	}
	const loadStartedAtMilliseconds = props.now();
	const streamConsumerKey = streamConsumerKeyForIntent(nextIntent);
	if (props.onProvisionalTextChunk !== undefined) {
		props.provisionalChunkConsumersByIntentKey.set(streamConsumerKey, props.onProvisionalTextChunk);
	}
	let result: Awaited<ReturnType<typeof props.executor.load>>;
	let loadFinishedAtMilliseconds: number;
	try {
		result = await props.executor.load(nextIntent);
		loadFinishedAtMilliseconds = props.now();
	} finally {
		if (
			props.provisionalChunkConsumersByIntentKey.get(streamConsumerKey) ===
			props.onProvisionalTextChunk
		) {
			props.provisionalChunkConsumersByIntentKey.delete(streamConsumerKey);
		}
	}
	if (!result.ok) {
		return result;
	}
	if (!result.authoritative) {
		return { ok: false, reason: 'preview_only' };
	}
	return {
		ok: true,
		authoritative: result.authoritative,
		byteLength: result.byteLength,
		content: result.content,
		descriptorId: result.descriptor.descriptorId,
		loadTelemetry: {
			disposition: loadDispositionForStimulus({
				cachedPreloadDisposition,
				stimulusKind: props.stimulusKind,
				wasCachedBeforeLoad,
			}),
			durationMilliseconds: Math.max(0, loadFinishedAtMilliseconds - loadStartedAtMilliseconds),
			estimatedBytes: expectedBytes,
			executorInFlightBytesAfter: props.executor.inFlightBytes,
			executorInFlightBytesBefore,
			executorInFlightCountAfter: props.executor.inFlightCount,
			executorInFlightCountBefore,
			executorQueuedBytesAfter: props.executor.queuedBytes,
			executorQueuedBytesBefore,
			executorQueuedLoadCountAfter: props.executor.queuedLoadCount,
			executorQueuedLoadCountBefore,
			lane: nextIntent.lane,
			schedulerQueuedEstimatedBytesAfter: props.scheduler.queuedEstimatedBytes,
			schedulerQueuedEstimatedBytesBefore: queuedEstimatedBytesBefore,
			schedulerQueuedIntentCountAfter: props.scheduler.queuedIntentCount,
			schedulerQueuedIntentCountBefore: queuedIntentCountBefore,
		},
	};
}

function pressureReasonForSchedulerRejection(
	reason: 'lane_queue_full' | 'queued_byte_limit_exceeded',
): 'byte_budget_exceeded' | 'concurrency_exceeded' {
	switch (reason) {
		case 'lane_queue_full':
			return 'concurrency_exceeded';
		case 'queued_byte_limit_exceeded':
			return 'byte_budget_exceeded';
	}
	return assertNever(reason);
}

function loadDispositionForStimulus(props: {
	readonly cachedPreloadDisposition: WorktreeFileSurfaceLoadDisposition | undefined;
	readonly stimulusKind: 'fileSelected' | 'explicitRefresh';
	readonly wasCachedBeforeLoad: boolean;
}): WorktreeFileSurfaceLoadDisposition {
	if (props.wasCachedBeforeLoad) {
		return props.cachedPreloadDisposition ?? 'cache-hit';
	}
	return props.stimulusKind === 'explicitRefresh' ? 'refreshed' : 'cold-loaded';
}

function preloadDispositionForLane(props: {
	readonly cachedPreloadDisposition: WorktreeFileSurfaceLoadDisposition | undefined;
	readonly lane: BridgeDemandLane;
	readonly wasCachedBeforeLoad: boolean;
}): WorktreeFileSurfaceLoadDisposition {
	if (props.wasCachedBeforeLoad) {
		return props.cachedPreloadDisposition ?? 'cache-hit';
	}
	switch (props.lane) {
		case 'active':
			return 'active-preloaded';
		case 'idle':
			return 'idle-preloaded';
		case 'nearby':
			return 'nearby-preloaded';
		case 'speculative':
			return 'speculative-preloaded';
		case 'visible':
			return 'visible-preloaded';
		case 'foreground':
			return 'cold-loaded';
	}
	return assertNever(props.lane);
}

function assertNever(value: never): never {
	throw new Error(`Unhandled WorktreeFileSurfaceRuntime case: ${String(value)}`);
}

function bodyProvenanceKey(props: {
	readonly resourceUrl: string;
	readonly freshnessKey: string;
}): string {
	return `${props.resourceUrl}\u0000${props.freshnessKey}`;
}

function streamConsumerKeyForIntent(intent: BridgeDemandIntent): string {
	return `${intent.dedupeKey}\u0000${intent.freshnessKey}`;
}

function cancelSourceDemand(props: {
	readonly executor: BridgeResourceExecutor<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly paneId: string;
	readonly scheduler: BridgeDemandScheduler;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}): number {
	const cancellationGroup = demandCancellationGroupForSource({
		paneId: props.paneId,
		source: props.source,
	});
	return (
		props.scheduler.cancelGroup(cancellationGroup) + props.executor.cancelGroup(cancellationGroup)
	);
}

function markSourceOpenSessionsStale(props: {
	readonly source: WorktreeFileSurfaceSourceIdentity;
	readonly state: WorktreeFileSurfaceState;
}): WorktreeFileSurfaceState {
	return {
		...props.state,
		openFileSessionsById: Object.fromEntries(
			Object.entries(props.state.openFileSessionsById).map(([sessionId, session]) => {
				const sessionSourceId =
					session.latestDescriptor?.sourceIdentity.sourceId ??
					session.descriptorRef.expectedIdentity.sourceId;
				if (sessionSourceId !== props.source.sourceId) {
					return [sessionId, session];
				}
				return [
					sessionId,
					{
						...session,
						status: 'stale',
						staleReason: 'sourceReset',
					},
				];
			}),
		),
	};
}

function markAllOpenSessionsStale(props: {
	readonly state: WorktreeFileSurfaceState;
}): WorktreeFileSurfaceState {
	return {
		...props.state,
		openFileSessionsById: Object.fromEntries(
			Object.entries(props.state.openFileSessionsById).map(([sessionId, session]) => [
				sessionId,
				{
					...session,
					status: 'stale',
					staleReason: 'sourceReset',
				},
			]),
		),
	};
}

function stateWithOpenSessionStatus(props: {
	readonly state: WorktreeFileSurfaceState;
	readonly openFileSessionId: string;
	readonly status: 'failed' | 'fresh' | 'stale';
}): WorktreeFileSurfaceState {
	const session = props.state.openFileSessionsById[props.openFileSessionId];
	if (session === undefined) {
		return props.state;
	}
	return {
		...props.state,
		openFileSessionsById: {
			...props.state.openFileSessionsById,
			[props.openFileSessionId]: {
				...session,
				status: props.status,
			},
		},
	};
}

function demandFreshnessKeyForWorktreeDescriptorRef(ref: BridgeDescriptorRef): string {
	return [
		ref.expectedIdentity.paneId,
		ref.expectedProtocol,
		ref.expectedIdentity.sourceId ?? 'source-none',
		ref.expectedIdentity.generation ?? 'generation-none',
		ref.expectedIdentity.revision ?? 'revision-none',
		ref.expectedIdentity.cursor ?? 'cursor-none',
		ref.descriptorId,
	].join(':');
}

function demandCancellationGroupForWorktreeDescriptorRef(ref: BridgeDescriptorRef): string {
	return `${ref.expectedProtocol}:${ref.expectedIdentity.paneId}:${ref.expectedIdentity.sourceId ?? 'source-none'}`;
}

function demandCancellationGroupForSource(props: {
	readonly paneId: string;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}): string {
	return `worktree-file:${props.paneId}:${props.source.sourceId}`;
}

function canFetchWorktreeFileBody(descriptor: WorktreeFileDescriptor): boolean {
	return !descriptor.isBinary && descriptor.virtualizedExtentKind !== 'unavailable';
}
