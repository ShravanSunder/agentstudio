import { z } from 'zod';

import {
	parseBridgeCoreResourceUrl,
	type BridgeCoreResourceUrl,
} from '../core/resources/bridge-resource-url.js';
import {
	worktreeFileProtocolFrameSchema,
	worktreeFileSurfaceSourceIdentitySchema,
	worktreeTreeVirtualizedSizeFactsSchema,
	type WorktreeFileSurfaceSourceIdentity,
	type WorktreeFileDescriptor,
	type WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type {
	WorktreeFileFrameSubscriber,
	WorktreeFileFrameSubscriptionDispose,
} from '../worktree-file-surface/worktree-file-app.js';
import type { WorktreeFileSurfaceRuntimeFetchResourceProps } from '../worktree-file-surface/worktree-file-surface-runtime.js';

export interface BridgeAppDevWorktreeBackend {
	readonly fetchWorktreeFileResource: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<string>;
	readonly loadWorktreeFileSurface: () => Promise<BridgeAppDevWorktreeSurface>;
	readonly subscribeWorktreeFileFrames: (
		subscriber: WorktreeFileFrameSubscriber,
	) => WorktreeFileFrameSubscriptionDispose;
}

export interface BridgeAppDevWorktreeSurface {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance: BridgeAppDevWorktreeSurfaceProvenance;
	readonly source: WorktreeFileSurfaceSourceIdentity;
}

export interface BridgeAppDevWorktreeSurfaceProvenance {
	readonly baseRef: string;
	readonly scenarioName: 'current-worktree';
	readonly worktreeRootToken: string;
}

const worktreeFileContentEndpointPrefix = '/__bridge-worktree/file-content/';
const worktreeSurfaceEndpoint = '/__bridge-worktree/surface';
const worktreeDevReloadEventType = 'bridge-worktree-dev-reload';
const worktreeDevForceSplitResetReloadEventType = 'bridge-worktree-dev-force-split-reset-reload';
const worktreeDevPausePollingEventType = 'bridge-worktree-dev-pause-polling';
const worktreeDevResumePollingEventType = 'bridge-worktree-dev-resume-polling';
const worktreeDevPollIntervalMilliseconds = 1_000;
const worktreeDevSplitResetReplacementDelayDatasetKey =
	'bridgeWorktreeDevSplitResetReplacementDelayMs';
const worktreeForwardedSearchParamNames: readonly string[] = ['scenario'];
const bridgeWorktreeAllowedResourceKindsByProtocol = {
	'worktree-file': new Set(['worktree.fileContent', 'worktree.treeWindow']),
};

const bridgeWorktreeSurfaceResponseSchema = z
	.object({
		frames: z.array(worktreeFileProtocolFrameSchema),
		provenance: z
			.object({
				baseRef: z.string().min(1),
				scenarioName: z.literal('current-worktree'),
				worktreeRootToken: z.string().min(1),
			})
			.strict(),
		source: worktreeFileSurfaceSourceIdentitySchema,
		treeSizeFacts: worktreeTreeVirtualizedSizeFactsSchema,
	})
	.strict();

export function installBridgeAppDevWorktreeBackend(): BridgeAppDevWorktreeBackend {
	const forwardedSearchParams = bridgeWorktreeForwardedSearchParams(window.location.search);
	let lastAcceptedSurfaceFrames: readonly WorktreeFileProtocolFrame[] | null = null;
	let lastAcceptedLineageFrames: readonly WorktreeFileProtocolFrame[] | null = null;
	document.documentElement.setAttribute('data-bridge-app-protocol', 'worktree-file');
	window.addEventListener(
		'beforeunload',
		(): void => {
			document.documentElement.removeAttribute('data-bridge-app-protocol');
		},
		{ once: true },
	);
	const loadSurface = async (): Promise<BridgeAppDevWorktreeSurface> => {
		const response = await fetch(
			bridgeWorktreeEndpoint(worktreeSurfaceEndpoint, forwardedSearchParams),
		);
		if (!response.ok) {
			throw new Error(`Bridge worktree surface request failed: ${response.status}`);
		}
		const surfaceResponse = bridgeWorktreeSurfaceResponseSchema.parse(await response.json());
		return {
			frames: surfaceResponse.frames,
			provenance: surfaceResponse.provenance,
			source: surfaceResponse.source,
		};
	};

	return {
		fetchWorktreeFileResource: async (
			resourceProps: WorktreeFileSurfaceRuntimeFetchResourceProps,
		): Promise<string> => {
			const parsedResourceUrl = parseBridgeCoreResourceUrl(resourceProps.resourceUrl, {
				allowedResourceKindsByProtocol: bridgeWorktreeAllowedResourceKindsByProtocol,
			});
			if (parsedResourceUrl === null || parsedResourceUrl.resourceKind !== 'worktree.fileContent') {
				throw new Error('Invalid Bridge worktree file resource URL');
			}
			const response = await fetch(
				bridgeWorktreeEndpoint(
					`${worktreeFileContentEndpointPrefix}${encodeURIComponent(parsedResourceUrl.opaqueId)}`,
					bridgeWorktreeFileContentSearchParams({
						forwardedSearchParams,
						parsedResourceUrl,
					}),
				),
				{ signal: resourceProps.signal },
			);
			if (!response.ok) {
				throw new Error(`Bridge worktree file content request failed: ${response.status}`);
			}
			return await response.text();
		},
		loadWorktreeFileSurface: async (): Promise<BridgeAppDevWorktreeSurface> => {
			const surface = await loadSurface();
			lastAcceptedSurfaceFrames = surface.frames;
			lastAcceptedLineageFrames = surface.frames;
			return surface;
		},
		subscribeWorktreeFileFrames: (
			subscriber: WorktreeFileFrameSubscriber,
		): WorktreeFileFrameSubscriptionDispose => {
			let isDisposed = false;
			let isPollingEnabled = true;
			let isReloading = false;
			let hasPendingForceSplitResetReload = false;
			const pendingFrameDeliveryTimeoutIds = new Set<number>();
			const publishPausedIfIdle = (): void => {
				if (!isPollingEnabled && !isReloading) {
					document.documentElement.dataset['bridgeWorktreeDevPollingState'] = 'paused';
				}
			};
			const reloadFrames = async (
				options: {
					readonly forceSplitReset?: boolean;
				} = {},
			): Promise<void> => {
				if (isDisposed || isReloading) {
					if (!isDisposed && options.forceSplitReset === true) {
						hasPendingForceSplitResetReload = true;
					}
					document.documentElement.dataset['bridgeWorktreeDevLastReloadStatus'] = 'is-reloading';
					return;
				}
				isReloading = true;
				try {
					const nextSurface = await loadSurface();
					const previousLineageFrames = lastAcceptedLineageFrames ?? lastAcceptedSurfaceFrames;
					const incrementalFrames =
						options.forceSplitReset === true
							? worktreeFileSourceLessResetFramesFromSurface({
									nextFrames: nextSurface.frames,
									previousFrames: previousLineageFrames,
								})
							: worktreeFileIncrementalFramesFromSurfaces({
									nextFrames: nextSurface.frames,
									previousFrames: lastAcceptedSurfaceFrames,
									previousLineageFrames,
								});
					if (options.forceSplitReset !== true && hasPendingForceSplitResetReload) {
						document.documentElement.dataset['bridgeWorktreeDevLastReloadStatus'] =
							'force-split-pending';
						return;
					}
					lastAcceptedSurfaceFrames = nextSurface.frames;
					if (incrementalFrames.length > 0) {
						lastAcceptedLineageFrames = incrementalFrames;
					}
					const frameGenerations = incrementalFrames.map((frame) => frame.generation).join(',');
					const frameKinds = incrementalFrames.map((frame) => frame.frameKind).join(',');
					const frameSequences = incrementalFrames.map((frame) => frame.sequence).join(',');
					const frameStreamIds = incrementalFrames.map((frame) => frame.streamId).join(',');
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameCount'] = String(
						incrementalFrames.length,
					);
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameGenerations'] =
						frameGenerations;
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameKinds'] = frameKinds;
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameSequences'] =
						frameSequences;
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameStreamIds'] =
						frameStreamIds;
					document.documentElement.dataset['bridgeWorktreeDevLastReloadSourceCursor'] =
						nextSurface.source.sourceCursor;
					document.documentElement.dataset['bridgeWorktreeDevLastReloadStatus'] = 'delivered';
					if (options.forceSplitReset === true) {
						document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameCount'] =
							String(incrementalFrames.length);
						document.documentElement.dataset[
							'bridgeWorktreeDevLastForceSplitReloadFrameGenerations'
						] = frameGenerations;
						document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameKinds'] =
							frameKinds;
						document.documentElement.dataset[
							'bridgeWorktreeDevLastForceSplitReloadFrameSequences'
						] = frameSequences;
						document.documentElement.dataset[
							'bridgeWorktreeDevLastForceSplitReloadFrameStreamIds'
						] = frameStreamIds;
						document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadSourceCursor'] =
							nextSurface.source.sourceCursor;
						document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadStatus'] =
							'delivered';
					}
					if (!isDisposed && incrementalFrames.length > 0) {
						if (options.forceSplitReset === true && incrementalFrames.length > 1) {
							const resetFrame = incrementalFrames[0];
							const replacementFrames = incrementalFrames.slice(1);
							if (resetFrame === undefined) {
								return;
							}
							subscriber([resetFrame]);
							const timeoutId = window.setTimeout((): void => {
								pendingFrameDeliveryTimeoutIds.delete(timeoutId);
								if (!isDisposed) {
									subscriber(replacementFrames);
								}
							}, worktreeDevSplitResetReplacementDelayMilliseconds());
							pendingFrameDeliveryTimeoutIds.add(timeoutId);
						} else {
							subscriber(incrementalFrames);
						}
					}
				} finally {
					isReloading = false;
					if (!isDisposed && hasPendingForceSplitResetReload) {
						hasPendingForceSplitResetReload = false;
						void reloadFrames({ forceSplitReset: true });
					} else {
						publishPausedIfIdle();
					}
				}
			};
			const handleReloadEvent = (): void => {
				document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] = 'normal';
				void reloadFrames();
			};
			const handleForceSplitResetReloadEvent = (): void => {
				document.documentElement.dataset['bridgeWorktreeDevLastReloadRequest'] =
					'force-split-reset';
				void reloadFrames({ forceSplitReset: true });
			};
			const handlePausePollingEvent = (): void => {
				isPollingEnabled = false;
				document.documentElement.dataset['bridgeWorktreeDevPollingState'] = isReloading
					? 'pausing'
					: 'paused';
			};
			const handleResumePollingEvent = (): void => {
				isPollingEnabled = true;
				document.documentElement.dataset['bridgeWorktreeDevPollingState'] = 'running';
			};
			window.addEventListener(worktreeDevReloadEventType, handleReloadEvent);
			window.addEventListener(
				worktreeDevForceSplitResetReloadEventType,
				handleForceSplitResetReloadEvent,
			);
			window.addEventListener(worktreeDevPausePollingEventType, handlePausePollingEvent);
			window.addEventListener(worktreeDevResumePollingEventType, handleResumePollingEvent);
			const intervalId = window.setInterval((): void => {
				if (isPollingEnabled) {
					void reloadFrames();
				}
			}, worktreeDevPollIntervalMilliseconds);
			return (): void => {
				isDisposed = true;
				window.clearInterval(intervalId);
				for (const timeoutId of pendingFrameDeliveryTimeoutIds) {
					window.clearTimeout(timeoutId);
				}
				window.removeEventListener(worktreeDevReloadEventType, handleReloadEvent);
				window.removeEventListener(
					worktreeDevForceSplitResetReloadEventType,
					handleForceSplitResetReloadEvent,
				);
				window.removeEventListener(worktreeDevPausePollingEventType, handlePausePollingEvent);
				window.removeEventListener(worktreeDevResumePollingEventType, handleResumePollingEvent);
			};
		},
	};
}

export function worktreeFileSourceLessResetFramesFromSurface(props: {
	readonly nextFrames: readonly WorktreeFileProtocolFrame[];
	readonly previousFrames: readonly WorktreeFileProtocolFrame[] | null;
}): readonly WorktreeFileProtocolFrame[] {
	const resetLineage = worktreeFileResetLineage({
		nextFrames: props.nextFrames,
		previousFrames: props.previousFrames,
	});
	return [
		{
			kind: 'reset',
			streamId: resetLineage.streamId,
			generation: resetLineage.generation,
			sequence: resetLineage.sequence,
			frameKind: 'worktree.reset',
			reason: 'sourceChanged',
		},
		...rebaseWorktreeFileFrameSequences({
			frames: props.nextFrames,
			generation: resetLineage.generation,
			startSequence: resetLineage.sequence + 1,
			streamId: resetLineage.streamId,
		}),
	];
}

export function worktreeFileIncrementalFramesFromSurfaces(props: {
	readonly nextFrames: readonly WorktreeFileProtocolFrame[];
	readonly previousFrames: readonly WorktreeFileProtocolFrame[] | null;
	readonly previousLineageFrames?: readonly WorktreeFileProtocolFrame[] | null;
}): readonly WorktreeFileProtocolFrame[] {
	if (props.previousFrames === null) {
		return props.nextFrames;
	}
	const previousDescriptorsByFileId = worktreeFileDescriptorsByFileId(props.previousFrames);
	const nextDescriptorsByFileId = worktreeFileDescriptorsByFileId(props.nextFrames);
	const continuationLineage = worktreeFileContinuationLineage({
		nextFrames: props.nextFrames,
		previousFrames: props.previousLineageFrames ?? props.previousFrames,
	});
	const hasRemovedDescriptor = [...previousDescriptorsByFileId.keys()].some(
		(fileId) => !nextDescriptorsByFileId.has(fileId),
	);
	if (hasRemovedDescriptor) {
		const resetLineage = worktreeFileResetLineage({
			nextFrames: props.nextFrames,
			previousFrames: props.previousLineageFrames ?? props.previousFrames,
		});
		return [
			{
				kind: 'reset',
				streamId: resetLineage.streamId,
				generation: resetLineage.generation,
				sequence: resetLineage.sequence,
				frameKind: 'worktree.reset',
				reason: 'sourceChanged',
			},
			...rebaseWorktreeFileFrameSequences({
				frames: props.nextFrames,
				generation: resetLineage.generation,
				startSequence: resetLineage.sequence + 1,
				streamId: resetLineage.streamId,
			}),
		];
	}
	const incrementalFrames: WorktreeFileProtocolFrame[] = [];
	let sequenceOffset = 0;
	for (const nextDescriptor of nextDescriptorsByFileId.values()) {
		const previousDescriptor = previousDescriptorsByFileId.get(nextDescriptor.fileId);
		if (previousDescriptor === undefined) {
			incrementalFrames.push(
				worktreeFileDescriptorFrame({
					descriptor: nextDescriptor,
					generation: continuationLineage.generation,
					sequence: continuationLineage.sequence + sequenceOffset,
					streamId: continuationLineage.streamId,
				}),
			);
			sequenceOffset += 1;
			continue;
		}
		if (previousDescriptor.contentHash !== nextDescriptor.contentHash) {
			incrementalFrames.push(
				worktreeFileInvalidatedFrame({
					generation: continuationLineage.generation,
					latestDescriptor: nextDescriptor,
					previousDescriptor,
					sequence: continuationLineage.sequence + sequenceOffset,
					streamId: continuationLineage.streamId,
				}),
			);
			sequenceOffset += 1;
		}
	}
	return incrementalFrames;
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

function bridgeWorktreeFileContentSearchParams(props: {
	readonly forwardedSearchParams: URLSearchParams;
	readonly parsedResourceUrl: BridgeCoreResourceUrl;
}): URLSearchParams {
	const contentSearchParams = new URLSearchParams(props.forwardedSearchParams);
	if (props.parsedResourceUrl.generation !== undefined) {
		contentSearchParams.set('generation', String(props.parsedResourceUrl.generation));
	}
	if (props.parsedResourceUrl.cursor !== undefined) {
		contentSearchParams.set('cursor', props.parsedResourceUrl.cursor);
	}
	return contentSearchParams;
}

function worktreeFileDescriptorsByFileId(
	frames: readonly WorktreeFileProtocolFrame[],
): ReadonlyMap<string, WorktreeFileDescriptor> {
	const descriptorsByFileId = new Map<string, WorktreeFileDescriptor>();
	for (const frame of frames) {
		if (frame.frameKind === 'worktree.fileDescriptor') {
			descriptorsByFileId.set(frame.descriptor.fileId, frame.descriptor);
		}
	}
	return descriptorsByFileId;
}

function worktreeFileDescriptorFrame(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly generation: number;
	readonly sequence: number;
	readonly streamId: string;
}): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId: props.streamId,
		generation: props.generation,
		sequence: props.sequence,
		frameKind: 'worktree.fileDescriptor',
		descriptor: props.descriptor,
	};
}

function worktreeFileInvalidatedFrame(props: {
	readonly generation: number;
	readonly latestDescriptor: WorktreeFileDescriptor;
	readonly previousDescriptor: WorktreeFileDescriptor;
	readonly sequence: number;
	readonly streamId: string;
}): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId: props.streamId,
		generation: props.generation,
		sequence: props.sequence,
		frameKind: 'worktree.fileInvalidated',
		invalidation: {
			path: props.latestDescriptor.path,
			fileId: props.latestDescriptor.fileId,
			reason: 'contentChanged',
			contentHandleIds: [props.previousDescriptor.contentHandle],
			latestDescriptor: props.latestDescriptor,
		},
	};
}

function worktreeFileContinuationLineage(props: {
	readonly nextFrames: readonly WorktreeFileProtocolFrame[];
	readonly previousFrames: readonly WorktreeFileProtocolFrame[] | null;
}): {
	readonly generation: number;
	readonly sequence: number;
	readonly streamId: string;
} {
	const lineageFrames = props.previousFrames ?? props.nextFrames;
	const streamId = lineageFrames[0]?.streamId ?? props.nextFrames[0]?.streamId ?? 'worktree-file';
	return {
		generation: maxWorktreeFrameGeneration(lineageFrames),
		sequence: maxWorktreeFrameSequence(lineageFrames) + 1,
		streamId,
	};
}

function maxWorktreeFrameSequence(frames: readonly WorktreeFileProtocolFrame[]): number {
	return frames.reduce((maxSequence, frame) => Math.max(maxSequence, frame.sequence), 0);
}

function maxWorktreeFrameGeneration(frames: readonly WorktreeFileProtocolFrame[]): number {
	return frames.reduce((maxGeneration, frame) => Math.max(maxGeneration, frame.generation), 0);
}

function worktreeFileResetLineage(props: {
	readonly nextFrames: readonly WorktreeFileProtocolFrame[];
	readonly previousFrames: readonly WorktreeFileProtocolFrame[] | null;
}): {
	readonly generation: number;
	readonly sequence: number;
	readonly streamId: string;
} {
	const lineageFrames = props.previousFrames ?? props.nextFrames;
	const streamId = lineageFrames[0]?.streamId ?? props.nextFrames[0]?.streamId ?? 'worktree-file';
	return {
		generation: maxWorktreeFrameGeneration(lineageFrames) + 1,
		sequence: maxWorktreeFrameSequence(lineageFrames) + 1,
		streamId,
	};
}

function rebaseWorktreeFileFrameSequences(props: {
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly generation: number;
	readonly startSequence: number;
	readonly streamId: string;
}): readonly WorktreeFileProtocolFrame[] {
	return props.frames.map(
		(frame, index): WorktreeFileProtocolFrame => ({
			...frame,
			generation: props.generation,
			sequence: props.startSequence + index,
			streamId: props.streamId,
		}),
	);
}

function worktreeDevSplitResetReplacementDelayMilliseconds(): number {
	const delayText =
		document.documentElement.dataset[worktreeDevSplitResetReplacementDelayDatasetKey];
	if (delayText === undefined) {
		return 0;
	}
	const parsedDelay = Number.parseInt(delayText, 10);
	if (!Number.isSafeInteger(parsedDelay) || parsedDelay < 0) {
		return 0;
	}
	return parsedDelay;
}

function bridgeWorktreeEndpoint(path: string, searchParams: URLSearchParams): string {
	const query = searchParams.toString();
	return query.length === 0 ? path : `${path}?${query}`;
}
