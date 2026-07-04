import { prepareFileTreeInput, type FileTreeBatchOperation } from '@pierre/trees';
import { useFileTree } from '@pierre/trees/react';
import { useCallback, useEffect, useRef, type MouseEvent as ReactMouseEvent } from 'react';

import {
	appendedOnlyPierreTreePaths,
	expandAncestorDirectoriesForPierreTreePaths,
	pierreFilePathFromTreeEvent,
	type BridgePierreTreeModelForExpansion,
	type BridgePierreTreeScrollOwner,
} from '../app/bridge-pierre-tree-adapter.js';
import { bridgeViewerTreeUnsafeCSS } from '../app/bridge-viewer-tree-theme.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeViewerFirstInteractionReady } from '../foundation/telemetry/bridge-viewer-first-interaction.js';
import {
	recordBridgeTreeScrollToPathTelemetrySample,
	recordBridgeTreeScrollVisibleDemandTelemetrySample,
} from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type {
	BridgeFileViewerDescriptorProjection,
	BridgeFileViewerVisibleFileDemandChange,
} from './bridge-file-viewer-contracts.js';
import {
	pierreFileTreeScrollElementForDemand,
	visibleDescriptorRefsForPierreDemand,
} from './bridge-file-viewer-pierre-visible-demand.js';

export interface UseBridgeFileViewerPierreTreeRuntimeProps {
	readonly descriptorProjection: BridgeFileViewerDescriptorProjection;
	readonly fileDescriptorByPath: ReadonlyMap<string, WorktreeFileDescriptor>;
	readonly onOpenFile: (descriptor: WorktreeFileDescriptor) => Promise<void>;
	readonly onRequestFileDescriptor?: (
		request: WorktreeFileDescriptorRequest,
	) => Promise<void> | void;
	readonly onVisibleFileDemandChange?: (change: BridgeFileViewerVisibleFileDemandChange) => void;
	readonly selectedPath: string | null;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
}

export interface BridgeFileViewerPierreTreeRuntime {
	readonly handleTreeClick: (event: ReactMouseEvent<HTMLElement>) => void;
	readonly model: ReturnType<typeof useFileTree>['model'];
}

const bridgeFileViewerTreeRowHeightPixels = 24;
const bridgeFileViewerTreeOptions = {
	flattenEmptyDirectories: true,
	sort: 'default',
} as const;

export function useBridgeFileViewerPierreTreeRuntime(
	props: UseBridgeFileViewerPierreTreeRuntimeProps,
): BridgeFileViewerPierreTreeRuntime {
	const fileDescriptorByPathRef = useRef(props.fileDescriptorByPath);
	const onOpenFileRef = useRef(props.onOpenFile);
	const onRequestFileDescriptorRef = useRef(props.onRequestFileDescriptor);
	const sourceIdentityRef = useRef(props.sourceIdentity);
	const treeRowsRef = useRef(props.descriptorProjection.treeRows);
	const isSyncingSelectedPathRef = useRef(false);
	const firstInteractionMountStartedAtRef = useRef(performance.now());
	const hasRecordedFirstInteractionRef = useRef(false);
	const paths = props.descriptorProjection.paths;
	const appliedTreePathsRef = useRef(paths);
	const initialPreparedInputRef = useRef<ReturnType<typeof prepareFileTreeInput> | null>(null);
	const initialPreparedInput =
		initialPreparedInputRef.current ?? prepareFileTreeInput(paths, bridgeFileViewerTreeOptions);
	initialPreparedInputRef.current = initialPreparedInput;
	fileDescriptorByPathRef.current = props.fileDescriptorByPath;
	onOpenFileRef.current = props.onOpenFile;
	onRequestFileDescriptorRef.current = props.onRequestFileDescriptor;
	sourceIdentityRef.current = props.sourceIdentity;
	treeRowsRef.current = props.descriptorProjection.treeRows;

	const openOrRequestPath = useCallback((selectedPath: string): void => {
		const descriptor = fileDescriptorByPathRef.current.get(selectedPath);
		if (descriptor !== undefined) {
			void onOpenFileRef.current(descriptor);
			return;
		}
		const request = descriptorRequestForSelectedPath({
			path: selectedPath,
			sourceIdentity: sourceIdentityRef.current,
			treeRows: treeRowsRef.current,
		});
		if (request !== null) {
			void onRequestFileDescriptorRef.current?.(request);
		}
	}, []);
	const selectionCoordinatorRef = useRef<BridgeFileViewerTreeSelectionCoordinator | null>(null);
	selectionCoordinatorRef.current ??= createBridgeFileViewerTreeSelectionCoordinator({
		openOrRequestPath,
	});

	const { model } = useFileTree({
		preparedInput: initialPreparedInput,
		flattenEmptyDirectories: true,
		initialExpansion: 'open',
		initialSelectedPaths: props.selectedPath === null ? [] : [props.selectedPath],
		itemHeight: bridgeFileViewerTreeRowHeightPixels,
		onSelectionChange: (selectedPaths): void => {
			if (isSyncingSelectedPathRef.current) {
				return;
			}
			const selectedPath = selectedPaths[0];
			if (selectedPath === undefined) {
				return;
			}
			selectionCoordinatorRef.current?.recordPierreSelectionPath(selectedPath);
		},
		search: false,
		sort: 'default',
		unsafeCSS: bridgeViewerTreeUnsafeCSS,
	});

	useEffect((): void => {
		const previousPaths = appliedTreePathsRef.current;
		if (previousPaths === paths) {
			return;
		}
		const appendedPaths = appendedOnlyPierreTreePaths({
			nextPaths: paths,
			previousPaths,
		});
		if (appendedPaths === null) {
			model.resetPaths(paths, {
				preparedInput: prepareFileTreeInput(paths, bridgeFileViewerTreeOptions),
			});
		} else if (appendedPaths.length > 0) {
			model.batch(appendedPaths.map(fileTreeAddOperation));
			expandAncestorDirectoriesForPierreTreePaths({
				model,
				paths: appendedPaths,
			});
		}
		appliedTreePathsRef.current = paths;
	}, [model, paths]);

	const onVisibleFileDemandChange = props.onVisibleFileDemandChange;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;
	const publishVisibleFileDemand = useCallback((): void => {
		if (onVisibleFileDemandChange === undefined) {
			return;
		}
		const publishStartedAt = performance.now();
		const descriptorRefs = visibleDescriptorRefsForPierreDemand({
			fileDescriptorByPath: fileDescriptorByPathRef.current,
			model,
			telemetryRecorder,
			telemetryTraceContext,
		});
		if (descriptorRefs.length === 0) {
			return;
		}
		onVisibleFileDemandChange({
			descriptorRefs,
			visibleFileCount: descriptorRefs.length,
		});
		if (telemetryRecorder !== undefined) {
			recordBridgeTreeScrollVisibleDemandTelemetrySample({
				durationMilliseconds: performance.now() - publishStartedAt,
				telemetryRecorder,
				traceContext: telemetryTraceContext,
				viewer: 'file',
				visibleItemCount: descriptorRefs.length,
			});
		}
	}, [
		fileDescriptorByPathRef,
		model,
		onVisibleFileDemandChange,
		telemetryRecorder,
		telemetryTraceContext,
	]);

	useEffect((): (() => void) => {
		let scrollElement: BridgePierreTreeScrollOwner | null = null;
		let animationFrameId: number | null = null;
		const scheduleVisibleFileDemand = (): void => {
			if (animationFrameId !== null) {
				return;
			}
			animationFrameId = requestAnimationFrame((): void => {
				animationFrameId = null;
				publishVisibleFileDemand();
			});
		};
		const setupFrameId = requestAnimationFrame((): void => {
			scrollElement = pierreFileTreeScrollElementForDemand(model);
			scrollElement?.addEventListener('scroll', scheduleVisibleFileDemand, { passive: true });
			publishVisibleFileDemand();
			// Only anchor time-to-first-interaction once the tree actually has rows painted.
			// On a large streaming worktree the tree shell mounts before metadata arrives, so
			// an ungated RAF would fire against an empty tree and understate the metric.
			if (!hasRecordedFirstInteractionRef.current && paths.length > 0) {
				hasRecordedFirstInteractionRef.current = true;
				recordBridgeViewerFirstInteractionReady({
					viewer: 'file',
					telemetryRecorder,
					mountStartedAtPerfNow: firstInteractionMountStartedAtRef.current,
					visibleItemCount: visibleDescriptorRefsForPierreDemand({
						fileDescriptorByPath: fileDescriptorByPathRef.current,
						model,
						telemetryRecorder,
						telemetryTraceContext,
					}).length,
					fallbackTraceContext: telemetryTraceContext,
				});
			}
		});
		const unsubscribeModel = model.subscribe(scheduleVisibleFileDemand);
		return (): void => {
			cancelAnimationFrame(setupFrameId);
			if (animationFrameId !== null) {
				cancelAnimationFrame(animationFrameId);
			}
			scrollElement?.removeEventListener('scroll', scheduleVisibleFileDemand);
			unsubscribeModel();
		};
	}, [model, paths, publishVisibleFileDemand, telemetryRecorder, telemetryTraceContext]);

	useEffect((): void => {
		if (props.selectedPath === null) {
			return;
		}
		const item = model.getItem(props.selectedPath);
		if (item === null || item.isSelected()) {
			return;
		}
		isSyncingSelectedPathRef.current = true;
		try {
			item.select();
		} finally {
			isSyncingSelectedPathRef.current = false;
		}
		recordFileTreeScrollToPath({
			focus: true,
			model,
			offset: 'nearest',
			path: props.selectedPath,
			reason: 'selected_path_effect',
			telemetryRecorder,
			traceContext: telemetryTraceContext,
		});
	}, [model, props.selectedPath, paths, telemetryRecorder, telemetryTraceContext]);

	const handleTreeClick = useCallback((event: ReactMouseEvent<HTMLElement>): void => {
		const selectedPath = pierreFilePathFromTreeEvent(event.nativeEvent);
		if (selectedPath === null) {
			return;
		}
		selectionCoordinatorRef.current?.handleClickedPath(selectedPath);
	}, []);

	return { handleTreeClick, model };
}

export interface BridgeFileViewerTreeSelectionCoordinator {
	readonly handleClickedPath: (path: string) => void;
	readonly recordPierreSelectionPath: (path: string) => void;
}

export function createBridgeFileViewerTreeSelectionCoordinator(props: {
	readonly openOrRequestPath: (path: string) => void;
}): BridgeFileViewerTreeSelectionCoordinator {
	let lastSelectionChangePath: string | null = null;
	return {
		handleClickedPath(path: string): void {
			if (lastSelectionChangePath === path) {
				lastSelectionChangePath = null;
				return;
			}
			props.openOrRequestPath(path);
		},
		recordPierreSelectionPath(path: string): void {
			lastSelectionChangePath = path;
			props.openOrRequestPath(path);
		},
	};
}

function descriptorRequestForSelectedPath(props: {
	readonly path: string;
	readonly sourceIdentity: WorktreeFileSurfaceSourceIdentity | null;
	readonly treeRows: readonly WorktreeTreeRowMetadata[];
}): WorktreeFileDescriptorRequest | null {
	if (props.sourceIdentity === null) {
		return null;
	}
	const row = props.treeRows.find((candidate): boolean => candidate.path === props.path);
	if (row === undefined || row.isDirectory || row.fileId === undefined) {
		return null;
	}
	return {
		sourceIdentity: props.sourceIdentity,
		rowId: row.rowId,
		path: row.path,
		fileId: row.fileId,
		lane: 'foreground',
	};
}

function fileTreeAddOperation(path: string): FileTreeBatchOperation {
	return { type: 'add', path };
}

function recordFileTreeScrollToPath(props: {
	readonly focus: boolean;
	readonly model: ReturnType<typeof useFileTree>['model'];
	readonly offset: 'nearest' | 'top';
	readonly path: string;
	readonly reason: 'selected_path_effect';
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly traceContext: BridgeTraceContext | null;
}): void {
	const startedAt = performance.now();
	props.model.scrollToPath(props.path, { focus: props.focus, offset: props.offset });
	if (props.telemetryRecorder === undefined) {
		return;
	}
	recordBridgeTreeScrollToPathTelemetrySample({
		durationMilliseconds: performance.now() - startedAt,
		focus: props.focus,
		offset: props.offset,
		reason: props.reason,
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		viewer: 'file',
	});
}

export type BridgeFileViewerTreeModelForAppend = BridgePierreTreeModelForExpansion;
