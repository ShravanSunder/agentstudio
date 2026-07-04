import { createBridgeBodyRegistry } from '../core/demand/bridge-body-registry.js';
import type {
	BridgeResourceExecutor,
	BridgeResourceExecutorLifecycleEvent,
} from '../core/demand/bridge-resource-executor.js';
import type { BridgeDemandIntent, BridgeDemandLane } from '../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../core/models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import {
	mapWorktreeFileDemandStimulusToIntents,
	type WorktreeFileDemandReadContext,
} from '../features/worktree-file/demand/worktree-file-demand-policy.js';
import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileSurfaceSourceIdentity } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type {
	WorktreeFileSurfaceState,
	WorktreeOpenFileSessionState,
} from '../features/worktree-file/state/worktree-file-state.js';
import type {
	WorktreeFileSurfaceDemandDispatchLoadResult,
	WorktreeFileSurfaceLoadDisposition,
	WorktreeFileSurfaceLoadResult,
	WorktreeFileSurfaceLoadTelemetry,
	WorktreeFileSurfaceProvisionalTextChunk,
	WorktreeFileSurfaceResourceLoadProbe,
	WorktreeFileSurfaceResourceLoadProbeSample,
	WorktreeFileSurfaceRuntimeFetchedResource,
} from './worktree-file-surface-runtime.js';

interface MutableWorktreeFileSurfaceResourceLoadTiming {
	bodyRegistryCommitMilliseconds: number | null;
	firstChunkWaitMilliseconds?: number | null | undefined;
	responseWaitMilliseconds?: number | null | undefined;
	streamReadMilliseconds?: number | null | undefined;
}

export interface WorktreeFileSourceLessResetScope {
	hasSourceLessReset: boolean;
	postResetAnchorSource: WorktreeFileSurfaceSourceIdentity | null;
}

export interface WorktreeFileDemandLifecycleTiming {
	executorInFlightMilliseconds: number | null;
	executorPendingWaitMilliseconds: number | null;
	demandQueueWaitMilliseconds: number | null;
}

const sourceLessResetIdentity = 'source-less-reset';

export function isDescriptorFromSourceLessResetAnchor(props: {
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

export function applyReplacementDescriptorToOpenSessions(props: {
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

export function isOpenFileRefreshStillCurrent(props: {
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

export function makeWorktreeFileDemandReadContext(props: {
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

export function isDescriptorRefBlockedByReset(props: {
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

export function deleteResetReplacementDescriptorKeysForSource(props: {
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

export function resetDescriptorKeyForBridgeDescriptorRef(ref: BridgeDescriptorRef): string {
	return `${ref.expectedIdentity.sourceId ?? 'source-none'}:${demandFreshnessKeyForWorktreeDescriptorRef(ref)}`;
}

export async function settlePreloadLoads(props: {
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

export function recordExecutorLifecycleTiming(props: {
	readonly event: BridgeResourceExecutorLifecycleEvent;
	readonly lifecycleTimingsByDemandKey: Map<string, WorktreeFileDemandLifecycleTiming>;
}): void {
	const demandKey = demandLifecycleTimingKey(props.event.intent);
	const currentTiming = props.lifecycleTimingsByDemandKey.get(demandKey);
	switch (props.event.kind) {
		case 'queued':
			props.lifecycleTimingsByDemandKey.set(demandKey, {
				executorInFlightMilliseconds: currentTiming?.executorInFlightMilliseconds ?? null,
				executorPendingWaitMilliseconds: currentTiming?.executorPendingWaitMilliseconds ?? null,
				demandQueueWaitMilliseconds: currentTiming?.demandQueueWaitMilliseconds ?? null,
			});
			return;
		case 'started':
			props.lifecycleTimingsByDemandKey.set(demandKey, {
				executorInFlightMilliseconds: currentTiming?.executorInFlightMilliseconds ?? null,
				executorPendingWaitMilliseconds: props.event.pendingWaitMilliseconds,
				demandQueueWaitMilliseconds: currentTiming?.demandQueueWaitMilliseconds ?? null,
			});
			return;
		case 'completed':
			props.lifecycleTimingsByDemandKey.set(demandKey, {
				executorInFlightMilliseconds: props.event.inFlightMilliseconds,
				executorPendingWaitMilliseconds: currentTiming?.executorPendingWaitMilliseconds ?? null,
				demandQueueWaitMilliseconds: currentTiming?.demandQueueWaitMilliseconds ?? null,
			});
			return;
	}
	return assertNever(props.event);
}

function takeDemandLifecycleTiming(props: {
	readonly intent: BridgeDemandIntent;
	readonly lifecycleTimingsByDemandKey: Map<string, WorktreeFileDemandLifecycleTiming>;
}): WorktreeFileDemandLifecycleTiming {
	const demandKey = demandLifecycleTimingKey(props.intent);
	const timing = props.lifecycleTimingsByDemandKey.get(demandKey);
	props.lifecycleTimingsByDemandKey.delete(demandKey);
	return (
		timing ?? {
			executorInFlightMilliseconds: null,
			executorPendingWaitMilliseconds: null,
			demandQueueWaitMilliseconds: null,
		}
	);
}

function demandLifecycleTimingKey(intent: BridgeDemandIntent): string {
	return `${intent.dedupeKey}\u0000${intent.freshnessKey}`;
}

export async function loadPreloadIntent(props: {
	readonly bodyRegistry: ReturnType<
		typeof createBridgeBodyRegistry<WorktreeFileSurfaceRuntimeFetchedResource>
	>;
	readonly executor: BridgeResourceExecutor<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly lifecycleTimingsByDemandKey: Map<string, WorktreeFileDemandLifecycleTiming>;
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly now: () => number;
	readonly intent: BridgeDemandIntent;
	readonly preloadDispositionByBodyKey: Map<string, WorktreeFileSurfaceLoadDisposition>;
	readonly resourceLoadProbe: WorktreeFileSurfaceResourceLoadProbe | undefined;
}): Promise<WorktreeFileSurfaceDemandDispatchLoadResult> {
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
	const lifecycleTiming = takeDemandLifecycleTiming({
		intent: props.intent,
		lifecycleTimingsByDemandKey: props.lifecycleTimingsByDemandKey,
	});
	if (!result.ok) {
		recordFailedResourceLoadProbeSample({
			durationMilliseconds: Math.max(0, loadFinishedAtMilliseconds - loadStartedAtMilliseconds),
			estimatedBytes,
			lane: props.intent.lane,
			resourceLoadProbe: props.resourceLoadProbe,
			resultReason: result.reason,
		});
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
	const durationMilliseconds = Math.max(0, loadFinishedAtMilliseconds - loadStartedAtMilliseconds);
	const telemetryLifecycleTiming = lifecycleTimingForLoadTelemetry({
		disposition,
		durationMilliseconds,
		timing: lifecycleTiming,
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
	const loadTelemetry = {
		disposition,
		durationMilliseconds,
		estimatedBytes,
		executorInFlightBytesAfter: props.executor.inFlightBytes,
		executorInFlightBytesBefore,
		executorInFlightCountAfter: props.executor.inFlightCount,
		executorInFlightCountBefore,
		executorInFlightMilliseconds: telemetryLifecycleTiming.executorInFlightMilliseconds,
		executorPendingWaitMilliseconds: telemetryLifecycleTiming.executorPendingWaitMilliseconds,
		executorQueuedBytesAfter: props.executor.queuedBytes,
		executorQueuedBytesBefore,
		executorQueuedLoadCountAfter: props.executor.queuedLoadCount,
		executorQueuedLoadCountBefore,
		lane: props.intent.lane,
		resourceBodyRegistryCommitMilliseconds:
			result.content.timing?.bodyRegistryCommitMilliseconds ?? null,
		resourceFetchResponseWaitMilliseconds: result.content.timing?.responseWaitMilliseconds ?? null,
		resourceFirstChunkWaitMilliseconds: result.content.timing?.firstChunkWaitMilliseconds ?? null,
		resourceStreamReadMilliseconds: result.content.timing?.streamReadMilliseconds ?? null,
		demandQueueWaitMilliseconds: telemetryLifecycleTiming.demandQueueWaitMilliseconds,
	} satisfies WorktreeFileSurfaceLoadTelemetry;
	if (disposition !== 'cache-hit' && props.resourceLoadProbe?.isEnabled() === true) {
		props.resourceLoadProbe?.record(
			resourceLoadProbeSampleForTelemetry({
				byteLength: result.byteLength,
				loadTelemetry,
				result: 'success',
				resultReason: null,
			}),
		);
	}
	return {
		dedupeKey: props.intent.dedupeKey,
		ok: true,
		authoritative: result.authoritative,
		byteLength: result.byteLength,
		descriptorId: result.descriptor.descriptorId,
		freshnessKey: props.intent.freshnessKey,
		loadTelemetry,
	};
}

export async function loadStimulus(props: {
	readonly bodyRegistry: ReturnType<
		typeof createBridgeBodyRegistry<WorktreeFileSurfaceRuntimeFetchedResource>
	>;
	readonly executor: BridgeResourceExecutor<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly lifecycleTimingsByDemandKey: Map<string, WorktreeFileDemandLifecycleTiming>;
	readonly now: () => number;
	readonly preloadDispositionByBodyKey: Map<string, WorktreeFileSurfaceLoadDisposition>;
	readonly provisionalChunkConsumersByIntentKey: Map<
		string,
		(chunk: WorktreeFileSurfaceProvisionalTextChunk) => void
	>;
	readonly readContext: WorktreeFileDemandReadContext;
	readonly resourceLoadProbe: WorktreeFileSurfaceResourceLoadProbe | undefined;
	readonly onProvisionalTextChunk?:
		| ((chunk: WorktreeFileSurfaceProvisionalTextChunk) => void)
		| undefined;
	readonly stimulusDescriptor: WorktreeFileDescriptor;
	readonly stimulusKind: 'fileSelected' | 'explicitRefresh';
}): Promise<WorktreeFileSurfaceLoadResult> {
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
	const nextIntent = intents[0];
	if (nextIntent === undefined) {
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
	const lifecycleTiming = takeDemandLifecycleTiming({
		intent: nextIntent,
		lifecycleTimingsByDemandKey: props.lifecycleTimingsByDemandKey,
	});
	if (!result.ok) {
		recordFailedResourceLoadProbeSample({
			durationMilliseconds: Math.max(0, loadFinishedAtMilliseconds - loadStartedAtMilliseconds),
			estimatedBytes: expectedBytes,
			lane: nextIntent.lane,
			resourceLoadProbe: props.resourceLoadProbe,
			resultReason: result.reason,
		});
		return result;
	}
	if (!result.authoritative) {
		return { ok: false, reason: 'preview_only' };
	}
	const disposition = loadDispositionForStimulus({
		cachedPreloadDisposition,
		stimulusKind: props.stimulusKind,
		wasCachedBeforeLoad,
	});
	const durationMilliseconds = Math.max(0, loadFinishedAtMilliseconds - loadStartedAtMilliseconds);
	const telemetryLifecycleTiming = lifecycleTimingForLoadTelemetry({
		disposition,
		durationMilliseconds,
		timing: lifecycleTiming,
	});
	const loadTelemetry = {
		disposition,
		durationMilliseconds,
		estimatedBytes: expectedBytes,
		executorInFlightBytesAfter: props.executor.inFlightBytes,
		executorInFlightBytesBefore,
		executorInFlightCountAfter: props.executor.inFlightCount,
		executorInFlightCountBefore,
		executorInFlightMilliseconds: telemetryLifecycleTiming.executorInFlightMilliseconds,
		executorPendingWaitMilliseconds: telemetryLifecycleTiming.executorPendingWaitMilliseconds,
		executorQueuedBytesAfter: props.executor.queuedBytes,
		executorQueuedBytesBefore,
		executorQueuedLoadCountAfter: props.executor.queuedLoadCount,
		executorQueuedLoadCountBefore,
		lane: nextIntent.lane,
		resourceBodyRegistryCommitMilliseconds:
			result.content.timing?.bodyRegistryCommitMilliseconds ?? null,
		resourceFetchResponseWaitMilliseconds: result.content.timing?.responseWaitMilliseconds ?? null,
		resourceFirstChunkWaitMilliseconds: result.content.timing?.firstChunkWaitMilliseconds ?? null,
		resourceStreamReadMilliseconds: result.content.timing?.streamReadMilliseconds ?? null,
		demandQueueWaitMilliseconds: telemetryLifecycleTiming.demandQueueWaitMilliseconds,
	} satisfies WorktreeFileSurfaceLoadTelemetry;
	if (loadTelemetry.disposition !== 'cache-hit' && props.resourceLoadProbe?.isEnabled() === true) {
		props.resourceLoadProbe?.record(
			resourceLoadProbeSampleForTelemetry({
				byteLength: result.byteLength,
				loadTelemetry,
				result: 'success',
				resultReason: null,
			}),
		);
	}
	return {
		ok: true,
		authoritative: result.authoritative,
		byteLength: result.byteLength,
		content: result.content,
		descriptorId: result.descriptor.descriptorId,
		loadTelemetry,
	};
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

function lifecycleTimingForLoadTelemetry(props: {
	readonly disposition: WorktreeFileSurfaceLoadDisposition;
	readonly durationMilliseconds: number;
	readonly timing: WorktreeFileDemandLifecycleTiming;
}): WorktreeFileDemandLifecycleTiming {
	if (props.disposition === 'cache-hit') {
		return props.timing;
	}
	return {
		executorInFlightMilliseconds:
			props.timing.executorInFlightMilliseconds ?? props.durationMilliseconds,
		executorPendingWaitMilliseconds: props.timing.executorPendingWaitMilliseconds ?? 0,
		demandQueueWaitMilliseconds: props.timing.demandQueueWaitMilliseconds ?? 0,
	};
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

export function resourceWithMutableLoadTiming(
	fetchedResource: WorktreeFileSurfaceRuntimeFetchedResource,
): {
	readonly content: WorktreeFileSurfaceRuntimeFetchedResource;
	readonly timing: MutableWorktreeFileSurfaceResourceLoadTiming | null;
} {
	if (fetchedResource.timing === undefined) {
		return { content: fetchedResource, timing: null };
	}
	const timing: MutableWorktreeFileSurfaceResourceLoadTiming = {
		...fetchedResource.timing,
		bodyRegistryCommitMilliseconds: fetchedResource.timing.bodyRegistryCommitMilliseconds ?? null,
	};
	return {
		content: {
			...fetchedResource,
			timing,
		},
		timing,
	};
}

function resourceLoadProbeSampleForTelemetry(props: {
	readonly byteLength: number;
	readonly loadTelemetry: WorktreeFileSurfaceLoadTelemetry;
	readonly result: 'failed' | 'success';
	readonly resultReason: string | null;
}): WorktreeFileSurfaceResourceLoadProbeSample {
	return {
		byteLength: props.byteLength,
		estimatedBytes: props.loadTelemetry.estimatedBytes,
		firstChunkWaitMilliseconds: props.loadTelemetry.resourceFirstChunkWaitMilliseconds,
		lane: props.loadTelemetry.lane,
		responseWaitMilliseconds: props.loadTelemetry.resourceFetchResponseWaitMilliseconds,
		result: props.result,
		resultReason: props.resultReason,
		streamReadMilliseconds: props.loadTelemetry.resourceStreamReadMilliseconds,
		totalDurationMilliseconds: props.loadTelemetry.durationMilliseconds,
	};
}

function recordFailedResourceLoadProbeSample(props: {
	readonly durationMilliseconds: number;
	readonly estimatedBytes: number | null;
	readonly lane: BridgeDemandLane;
	readonly resourceLoadProbe: WorktreeFileSurfaceResourceLoadProbe | undefined;
	readonly resultReason: string;
}): void {
	if (props.resourceLoadProbe?.isEnabled() !== true) {
		return;
	}
	props.resourceLoadProbe.record({
		byteLength: 0,
		estimatedBytes: props.estimatedBytes,
		firstChunkWaitMilliseconds: null,
		lane: props.lane,
		responseWaitMilliseconds: null,
		result: 'failed',
		resultReason: props.resultReason,
		streamReadMilliseconds: null,
		totalDurationMilliseconds: props.durationMilliseconds,
	});
}

export function streamConsumerKeyForIntent(intent: BridgeDemandIntent): string {
	return `${intent.dedupeKey}\u0000${intent.freshnessKey}`;
}

export function cancelSourceDemand(props: {
	readonly executor: BridgeResourceExecutor<WorktreeFileSurfaceRuntimeFetchedResource>;
	readonly paneId: string;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}): number {
	const cancellationGroup = demandCancellationGroupForSource({
		paneId: props.paneId,
		source: props.source,
	});
	return props.executor.cancelGroup(cancellationGroup);
}

export function markSourceOpenSessionsStale(props: {
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

export function markOpenSessionsStaleForReplacementSource(props: {
	readonly source: WorktreeFileSurfaceSourceIdentity;
	readonly state: WorktreeFileSurfaceState;
}): WorktreeFileSurfaceState {
	return {
		...props.state,
		openFileSessionsById: Object.fromEntries(
			Object.entries(props.state.openFileSessionsById).map(([sessionId, session]) => {
				if (
					doesOpenSessionBelongToSource({
						session,
						source: props.source,
					})
				) {
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

function doesOpenSessionBelongToSource(props: {
	readonly session: WorktreeOpenFileSessionState;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}): boolean {
	const latestDescriptorSource = props.session.latestDescriptor?.sourceIdentity;
	if (latestDescriptorSource !== undefined) {
		return areWorktreeFileSourceIdentitiesEqual(latestDescriptorSource, props.source);
	}
	const expectedIdentity = props.session.descriptorRef.expectedIdentity;
	return (
		expectedIdentity.sourceId === props.source.sourceId &&
		expectedIdentity.generation === props.source.subscriptionGeneration &&
		expectedIdentity.cursor === props.source.sourceCursor
	);
}

export function markAllOpenSessionsStale(props: {
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

export function stateWithOpenSessionStatus(props: {
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

export function demandFreshnessKeyForWorktreeDescriptorRef(ref: BridgeDescriptorRef): string {
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

export function demandCancellationGroupForWorktreeDescriptorRef(ref: BridgeDescriptorRef): string {
	return `${ref.expectedProtocol}:${ref.expectedIdentity.paneId}:${ref.expectedIdentity.sourceId ?? 'source-none'}`;
}

export function demandCancellationGroupForSource(props: {
	readonly paneId: string;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}): string {
	return `worktree-file:${props.paneId}:${props.source.sourceId}`;
}

export function canFetchWorktreeFileBody(descriptor: WorktreeFileDescriptor): boolean {
	return !descriptor.isBinary && descriptor.virtualizedExtentKind !== 'unavailable';
}
