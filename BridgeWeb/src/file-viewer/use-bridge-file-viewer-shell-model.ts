import { useEffect, useMemo } from 'react';

import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { countFlattenedWorktreeFileTreeRows } from '../features/worktree-file/models/worktree-file-tree-size.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeViewerWorktreeFileTreeTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type {
	BridgeFileViewerDescriptorProjection,
	BridgeFileViewerFilterMode,
	BridgeFileViewerSearchMode,
} from './bridge-file-viewer-contracts.js';
import {
	bridgeFileViewerHeaderTitle,
	findLatestDescriptorForOpenFile,
	projectBridgeFileViewerDescriptors,
	renderedOpenFileContentForState,
	totalOpenFileHeightForState,
	totalTreeHeightForSizeFacts,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerRenderedOpenFileContent,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerShellModelProps {
	readonly filterMode: BridgeFileViewerFilterMode;
	readonly lastGoodOpenFileContent: BridgeFileViewerRenderedOpenFileContent | null;
	readonly openFileBodyState: string | null;
	readonly openFileBodyVersion: number;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly provisionalOpenFileBody: string | null;
	readonly renderState: BridgeFileViewerRenderState;
	readonly searchMode: BridgeFileViewerSearchMode;
	readonly searchText: string;
	readonly selectedPath: string | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext: BridgeTraceContext | null;
}

export interface BridgeFileViewerShellModel {
	readonly canRefreshOpenFile: boolean;
	readonly contentHeaderTitle: string;
	readonly descriptorProjection: BridgeFileViewerDescriptorProjection;
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly metadataFileTreeRowCount: number;
	readonly openFileTotalHeightPixels: number | null;
	readonly renderedOpenFileContent: BridgeFileViewerRenderedOpenFileContent | null;
	readonly totalTreeHeight: {
		readonly heightPixels: number | null;
		readonly source: 'providerFacts' | 'localProjection' | null;
	};
	readonly totalTreeRowCount: number;
}

export function useBridgeFileViewerShellModel(
	props: UseBridgeFileViewerShellModelProps,
): BridgeFileViewerShellModel {
	const fileDescriptorByPath = useMemo(
		(): ReadonlyMap<string, WorktreeFileDescriptor> =>
			new Map(props.renderState.descriptors.map((descriptor) => [descriptor.path, descriptor])),
		[props.renderState.descriptors],
	);
	const descriptorProjectionResult = useMemo((): {
		readonly durationMilliseconds: number;
		readonly projection: BridgeFileViewerDescriptorProjection;
	} => {
		const projectionStartedAt = performance.now();
		const projection = projectBridgeFileViewerDescriptors({
			descriptors: props.renderState.descriptors,
			filterMode: props.filterMode,
			searchMode: props.searchMode,
			searchText: props.searchText,
			treeRows: props.renderState.treeRows,
		});
		return {
			durationMilliseconds: performance.now() - projectionStartedAt,
			projection,
		};
	}, [
		props.filterMode,
		props.renderState.descriptors,
		props.renderState.treeRows,
		props.searchMode,
		props.searchText,
	]);
	const descriptorProjection = descriptorProjectionResult.projection;
	useEffect((): void => {
		if (props.telemetryRecorder === undefined) {
			return;
		}
		recordBridgeViewerWorktreeFileTreeTelemetrySample({
			descriptorCount: descriptorProjection.descriptors.length,
			durationMilliseconds: descriptorProjectionResult.durationMilliseconds,
			frameCount: 0,
			phase: 'worktree_file_projection',
			result: 'success',
			telemetryRecorder: props.telemetryRecorder,
			traceContext: props.telemetryTraceContext,
			treeRowCount: descriptorProjection.treeRows.length,
			treeWindowRowCount: 0,
		});
	}, [
		descriptorProjection,
		descriptorProjectionResult.durationMilliseconds,
		props.telemetryRecorder,
		props.telemetryTraceContext,
	]);
	const totalTreeRowCount = props.renderState.treeRows.length;
	const totalTreeHeight = totalTreeHeightForSizeFacts({
		filteredTreeRowCount: countFlattenedWorktreeFileTreeRows(descriptorProjection.paths),
		hasActiveProjection:
			props.filterMode !== 'all' ||
			props.searchText.trim().length > 0 ||
			descriptorProjection.searchError !== null,
		sizeFacts: props.renderState.treeSizeFacts,
		totalTreeRowCount,
	});
	const renderedOpenFileContent = useMemo(
		(): BridgeFileViewerRenderedOpenFileContent | null =>
			renderedOpenFileContentForState({
				lastGoodOpenFileContent: props.lastGoodOpenFileContent,
				openFileBody: props.openFileBodyState,
				openFileBodyVersion: props.openFileBodyVersion,
				openFileState: props.openFileState,
				provisionalOpenFileBody: props.provisionalOpenFileBody,
				selectedPath: props.selectedPath,
			}),
		[
			props.lastGoodOpenFileContent,
			props.openFileBodyState,
			props.openFileBodyVersion,
			props.openFileState,
			props.provisionalOpenFileBody,
			props.selectedPath,
		],
	);

	return {
		canRefreshOpenFile:
			props.openFileState.status === 'stale' &&
			findLatestDescriptorForOpenFile({
				descriptor: props.openFileState.descriptor,
				renderState: props.renderState,
			}) !== null,
		contentHeaderTitle: bridgeFileViewerHeaderTitle({
			selectedPath: props.selectedPath,
			sourceIdentity: props.renderState.sourceIdentity,
		}),
		descriptorProjection,
		fileDescriptorByPath,
		metadataFileTreeRowCount: props.renderState.treeRows.filter(
			(treeRow): boolean => !treeRow.isDirectory && treeRow.fileId !== undefined,
		).length,
		openFileTotalHeightPixels: totalOpenFileHeightForState(props.openFileState),
		renderedOpenFileContent,
		totalTreeHeight,
		totalTreeRowCount,
	};
}
