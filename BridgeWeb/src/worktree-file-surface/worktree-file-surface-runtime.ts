import { createBridgeBodyRegistry } from '../core/demand/bridge-body-registry.js';
import {
	createBridgeDemandScheduler,
	type BridgeDemandScheduler,
} from '../core/demand/bridge-demand-scheduler.js';
import {
	createBridgeResourceExecutor,
	type BridgeResourceExecutor,
} from '../core/demand/bridge-resource-executor.js';
import type {
	BridgeDescriptorRef,
	BridgeResourceDescriptor,
} from '../core/models/bridge-resource-descriptor.js';
import {
	createBridgeResourceDescriptorRegistry,
	type BridgeResourceDescriptorRegistry,
} from '../core/resources/bridge-resource-registry.js';
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
	readonly resourceUrl: string;
	readonly signal: AbortSignal;
}

export interface WorktreeFileSurfaceRuntimeProps {
	readonly paneId: string;
	readonly fetchResource: (props: WorktreeFileSurfaceRuntimeFetchResourceProps) => Promise<string>;
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
	readonly openFileSessionId: string;
}

export interface WorktreeFileSurfaceRefreshOpenFileProps {
	readonly openFileSessionId: string;
}

export type WorktreeFileSurfaceLoadResult =
	| {
			readonly ok: true;
			readonly body: string;
			readonly descriptorId: string;
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
				| 'source_reset'
				| 'stale_completion';
	  };

export interface WorktreeFileSurfaceRuntime {
	applyFrame(frame: WorktreeFileProtocolFrame): WorktreeFileSurfaceApplyFrameResult;
	openFile(props: WorktreeFileSurfaceOpenFileProps): Promise<WorktreeFileSurfaceLoadResult>;
	refreshOpenFile(
		props: WorktreeFileSurfaceRefreshOpenFileProps,
	): Promise<WorktreeFileSurfaceLoadResult>;
	getState(): WorktreeFileSurfaceState;
	getBodyRegistrySnapshot(): ReturnType<
		ReturnType<typeof createBridgeBodyRegistry<string>>['snapshot']
	>;
}

const worktreeFileBodyRegistryMaxBytes = 24 * 1024 * 1024;
const worktreeFileResourceExecutorMaxConcurrentLoads = 8;
const worktreeFileResourceExecutorMaxInFlightBytes = 8 * 1024 * 1024;
const worktreeFileResourceExecutorMaxQueuedLoads = 128;
const worktreeFileResourceExecutorMaxQueuedBytes = 8 * 1024 * 1024;
const worktreeFileDemandMaxQueuedIntentsPerLane = 128;
const worktreeFileDemandMaxQueuedEstimatedBytes = 8 * 1024 * 1024;

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
	const bodyRegistry = createBridgeBodyRegistry<string>({
		maxBytes: worktreeFileBodyRegistryMaxBytes,
	});
	const resetSourceIds = new Set<string>();
	const resetReplacementDescriptorKeys = new Set<string>();
	let state = createWorktreeFileSurfaceState();
	const scheduler = createBridgeDemandScheduler({
		maxQueuedIntentsPerLane: worktreeFileDemandMaxQueuedIntentsPerLane,
		maxQueuedEstimatedBytes: worktreeFileDemandMaxQueuedEstimatedBytes,
	});
	const executor = createBridgeResourceExecutor<string>({
		registry,
		maxConcurrentLoads: worktreeFileResourceExecutorMaxConcurrentLoads,
		maxInFlightBytes: worktreeFileResourceExecutorMaxInFlightBytes,
		maxQueuedLoads: worktreeFileResourceExecutorMaxQueuedLoads,
		maxQueuedBytes: worktreeFileResourceExecutorMaxQueuedBytes,
		isFresh: (intent): boolean => {
			const sourceId = intent.descriptorRef.expectedIdentity.sourceId;
			if (sourceId === undefined || !resetSourceIds.has(sourceId)) {
				return true;
			}
			return resetReplacementDescriptorKeys.has(
				resetDescriptorKeyForBridgeDescriptorRef(intent.descriptorRef),
			);
		},
		loadResource: async ({ descriptor, intent, signal }) => {
			const cachedBody = bodyRegistry.get({
				cacheKey: descriptor.resourceUrl,
				freshnessKey: intent.freshnessKey,
			});
			if (cachedBody !== null) {
				return {
					body: cachedBody,
					byteLength: encodedByteLength(cachedBody),
				};
			}
			const body = await props.fetchResource({
				descriptor,
				resourceUrl: descriptor.resourceUrl,
				signal,
			});
			const byteLength = encodedByteLength(body);
			bodyRegistry.put({
				cacheKey: descriptor.resourceUrl,
				freshnessKey: intent.freshnessKey,
				body,
				byteLength,
			});
			return { body, byteLength };
		},
	});
	const readContext = makeWorktreeFileDemandReadContext({
		registry,
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
				}
				return {
					ok: true,
					deltaKind: delta.kind,
					cancelledDemandCount,
				};
			}
			case 'fileDescriptor':
				if (resetSourceIds.has(delta.descriptor.sourceIdentity.sourceId)) {
					resetReplacementDescriptorKeys.add(
						resetDescriptorKeyForBridgeDescriptorRef(delta.descriptor.contentDescriptor.ref),
					);
				}
				state = applyReplacementDescriptorToOpenSessions({
					descriptor: delta.descriptor,
					state,
				});
				return {
					ok: true,
					deltaKind: delta.kind,
				};
			case 'snapshot':
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
			scheduler,
			executor,
			readContext,
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
			return { ok: false, reason: 'no_demand' };
		}
		if (
			resetSourceIds.has(session.latestDescriptor.sourceIdentity.sourceId) &&
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
			scheduler,
			executor,
			readContext,
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
		openFile,
		refreshOpenFile,
		getState: (): WorktreeFileSurfaceState => state,
		getBodyRegistrySnapshot: () => bodyRegistry.snapshot(),
	};
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
	readonly resetSourceIds: ReadonlySet<string>;
	readonly resetReplacementDescriptorKeys: ReadonlySet<string>;
}): WorktreeFileDemandReadContext {
	return {
		getDescriptorState: (ref: BridgeDescriptorRef) => {
			const sourceId = ref.expectedIdentity.sourceId;
			const resetDescriptorKey = resetDescriptorKeyForBridgeDescriptorRef(ref);
			if (
				sourceId !== undefined &&
				props.resetSourceIds.has(sourceId) &&
				!props.resetReplacementDescriptorKeys.has(resetDescriptorKey)
			) {
				return { kind: 'reset', sourceIdentity: sourceId };
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

async function loadStimulus(props: {
	readonly scheduler: BridgeDemandScheduler;
	readonly executor: BridgeResourceExecutor<string>;
	readonly readContext: WorktreeFileDemandReadContext;
	readonly stimulusDescriptor: WorktreeFileDescriptor;
	readonly stimulusKind: 'fileSelected' | 'explicitRefresh';
}): Promise<WorktreeFileSurfaceLoadResult> {
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
		props.scheduler.enqueue({
			intent,
			...(estimatedBytes === undefined ? {} : { estimatedBytes }),
		});
	}
	const nextIntent = props.scheduler.dequeueNext();
	if (nextIntent === null) {
		return { ok: false, reason: 'no_demand' };
	}
	const result = await props.executor.load(nextIntent);
	if (!result.ok) {
		return result;
	}
	return {
		ok: true,
		body: result.body,
		descriptorId: result.descriptor.descriptorId,
	};
}

function cancelSourceDemand(props: {
	readonly executor: BridgeResourceExecutor<string>;
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

function encodedByteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}

function canFetchWorktreeFileBody(descriptor: WorktreeFileDescriptor): boolean {
	return !descriptor.isBinary && descriptor.virtualizedExtentKind !== 'unavailable';
}
