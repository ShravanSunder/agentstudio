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
const worktreeDevPollIntervalMilliseconds = 1_000;
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
			return surface;
		},
		subscribeWorktreeFileFrames: (
			subscriber: WorktreeFileFrameSubscriber,
		): WorktreeFileFrameSubscriptionDispose => {
			let isDisposed = false;
			let isReloading = false;
			let hasPendingForceSplitResetReload = false;
			const pendingFrameDeliveryTimeoutIds = new Set<number>();
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
					const incrementalFrames =
						options.forceSplitReset === true
							? worktreeFileSourceLessResetFramesFromSurface(nextSurface.frames)
							: worktreeFileIncrementalFramesFromSurfaces({
									nextFrames: nextSurface.frames,
									previousFrames: lastAcceptedSurfaceFrames,
								});
					if (options.forceSplitReset !== true && hasPendingForceSplitResetReload) {
						document.documentElement.dataset['bridgeWorktreeDevLastReloadStatus'] =
							'force-split-pending';
						return;
					}
					lastAcceptedSurfaceFrames = nextSurface.frames;
					const frameKinds = incrementalFrames.map((frame) => frame.frameKind).join(',');
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameCount'] = String(
						incrementalFrames.length,
					);
					document.documentElement.dataset['bridgeWorktreeDevLastReloadFrameKinds'] = frameKinds;
					document.documentElement.dataset['bridgeWorktreeDevLastReloadSourceCursor'] =
						nextSurface.source.sourceCursor;
					document.documentElement.dataset['bridgeWorktreeDevLastReloadStatus'] = 'delivered';
					if (options.forceSplitReset === true) {
						document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameCount'] =
							String(incrementalFrames.length);
						document.documentElement.dataset['bridgeWorktreeDevLastForceSplitReloadFrameKinds'] =
							frameKinds;
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
							}, 0);
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
			window.addEventListener(worktreeDevReloadEventType, handleReloadEvent);
			window.addEventListener(
				worktreeDevForceSplitResetReloadEventType,
				handleForceSplitResetReloadEvent,
			);
			const intervalId = window.setInterval((): void => {
				void reloadFrames();
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
			};
		},
	};
}

export function worktreeFileSourceLessResetFramesFromSurface(
	nextFrames: readonly WorktreeFileProtocolFrame[],
): readonly WorktreeFileProtocolFrame[] {
	return [
		{
			kind: 'reset',
			streamId: 'worktree-file',
			generation: 0,
			sequence: maxWorktreeFrameSequence(nextFrames) + 1,
			frameKind: 'worktree.reset',
			reason: 'sourceChanged',
		},
		...nextFrames,
	];
}

export function worktreeFileIncrementalFramesFromSurfaces(props: {
	readonly nextFrames: readonly WorktreeFileProtocolFrame[];
	readonly previousFrames: readonly WorktreeFileProtocolFrame[] | null;
}): readonly WorktreeFileProtocolFrame[] {
	if (props.previousFrames === null) {
		return props.nextFrames;
	}
	const previousDescriptorsByFileId = worktreeFileDescriptorsByFileId(props.previousFrames);
	const nextDescriptorsByFileId = worktreeFileDescriptorsByFileId(props.nextFrames);
	const nextSequence = maxWorktreeFrameSequence(props.nextFrames) + 1;
	const hasRemovedDescriptor = [...previousDescriptorsByFileId.keys()].some(
		(fileId) => !nextDescriptorsByFileId.has(fileId),
	);
	if (hasRemovedDescriptor) {
		return [
			{
				kind: 'reset',
				streamId: 'worktree-file',
				generation: 0,
				sequence: nextSequence,
				frameKind: 'worktree.reset',
				reason: 'sourceChanged',
			},
			...props.nextFrames,
		];
	}
	const incrementalFrames: WorktreeFileProtocolFrame[] = [];
	let sequenceOffset = 0;
	for (const nextDescriptor of nextDescriptorsByFileId.values()) {
		const previousDescriptor = previousDescriptorsByFileId.get(nextDescriptor.fileId);
		if (previousDescriptor === undefined) {
			incrementalFrames.push(
				worktreeFileDescriptorFrame(nextDescriptor, nextSequence + sequenceOffset),
			);
			sequenceOffset += 1;
			continue;
		}
		if (previousDescriptor.contentHash !== nextDescriptor.contentHash) {
			incrementalFrames.push(
				worktreeFileInvalidatedFrame({
					latestDescriptor: nextDescriptor,
					previousDescriptor,
					sequence: nextSequence + sequenceOffset,
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

function worktreeFileDescriptorFrame(
	descriptor: WorktreeFileDescriptor,
	sequence: number,
): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId: descriptor.contentDescriptor.ref.expectedIdentity.streamId ?? 'worktree-file',
		generation: descriptor.sourceIdentity.subscriptionGeneration,
		sequence,
		frameKind: 'worktree.fileDescriptor',
		descriptor,
	};
}

function worktreeFileInvalidatedFrame(props: {
	readonly latestDescriptor: WorktreeFileDescriptor;
	readonly previousDescriptor: WorktreeFileDescriptor;
	readonly sequence: number;
}): WorktreeFileProtocolFrame {
	return {
		kind: 'delta',
		streamId:
			props.latestDescriptor.contentDescriptor.ref.expectedIdentity.streamId ?? 'worktree-file',
		generation: props.latestDescriptor.sourceIdentity.subscriptionGeneration,
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

function maxWorktreeFrameSequence(frames: readonly WorktreeFileProtocolFrame[]): number {
	return frames.reduce((maxSequence, frame) => Math.max(maxSequence, frame.sequence), 0);
}

function bridgeWorktreeEndpoint(path: string, searchParams: URLSearchParams): string {
	const query = searchParams.toString();
	return query.length === 0 ? path : `${path}?${query}`;
}
