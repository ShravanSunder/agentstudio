import type { MutableRefObject } from 'react';
import { z } from 'zod';

import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import { loadBridgeTextResourceWithTiming } from '../core/resources/bridge-resource-stream.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
	WorktreeTreeVirtualizedSizeFacts,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileSurfaceProvenance } from '../worktree-file-surface/worktree-file-app.js';
import type {
	WorktreeFileSurfaceDemandDispatchResult,
	WorktreeFileSurfaceLoadResult,
	WorktreeFileSurfaceRuntime,
	WorktreeFileSurfaceRuntimeFetchedResource,
	WorktreeFileSurfaceRuntimeFetchResourceProps,
} from '../worktree-file-surface/worktree-file-surface-runtime.js';
import type {
	BridgeFileViewerDescriptorProjection,
	BridgeFileViewerFilterMode,
	BridgeFileViewerSearchMode,
	BridgeFileViewerVisibleFileDemandChange,
} from './bridge-file-viewer-contracts.js';
import { applyWorktreeTreeOperationsToFileViewerState } from './bridge-file-viewer-tree-delta.js';

export interface BridgeFileViewerRenderState {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly provenance: WorktreeFileSurfaceProvenance | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
	readonly treeSizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
}

export type BridgeFileViewerInitialSurfaceLoadState =
	| { readonly status: 'idle' | 'loading' | 'ready' }
	| { readonly reason: string; readonly status: 'failed' };

export type BridgeFileViewerOpenState =
	| { readonly status: 'idle' }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed' | 'loading' | 'ready' | 'refreshing' | 'stale' | 'unavailable';
	  };

export type BridgeFileViewerActiveOpenState = Exclude<
	BridgeFileViewerOpenState,
	{ readonly status: 'idle' }
>;

export interface BridgeFileViewerRenderedOpenFileContent {
	readonly body: string;
	readonly bodyVersion: number;
	readonly descriptor: WorktreeFileDescriptor;
	readonly path: string;
}

export interface CommitOpenFileBodyProps {
	readonly body: string;
	readonly descriptor: WorktreeFileDescriptor;
	readonly path: string;
}

export interface BridgeFileViewerRefreshDebugState {
	readonly commitState: 'committed' | 'ignored' | 'skipped' | 'started';
	readonly currentRequestId: number;
	readonly descriptorId: string;
	readonly requestId: number;
	readonly result:
		| 'non_stale_state'
		| 'started'
		| 'ok'
		| Extract<WorktreeFileSurfaceLoadResult, { readonly ok: false }>['reason'];
}

export type BridgeFileViewerDemandDispatchDebugState =
	| { readonly status: 'idle' }
	| {
			readonly origin:
				| {
						readonly expectedVisibleFileCount: number;
						readonly kind: 'visibleViewport';
				  }
				| {
						readonly descriptorPath: string;
						readonly kind: 'recentlyUpdatedFile';
						readonly openFilePathAfter: string | null;
						readonly openFilePathBefore: string | null;
				  };
			readonly status: 'settled';
			readonly result: WorktreeFileSurfaceDemandDispatchResult;
	  }
	| {
			readonly status: 'failed';
			readonly reason: string;
	  };

export interface BridgeFileViewerPendingRecentlyUpdatedDescriptorDemand {
	readonly openFilePathBefore: string | null;
	readonly proximity: 'nearby' | 'remote';
	readonly request: WorktreeFileDescriptorRequest;
	readonly requestId: number;
}

export type BridgeFileViewerSearchPattern =
	| { readonly ok: true; readonly pattern: RegExp }
	| { readonly ok: false; readonly message: string };

export const bridgeFileViewerRecentlyUpdatedEventName = 'bridge-worktree-file-recently-updated';
export const bridgeFileViewerRecentlyUpdatedEventDetailSchema = z
	.object({
		path: z.string().min(1),
		proximity: z.enum(['nearby', 'remote']),
		sourceIdentity: z.string().min(1),
	})
	.strict();

export const defaultPaneId = 'bridge-worktree-dev-pane';
export const defaultFileLineHeightPixels = 20;
export const emptyRenderState: BridgeFileViewerRenderState = {
	descriptors: [],
	provenance: null,
	sourceIdentity: null,
	treeRows: [],
	treeSizeFacts: null,
};

export function visibleViewportDemandDispatchSatisfied(
	state: BridgeFileViewerDemandDispatchDebugState,
): boolean {
	if (state.status !== 'settled' || state.origin.kind !== 'visibleViewport') {
		return false;
	}
	const firstLoadResult = firstSuccessfulDemandLoadResult(state.result);
	return (
		state.origin.expectedVisibleFileCount > 0 &&
		state.result.stimulusCount === 1 &&
		state.result.intentCount === state.origin.expectedVisibleFileCount &&
		state.result.loadedCount === state.origin.expectedVisibleFileCount &&
		state.result.failedCount === 0 &&
		state.result.schedulerQueuedIntentCountAfter === 0 &&
		state.result.executorQueuedLoadCountAfter === 0 &&
		firstLoadResult?.loadTelemetry.lane === 'visible' &&
		firstLoadResult.loadTelemetry.disposition === 'visible-preloaded'
	);
}

export function visibleFileDemandSignature(
	change: BridgeFileViewerVisibleFileDemandChange,
): string {
	return change.descriptorRefs
		.map((ref): string => {
			const identity = ref.expectedIdentity;
			return [
				ref.descriptorId,
				ref.expectedProtocol,
				ref.expectedResourceKind,
				identity.paneId,
				identity.sourceId ?? 'source-none',
				identity.generation ?? 'generation-none',
				identity.revision ?? 'revision-none',
				identity.streamId ?? 'stream-none',
				identity.cursor ?? 'cursor-none',
			].join(':');
		})
		.join('\n');
}

export function visibleFileDemandChangeWithoutDescriptorId(
	change: BridgeFileViewerVisibleFileDemandChange,
	descriptorId: string,
): BridgeFileViewerVisibleFileDemandChange | null {
	const descriptorRefs = change.descriptorRefs.filter(
		(descriptorRef): boolean => descriptorRef.descriptorId !== descriptorId,
	);
	return descriptorRefs.length === 0
		? null
		: {
				...change,
				descriptorRefs,
				visibleFileCount: descriptorRefs.length,
			};
}

export function firstSuccessfulDemandLoadResult(
	result: WorktreeFileSurfaceDemandDispatchResult,
): Extract<
	WorktreeFileSurfaceDemandDispatchResult['loadResults'][number],
	{ readonly ok: true }
> | null {
	for (const loadResult of result.loadResults) {
		if (loadResult.ok) {
			return loadResult;
		}
	}
	return null;
}

export function worktreeFileDemandFailedCountByLane(
	result: WorktreeFileSurfaceDemandDispatchResult,
): Record<string, number> {
	const countByLane: Record<string, number> = {};
	for (const loadResult of result.loadResults) {
		if (loadResult.ok) {
			continue;
		}
		countByLane[loadResult.lane] = (countByLane[loadResult.lane] ?? 0) + 1;
	}
	return countByLane;
}

export function worktreeFileDemandFailedCountByReason(
	result: WorktreeFileSurfaceDemandDispatchResult,
): Record<string, number> {
	const countByReason: Record<string, number> = {};
	for (const loadResult of result.loadResults) {
		if (loadResult.ok) {
			continue;
		}
		countByReason[loadResult.reason] = (countByReason[loadResult.reason] ?? 0) + 1;
	}
	return countByReason;
}

export function worktreeTreeWindowRowCount(frames: readonly WorktreeFileProtocolFrame[]): number {
	let rowCount = 0;
	for (const frame of frames) {
		if (frame.frameKind === 'worktree.treeWindow') {
			rowCount += frame.rows?.length ?? 0;
		}
	}
	return rowCount;
}

export function bridgeFileViewerHeaderTitle(props: {
	readonly selectedPath: string | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
}): string {
	const sourceTitle = props.sourceIdentity?.sourceId ?? 'Source pending';
	return props.selectedPath === null ? sourceTitle : `${sourceTitle} / ${props.selectedPath}`;
}

export function fileViewerNavigationTargetPath(
	navigationCommand: BridgeViewerNavigationCommand | undefined,
): string | null {
	if (navigationCommand?.context !== 'files' || navigationCommand.target?.targetKind !== 'file') {
		return null;
	}
	return navigationCommand.target.fileRef.path;
}

export function projectBridgeFileViewerDescriptors(props: {
	readonly descriptors: readonly WorktreeFileDescriptor[];
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): BridgeFileViewerDescriptorProjection {
	const trimmedSearchText = props.searchText.trim();
	const searchPattern =
		trimmedSearchText.length === 0
			? null
			: makeBridgeFileViewerSearchPattern({
					searchMode: props.searchMode,
					searchText: trimmedSearchText,
				});
	if (searchPattern?.ok === false) {
		return { descriptors: [], paths: [], searchError: searchPattern.message, treeRows: [] };
	}
	const descriptorByPath = new Map(
		props.descriptors.map((descriptor) => [descriptor.path, descriptor]),
	);
	const treeRows = props.treeRows.filter((treeRow): boolean => {
		const descriptor = descriptorByPath.get(treeRow.path) ?? null;
		if (
			!treeRowMatchesFilterMode({
				descriptor,
				filterMode: props.filterMode,
				treeRow,
			})
		) {
			return false;
		}
		return searchPattern === null ? true : searchPattern.pattern.test(treeRow.path);
	});
	const includedPathSet = new Set(treeRows.map((treeRow) => treeRow.path));
	const descriptors = props.descriptors.filter((descriptor): boolean =>
		includedPathSet.has(descriptor.path),
	);
	return {
		descriptors,
		paths: treeRows.map(pierreFileTreePathForRow),
		searchError: null,
		treeRows,
	};
}

export function pierreFileTreePathForRow(treeRow: WorktreeTreeRowMetadata): string {
	if (!treeRow.isDirectory) {
		return treeRow.path;
	}
	return treeRow.path.endsWith('/') ? treeRow.path : `${treeRow.path}/`;
}

export function descriptorRequestForFirstFileTreeRow(props: {
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): WorktreeFileDescriptorRequest | null {
	if (props.sourceIdentity === null) {
		return null;
	}
	const firstFileRow = props.treeRows.find(
		(treeRow): boolean => !treeRow.isDirectory && treeRow.fileId !== undefined,
	);
	if (firstFileRow === undefined || firstFileRow.fileId === undefined) {
		return null;
	}
	return {
		sourceIdentity: props.sourceIdentity,
		rowId: firstFileRow.rowId,
		path: firstFileRow.path,
		fileId: firstFileRow.fileId,
		lane: 'foreground',
	};
}

export function descriptorRequestForTreePath(props: {
	readonly lane: WorktreeFileDescriptorRequest['lane'];
	readonly path: string;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): WorktreeFileDescriptorRequest | null {
	if (props.sourceIdentity === null) {
		return null;
	}
	const treeRow = props.treeRows.find(
		(candidate): boolean => candidate.path === props.path && !candidate.isDirectory,
	);
	if (treeRow === undefined || treeRow.fileId === undefined) {
		return null;
	}
	return {
		sourceIdentity: props.sourceIdentity,
		rowId: treeRow.rowId,
		path: treeRow.path,
		fileId: treeRow.fileId,
		lane: props.lane,
	};
}

export function worktreeFileDescriptorRequestsMatch(
	leftRequest: WorktreeFileDescriptorRequest | null,
	rightRequest: WorktreeFileDescriptorRequest,
): boolean {
	return (
		leftRequest !== null &&
		leftRequest.sourceIdentity.sourceId === rightRequest.sourceIdentity.sourceId &&
		leftRequest.sourceIdentity.sourceCursor === rightRequest.sourceIdentity.sourceCursor &&
		leftRequest.rowId === rightRequest.rowId &&
		leftRequest.path === rightRequest.path &&
		leftRequest.fileId === rightRequest.fileId &&
		leftRequest.lane === rightRequest.lane
	);
}

export function treeRowMatchesFilterMode(props: {
	readonly descriptor: WorktreeFileDescriptor | null;
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly treeRow: WorktreeTreeRowMetadata;
}): boolean {
	switch (props.filterMode) {
		case 'all':
			return true;
		case 'fetchable':
			if (props.descriptor === null) {
				return !props.treeRow.isDirectory && props.treeRow.fileId !== undefined;
			}
			return canFetchWorktreeFileDescriptorContent(props.descriptor);
		case 'unavailable':
			if (props.descriptor === null) {
				return false;
			}
			return props.descriptor.isBinary || props.descriptor.virtualizedExtentKind === 'unavailable';
	}
	return false;
}

export function makeBridgeFileViewerSearchPattern(props: {
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
}): BridgeFileViewerSearchPattern {
	if (props.searchMode === 'text') {
		return { ok: true, pattern: new RegExp(escapeRegExp(props.searchText), 'iu') };
	}
	try {
		return { ok: true, pattern: new RegExp(props.searchText, 'iu') };
	} catch (error) {
		return { ok: false, message: error instanceof Error ? error.message : 'Invalid regex' };
	}
}

export function escapeRegExp(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
}

export type WorktreeFileRuntimeFrameApplier = Pick<WorktreeFileSurfaceRuntime, 'applyFrame'>;

export function applyFramesToRuntime(props: {
	readonly currentRenderState: BridgeFileViewerRenderState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly provenance?: WorktreeFileSurfaceProvenance | null;
	readonly runtime: WorktreeFileRuntimeFrameApplier | null;
	readonly sourceIdentity?: WorktreeFileSurfaceSourceIdentity | null;
}): BridgeFileViewerRenderState {
	const descriptorsByFileId = new Map<string, WorktreeFileDescriptor>(
		props.currentRenderState.descriptors.map(
			(descriptor): readonly [string, WorktreeFileDescriptor] => [descriptor.fileId, descriptor],
		),
	);
	const treeRowsByPath = new Map<string, WorktreeTreeRowMetadata>(
		props.currentRenderState.treeRows.map((treeRow): readonly [string, WorktreeTreeRowMetadata] => [
			treeRow.path,
			treeRow,
		]),
	);
	const provenance = props.provenance ?? props.currentRenderState.provenance;
	let sourceIdentity = props.sourceIdentity ?? props.currentRenderState.sourceIdentity;
	let treeSizeFacts = props.currentRenderState.treeSizeFacts;

	for (const frame of props.frames) {
		const applyFrameResult = props.runtime?.applyFrame(frame);
		if (applyFrameResult?.ok === false) {
			continue;
		}
		if (frame.frameKind === 'worktree.snapshot' || frame.frameKind === 'worktree.treeWindow') {
			treeSizeFacts = frame.treeSizeFacts ?? treeSizeFacts;
		}
		if (frame.frameKind === 'worktree.snapshot') {
			sourceIdentity = frame.source;
			descriptorsByFileId.clear();
			if (frame.treeRows !== undefined) {
				treeRowsByPath.clear();
				for (const treeRow of frame.treeRows) {
					treeRowsByPath.set(treeRow.path, treeRow);
				}
			}
		}
		if (frame.frameKind === 'worktree.treeWindow') {
			sourceIdentity = frame.projectionIdentity.source;
			if (frame.rows !== undefined) {
				for (const treeRow of frame.rows) {
					treeRowsByPath.set(treeRow.path, treeRow);
				}
			}
		}
		if (frame.frameKind === 'worktree.treeDelta') {
			treeSizeFacts = applyWorktreeTreeOperationsToFileViewerState({
				descriptorsByFileId,
				fallbackRowHeightPixels: defaultFileLineHeightPixels,
				operations: frame.operations,
				pruneEmptyDirectories: pruneEmptyWorktreeFileTreeDirectories,
				treeRowsByPath,
				treeSizeFacts,
			});
		}
		if (frame.frameKind === 'worktree.fileDescriptor') {
			sourceIdentity = frame.descriptor.sourceIdentity;
			descriptorsByFileId.set(frame.descriptor.fileId, frame.descriptor);
		}
		if (frame.frameKind === 'worktree.fileInvalidated') {
			const latestDescriptor = frame.invalidation.latestDescriptor;
			if (latestDescriptor !== undefined) {
				sourceIdentity = latestDescriptor.sourceIdentity;
				descriptorsByFileId.set(latestDescriptor.fileId, latestDescriptor);
			} else {
				const invalidatedFileId = frame.invalidation.fileId;
				if (invalidatedFileId !== undefined) {
					descriptorsByFileId.delete(invalidatedFileId);
				}
				for (const [fileId, descriptor] of descriptorsByFileId) {
					if (descriptor.path === frame.invalidation.path) {
						descriptorsByFileId.delete(fileId);
					}
				}
				treeRowsByPath.delete(frame.invalidation.path);
				pruneEmptyWorktreeFileTreeDirectories(treeRowsByPath);
			}
		}
		if (frame.frameKind === 'worktree.reset') {
			descriptorsByFileId.clear();
			treeRowsByPath.clear();
			sourceIdentity = frame.source ?? null;
			treeSizeFacts = null;
		}
	}

	return {
		descriptors: [...descriptorsByFileId.values()],
		provenance,
		sourceIdentity,
		treeRows: [...treeRowsByPath.values()],
		treeSizeFacts,
	};
}

export function pruneEmptyWorktreeFileTreeDirectories(
	treeRowsByPath: Map<string, WorktreeTreeRowMetadata>,
): void {
	const pathsToDelete: string[] = [];
	for (const [path, treeRow] of treeRowsByPath) {
		if (!treeRow.isDirectory) {
			continue;
		}
		const descendantPathPrefix = `${path.replace(/\/+$/, '')}/`;
		let hasFileDescendant = false;
		for (const candidate of treeRowsByPath.values()) {
			if (!candidate.isDirectory && candidate.path.startsWith(descendantPathPrefix)) {
				hasFileDescendant = true;
				break;
			}
		}
		if (!hasFileDescendant) {
			pathsToDelete.push(path);
		}
	}
	for (const path of pathsToDelete) {
		treeRowsByPath.delete(path);
	}
}

export function reconcileOpenFileStateWithFrames(props: {
	readonly currentOpenFileState: BridgeFileViewerOpenState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
	readonly openFileBodyRef: MutableRefObject<string | null>;
	readonly openFileRequestIdRef: MutableRefObject<number>;
}): BridgeFileViewerOpenState {
	if (props.currentOpenFileState.status === 'idle') {
		return props.currentOpenFileState;
	}
	const currentOpenFileState = props.currentOpenFileState;
	const matchedReplacementDescriptor = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.fileDescriptor' &&
			(frame.descriptor.fileId === currentOpenFileState.descriptor.fileId ||
				frame.descriptor.path === currentOpenFileState.path),
	);
	const resetFrame = props.frames.find((frame) => frame.frameKind === 'worktree.reset');
	if (resetFrame !== undefined) {
		if (
			matchedReplacementDescriptor?.frameKind === 'worktree.fileDescriptor' &&
			areWorktreeFileDescriptorsSameContentVersion(
				matchedReplacementDescriptor.descriptor,
				currentOpenFileState.descriptor,
			)
		) {
			return {
				...currentOpenFileState,
				path: matchedReplacementDescriptor.descriptor.path,
				descriptor: matchedReplacementDescriptor.descriptor,
			};
		}
		if (
			matchedReplacementDescriptor === undefined &&
			resetSnapshotFramesKeepOpenFilePath({
				currentOpenFileState,
				frames: props.frames,
			})
		) {
			props.openFileRequestIdRef.current += 1;
			return {
				status: 'stale',
				path: currentOpenFileState.path,
				descriptor: currentOpenFileState.descriptor,
			};
		}
		props.openFileRequestIdRef.current += 1;
		return {
			status: 'stale',
			path: currentOpenFileState.path,
			descriptor: currentOpenFileState.descriptor,
		};
	}
	const replacementSourceSnapshot = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.snapshot' &&
			!areWorktreeFileSourceIdentitiesEqual(
				frame.source,
				currentOpenFileState.descriptor.sourceIdentity,
			),
	);
	if (replacementSourceSnapshot !== undefined) {
		if (
			matchedReplacementDescriptor?.frameKind === 'worktree.fileDescriptor' &&
			areWorktreeFileDescriptorsSameContentVersion(
				matchedReplacementDescriptor.descriptor,
				currentOpenFileState.descriptor,
			)
		) {
			return {
				...currentOpenFileState,
				path: matchedReplacementDescriptor.descriptor.path,
				descriptor: matchedReplacementDescriptor.descriptor,
			};
		}
		props.openFileRequestIdRef.current += 1;
		return {
			status: 'stale',
			path: currentOpenFileState.path,
			descriptor: currentOpenFileState.descriptor,
		};
	}
	const matchedInvalidation = props.frames.find(
		(frame) =>
			frame.frameKind === 'worktree.fileInvalidated' &&
			(frame.invalidation.fileId === currentOpenFileState.descriptor.fileId ||
				frame.invalidation.path === currentOpenFileState.path),
	);
	if (
		matchedInvalidation?.frameKind !== 'worktree.fileInvalidated' &&
		matchedReplacementDescriptor?.frameKind !== 'worktree.fileDescriptor'
	) {
		return currentOpenFileState;
	}
	if (
		isFrameForCurrentDescriptorVersion({
			currentDescriptor: currentOpenFileState.descriptor,
			matchedInvalidation,
			matchedReplacementDescriptor,
		})
	) {
		return currentOpenFileState;
	}
	props.openFileRequestIdRef.current += 1;
	return {
		status: 'stale',
		path: currentOpenFileState.path,
		descriptor: currentOpenFileState.descriptor,
	};
}

export function isFrameForCurrentDescriptorVersion(props: {
	readonly currentDescriptor: WorktreeFileDescriptor;
	readonly matchedInvalidation: WorktreeFileProtocolFrame | undefined;
	readonly matchedReplacementDescriptor: WorktreeFileProtocolFrame | undefined;
}): boolean {
	if (
		props.matchedReplacementDescriptor?.frameKind === 'worktree.fileDescriptor' &&
		areWorktreeFileDescriptorsSameContentVersion(
			props.matchedReplacementDescriptor.descriptor,
			props.currentDescriptor,
		)
	) {
		return true;
	}
	return (
		props.matchedInvalidation?.frameKind === 'worktree.fileInvalidated' &&
		props.matchedInvalidation.invalidation.latestDescriptor !== undefined &&
		areWorktreeFileDescriptorsSameContentVersion(
			props.matchedInvalidation.invalidation.latestDescriptor,
			props.currentDescriptor,
		)
	);
}

export function areWorktreeFileDescriptorsSameContentVersion(
	left: WorktreeFileDescriptor,
	right: WorktreeFileDescriptor,
): boolean {
	return (
		left.fileId === right.fileId &&
		left.path === right.path &&
		left.contentHandle === right.contentHandle &&
		left.contentHash === right.contentHash &&
		left.contentDescriptor.ref.descriptorId === right.contentDescriptor.ref.descriptorId
	);
}

export function areWorktreeFileSourceIdentitiesEqual(
	left: WorktreeFileSurfaceSourceIdentity,
	right: WorktreeFileSurfaceSourceIdentity,
): boolean {
	return (
		left.sourceId === right.sourceId &&
		left.repoId === right.repoId &&
		left.worktreeId === right.worktreeId &&
		left.subscriptionGeneration === right.subscriptionGeneration &&
		left.sourceCursor === right.sourceCursor
	);
}

export function resetSnapshotFramesKeepOpenFilePath(props: {
	readonly currentOpenFileState: BridgeFileViewerActiveOpenState;
	readonly frames: readonly WorktreeFileProtocolFrame[];
}): boolean {
	for (const frame of props.frames) {
		if (frame.frameKind !== 'worktree.snapshot' || frame.treeRows === undefined) {
			continue;
		}
		for (const row of frame.treeRows) {
			if (
				!row.isDirectory &&
				(row.fileId === props.currentOpenFileState.descriptor.fileId ||
					row.path === props.currentOpenFileState.path)
			) {
				return true;
			}
		}
	}
	return false;
}

export function findLatestDescriptorForOpenFile(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly renderState: BridgeFileViewerRenderState;
}): WorktreeFileDescriptor | null {
	return (
		props.renderState.descriptors.find(
			(descriptor) =>
				descriptor.fileId === props.descriptor.fileId || descriptor.path === props.descriptor.path,
		) ?? null
	);
}

export function totalTreeHeightForSizeFacts(props: {
	readonly filteredTreeRowCount: number;
	readonly hasActiveProjection: boolean;
	readonly sizeFacts: WorktreeTreeVirtualizedSizeFacts | null;
	readonly totalTreeRowCount: number;
}): {
	readonly heightPixels: number | null;
	readonly source: 'localProjection' | 'providerFacts' | null;
} {
	if (props.sizeFacts === null) {
		return { heightPixels: null, source: null };
	}
	if (!props.hasActiveProjection && props.sizeFacts.estimatedTotalHeightPixels !== undefined) {
		return { heightPixels: props.sizeFacts.estimatedTotalHeightPixels, source: 'providerFacts' };
	}
	if (!props.hasActiveProjection && props.sizeFacts.pathCount !== undefined) {
		return {
			heightPixels: Math.max(1, props.sizeFacts.pathCount) * props.sizeFacts.rowHeightPixels,
			source: 'providerFacts',
		};
	}
	if (
		props.hasActiveProjection &&
		props.filteredTreeRowCount === props.totalTreeRowCount &&
		props.sizeFacts.estimatedTotalHeightPixels !== undefined
	) {
		return { heightPixels: props.sizeFacts.estimatedTotalHeightPixels, source: 'providerFacts' };
	}
	if (
		props.hasActiveProjection &&
		props.filteredTreeRowCount === props.totalTreeRowCount &&
		props.sizeFacts.pathCount !== undefined
	) {
		return {
			heightPixels: Math.max(1, props.sizeFacts.pathCount) * props.sizeFacts.rowHeightPixels,
			source: 'providerFacts',
		};
	}
	return {
		heightPixels: Math.max(1, props.filteredTreeRowCount) * props.sizeFacts.rowHeightPixels,
		source: 'localProjection',
	};
}

export function renderedOpenFileContentForState(props: {
	readonly lastGoodOpenFileContent: BridgeFileViewerRenderedOpenFileContent | null;
	readonly openFileBody: string | null;
	readonly openFileBodyVersion: number;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly provisionalOpenFileBody: string | null;
	readonly selectedPath: string | null;
}): BridgeFileViewerRenderedOpenFileContent | null {
	if (props.openFileState.status === 'idle') {
		return null;
	}
	if (props.selectedPath !== null && props.selectedPath !== props.openFileState.path) {
		return props.lastGoodOpenFileContent;
	}
	if (props.openFileState.status === 'loading') {
		if (props.provisionalOpenFileBody !== null) {
			return {
				body: props.provisionalOpenFileBody,
				bodyVersion: props.openFileBodyVersion + 1,
				descriptor: props.openFileState.descriptor,
				path: props.openFileState.path,
			};
		}
		return null;
	}
	if (props.openFileState.status === 'refreshing') {
		if (props.provisionalOpenFileBody !== null) {
			return {
				body: props.provisionalOpenFileBody,
				bodyVersion: props.openFileBodyVersion + 1,
				descriptor: props.openFileState.descriptor,
				path: props.openFileState.path,
			};
		}
		if (props.openFileBody !== null) {
			return {
				body: props.openFileBody,
				bodyVersion: props.openFileBodyVersion,
				descriptor: props.openFileState.descriptor,
				path: props.openFileState.path,
			};
		}
		return props.lastGoodOpenFileContent;
	}
	if (props.openFileState.status === 'ready' || props.openFileState.status === 'stale') {
		if (props.openFileBody === null) {
			return props.lastGoodOpenFileContent;
		}
		return {
			body: props.openFileBody,
			bodyVersion: props.openFileBodyVersion,
			descriptor: props.openFileState.descriptor,
			path: props.openFileState.path,
		};
	}
	return null;
}

export function totalOpenFileHeightForState(
	openFileState: BridgeFileViewerOpenState,
): number | null {
	if (openFileState.status === 'idle') {
		return null;
	}
	const descriptor = openFileState.descriptor;
	if (descriptor.isBinary) {
		return null;
	}
	switch (descriptor.virtualizedExtentKind) {
		case 'exactLineCount':
			return descriptor.lineCount === undefined
				? null
				: descriptor.lineCount * defaultFileLineHeightPixels;
		case 'estimatedHeight':
			return descriptor.estimatedContentHeightPixels ?? null;
		case 'previewBounded':
		case 'unavailable':
			return null;
	}
	return null;
}

export async function defaultFetchWorktreeFileResource(
	props: WorktreeFileSurfaceRuntimeFetchResourceProps,
): Promise<WorktreeFileSurfaceRuntimeFetchedResource> {
	return await loadBridgeTextResourceWithTiming({
		integrity: props.descriptor.content.integrity,
		maxBytes: props.descriptor.content.maxBytes,
		onTextChunk: props.onTextChunk,
		performFetch: async (): Promise<Response> =>
			await fetch(props.resourceUrl, { signal: props.signal }),
		probe: props.probe,
		signal: props.signal,
	});
}
