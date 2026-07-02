import { prepareFileTreeInput, type FileTreeBatchOperation } from '@pierre/trees';
import { useFileTree } from '@pierre/trees/react';
import { useCallback, useEffect, useRef, type MouseEvent as ReactMouseEvent } from 'react';

import { bridgeViewerTreeUnsafeCSS } from '../app/bridge-viewer-tree-theme.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeRowMetadata,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeTreeScrollVisibleDemandTelemetrySample } from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
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
		const appendedPaths = appendedOnlyPaths({
			nextPaths: paths,
			previousPaths,
		});
		if (appendedPaths === null) {
			model.resetPaths(paths, {
				preparedInput: prepareFileTreeInput(paths, bridgeFileViewerTreeOptions),
			});
		} else if (appendedPaths.length > 0) {
			model.batch(appendedPaths.map(fileTreeAddOperation));
			expandAncestorDirectoriesForAppendedPaths({
				model,
				paths: appendedPaths,
			});
		}
		appliedTreePathsRef.current = paths;
	}, [model, paths]);

	const fileDescriptorByPath = props.fileDescriptorByPath;
	const onVisibleFileDemandChange = props.onVisibleFileDemandChange;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;
	const publishVisibleFileDemand = useCallback((): void => {
		if (onVisibleFileDemandChange === undefined) {
			return;
		}
		const publishStartedAt = performance.now();
		const descriptorRefs = visibleDescriptorRefsForPierreDemand({
			fileDescriptorByPath,
			model,
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
		fileDescriptorByPath,
		model,
		onVisibleFileDemandChange,
		telemetryRecorder,
		telemetryTraceContext,
	]);

	useEffect((): (() => void) => {
		let scrollElement: HTMLElement | null = null;
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
	}, [model, paths, publishVisibleFileDemand]);

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
		model.scrollToPath(props.selectedPath, { focus: true, offset: 'nearest' });
	}, [model, props.selectedPath, paths]);

	const handleTreeClick = useCallback((event: ReactMouseEvent<HTMLElement>): void => {
		const selectedPath = fileTreePathFromClickEvent(event);
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

export interface BridgeFileViewerTreeDirectoryHandle {
	readonly isDirectory: () => boolean;
	readonly isExpanded: () => boolean;
	readonly expand: () => void;
}

export interface BridgeFileViewerTreeItemHandleForAppend {
	readonly isDirectory: () => boolean;
	readonly isExpanded?: () => boolean;
	readonly expand?: () => void;
}

export interface BridgeFileViewerTreeModelForAppend {
	readonly getItem: (path: string) => BridgeFileViewerTreeItemHandleForAppend | null;
	readonly resolveMountedDirectoryPathFromInput?: (path: string) => string | null;
}

export function appendedOnlyPaths(props: {
	readonly nextPaths: readonly string[];
	readonly previousPaths: readonly string[];
}): readonly string[] | null {
	if (props.nextPaths.length < props.previousPaths.length) {
		return null;
	}
	for (let index = 0; index < props.previousPaths.length; index += 1) {
		if (props.nextPaths[index] !== props.previousPaths[index]) {
			return null;
		}
	}
	return props.nextPaths.slice(props.previousPaths.length);
}

export function expandAncestorDirectoriesForAppendedPaths(props: {
	readonly model: BridgeFileViewerTreeModelForAppend;
	readonly paths: readonly string[];
}): void {
	for (const path of props.paths) {
		for (const ancestorPath of ancestorDirectoryPaths(path)) {
			const item = directoryItemForInputPath({
				model: props.model,
				path: ancestorPath,
			});
			if (isExpandableDirectoryHandle(item) && !item.isExpanded()) {
				item.expand();
			}
		}
	}
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

function fileTreePathFromClickEvent(event: ReactMouseEvent<HTMLElement>): string | null {
	for (const target of event.nativeEvent.composedPath()) {
		if (!(target instanceof HTMLElement)) {
			continue;
		}
		const itemType = target.getAttribute('data-item-type');
		const itemPath = target.getAttribute('data-item-path');
		if (itemType === 'file' && itemPath !== null && itemPath.length > 0) {
			return itemPath;
		}
	}
	return null;
}

function fileTreeAddOperation(path: string): FileTreeBatchOperation {
	return { type: 'add', path };
}

function directoryItemForInputPath(props: {
	readonly model: BridgeFileViewerTreeModelForAppend;
	readonly path: string;
}): BridgeFileViewerTreeItemHandleForAppend | null {
	const slashPath = `${props.path}/`;
	const mountedPath =
		props.model.resolveMountedDirectoryPathFromInput?.(props.path) ??
		props.model.resolveMountedDirectoryPathFromInput?.(slashPath) ??
		null;
	if (mountedPath !== null) {
		return props.model.getItem(mountedPath);
	}
	return props.model.getItem(props.path) ?? props.model.getItem(slashPath);
}

function isExpandableDirectoryHandle(
	item: BridgeFileViewerTreeItemHandleForAppend | null,
): item is BridgeFileViewerTreeDirectoryHandle {
	return (
		item?.isDirectory() === true &&
		typeof item.isExpanded === 'function' &&
		typeof item.expand === 'function'
	);
}

function ancestorDirectoryPaths(path: string): readonly string[] {
	const segments = path.split('/').filter((segment: string): boolean => segment.length > 0);
	const ancestorPaths: string[] = [];
	let currentPath = '';
	for (const segment of segments.slice(0, -1)) {
		currentPath = currentPath.length === 0 ? segment : `${currentPath}/${segment}`;
		ancestorPaths.push(currentPath);
	}
	return ancestorPaths;
}
