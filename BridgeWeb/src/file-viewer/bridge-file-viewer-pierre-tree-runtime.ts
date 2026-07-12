import { useFileTree } from '@pierre/trees/react';
import {
	useCallback,
	useEffect,
	useRef,
	useSyncExternalStore,
	type MouseEvent as ReactMouseEvent,
} from 'react';

import {
	pierreFilePathFromTreeEvent,
	type BridgePierreTreeModelForExpansion,
	type BridgePierreTreeScrollOwner,
} from '../app/bridge-pierre-tree-adapter.js';
import { bridgeViewerTreeUnsafeCSS } from '../app/bridge-viewer-tree-theme.js';
import type { BridgeMainFileTreePatchStream } from '../core/comm-worker/bridge-main-file-display-patch-applier.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeViewerFirstInteractionReady } from '../foundation/telemetry/bridge-viewer-first-interaction.js';
import {
	recordBridgeTreeScrollToPathTelemetrySample,
	recordBridgeTreeScrollVisibleDemandTelemetrySample,
} from '../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { BridgeFileViewerVisibleFileDemandChange } from './bridge-file-viewer-contracts.js';
import type {
	BridgeFileViewerDisplayTreeRow,
	BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import {
	pierreFileTreeScrollElementForDemand,
	visibleFileDemandChangeForPierreDemand,
} from './bridge-file-viewer-pierre-visible-demand.js';
import {
	createBridgeFileViewerTreePatchCoordinator,
	type BridgeFileViewerTreePatchCoordinator,
} from './bridge-file-viewer-tree-patch-coordinator.js';

export interface UseBridgeFileViewerPierreTreeRuntimeProps {
	readonly completeFileQueryTransaction: (transactionId: string) => boolean;
	readonly fileTreePatchStream: BridgeMainFileTreePatchStream;
	readonly onSelectFile: (selection: BridgeFileViewerSelection) => void;
	readonly onVisibleFileDemandChange?: (change: BridgeFileViewerVisibleFileDemandChange) => void;
	readonly selectedPath: string | null;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly treeRowByPath: {
		readonly get: (path: string) => BridgeFileViewerDisplayTreeRow | undefined;
	};
}

export interface BridgeFileViewerPierreTreeRuntime {
	readonly handleTreeClick: (event: ReactMouseEvent<HTMLElement>) => void;
	readonly model: ReturnType<typeof useFileTree>['model'];
}

const bridgeFileViewerTreeRowHeightPixels = 24;
export function useBridgeFileViewerPierreTreeRuntime(
	props: UseBridgeFileViewerPierreTreeRuntimeProps,
): BridgeFileViewerPierreTreeRuntime {
	const onSelectFileRef = useRef(props.onSelectFile);
	const treeRowByPathRef = useRef(props.treeRowByPath);
	const completeFileQueryTransactionRef = useRef(props.completeFileQueryTransaction);
	const isSyncingSelectedPathRef = useRef(false);
	const firstInteractionMountStartedAtRef = useRef(performance.now());
	const hasRecordedFirstInteractionRef = useRef(false);
	onSelectFileRef.current = props.onSelectFile;
	treeRowByPathRef.current = props.treeRowByPath;
	completeFileQueryTransactionRef.current = props.completeFileQueryTransaction;

	const selectPath = useCallback((selectedPath: string): void => {
		const normalizedPath = selectedPath.endsWith('/') ? selectedPath.slice(0, -1) : selectedPath;
		const row = treeRowByPathRef.current.get(normalizedPath);
		if (row?.fileId === null || row?.fileId === undefined || row.isDirectory) {
			return;
		}
		onSelectFileRef.current({ fileId: row.fileId, path: row.path });
	}, []);
	const selectionCoordinatorRef = useRef<BridgeFileViewerTreeSelectionCoordinator | null>(null);
	selectionCoordinatorRef.current ??= createBridgeFileViewerTreeSelectionCoordinator({
		selectPath,
	});

	const handleSelectionChange = (selectedPaths: readonly string[]): void => {
		if (isSyncingSelectedPathRef.current) return;
		const selectedPath = selectedPaths[0];
		if (selectedPath !== undefined) {
			selectionCoordinatorRef.current?.recordPierreSelectionPath(selectedPath);
		}
	};
	const { model } = useFileTree({
		paths: [],
		flattenEmptyDirectories: true,
		initialExpansion: 'open',
		initialSelectedPaths: props.selectedPath === null ? [] : [props.selectedPath],
		itemHeight: bridgeFileViewerTreeRowHeightPixels,
		onSelectionChange: handleSelectionChange,
		search: false,
		sort: 'default',
		unsafeCSS: bridgeViewerTreeUnsafeCSS,
	});
	const patchCoordinatorRef = useRef<BridgeFileViewerTreePatchCoordinator | null>(null);
	patchCoordinatorRef.current ??= createBridgeFileViewerTreePatchCoordinator({
		model,
		onQueryTransactionReady: (transactionId): boolean =>
			completeFileQueryTransactionRef.current(transactionId),
	});
	useBridgeFileTreePatchStream({
		coordinator: patchCoordinatorRef.current,
		stream: props.fileTreePatchStream,
	});

	const onVisibleFileDemandChange = props.onVisibleFileDemandChange;
	const telemetryRecorder = props.telemetryRecorder;
	const telemetryTraceContext = props.telemetryTraceContext ?? null;
	const publishVisibleFileDemand = useCallback((): void => {
		if (onVisibleFileDemandChange === undefined) {
			return;
		}
		const publishStartedAt = performance.now();
		const demandChange = visibleFileDemandChangeForPierreDemand({
			model,
			telemetryRecorder,
			telemetryTraceContext,
			treeRowByPath: treeRowByPathRef.current,
		});
		if (demandChange === null) {
			return;
		}
		onVisibleFileDemandChange(demandChange);
		if (telemetryRecorder !== undefined) {
			recordBridgeTreeScrollVisibleDemandTelemetrySample({
				durationMilliseconds: performance.now() - publishStartedAt,
				telemetryRecorder,
				traceContext: telemetryTraceContext,
				viewer: 'file',
				visibleItemCount: demandChange.visibleFileCount,
			});
		}
	}, [model, onVisibleFileDemandChange, telemetryRecorder, telemetryTraceContext]);

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
			if (!hasRecordedFirstInteractionRef.current && props.fileTreePatchStream.getCursor() > 0) {
				hasRecordedFirstInteractionRef.current = true;
				recordBridgeViewerFirstInteractionReady({
					fallbackTraceContext: telemetryTraceContext,
					mountStartedAtPerfNow: firstInteractionMountStartedAtRef.current,
					telemetryRecorder,
					viewer: 'file',
					visibleItemCount:
						visibleFileDemandChangeForPierreDemand({
							model,
							telemetryRecorder,
							telemetryTraceContext,
							treeRowByPath: treeRowByPathRef.current,
						})?.visibleItemIds.length ?? 0,
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
	}, [
		model,
		props.fileTreePatchStream,
		publishVisibleFileDemand,
		telemetryRecorder,
		telemetryTraceContext,
	]);

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
	}, [model, props.selectedPath, telemetryRecorder, telemetryTraceContext]);

	const handleTreeClick = useCallback((event: ReactMouseEvent<HTMLElement>): void => {
		const selectedPath = pierreFilePathFromTreeEvent(event.nativeEvent);
		if (selectedPath !== null) {
			selectionCoordinatorRef.current?.handleClickedPath(selectedPath);
		}
	}, []);

	return { handleTreeClick, model };
}

function useBridgeFileTreePatchStream(props: {
	readonly coordinator: BridgeFileViewerTreePatchCoordinator;
	readonly stream: BridgeMainFileTreePatchStream;
}): void {
	const streamCursor = useSyncExternalStore(
		props.stream.subscribe,
		props.stream.getCursor,
		props.stream.getServerCursor,
	);
	const appliedCursorRef = useRef(0);
	const queuedCursorRef = useRef(0);
	const queuedEntriesRef = useRef<ReturnType<BridgeMainFileTreePatchStream['readAfter']>[number][]>(
		[],
	);
	const animationFrameIdRef = useRef<number | null>(null);
	const coordinatorRef = useRef(props.coordinator);
	coordinatorRef.current = props.coordinator;

	useEffect((): void => {
		const newEntries = props.stream.readAfter(queuedCursorRef.current);
		if (newEntries.length > 0) {
			queuedEntriesRef.current.push(...newEntries);
			queuedCursorRef.current = newEntries.at(-1)?.cursor ?? queuedCursorRef.current;
		}
		const drainNextEntry = (): void => {
			const entry = queuedEntriesRef.current.shift();
			if (entry === undefined) {
				animationFrameIdRef.current = null;
				return;
			}
			coordinatorRef.current.applyEntry(entry);
			appliedCursorRef.current = entry.cursor;
			animationFrameIdRef.current = requestAnimationFrame(drainNextEntry);
		};
		if (animationFrameIdRef.current === null && queuedEntriesRef.current.length > 0) {
			animationFrameIdRef.current = requestAnimationFrame(drainNextEntry);
		}
	}, [props.stream, streamCursor]);

	useEffect(
		(): (() => void) => (): void => {
			if (animationFrameIdRef.current !== null) {
				cancelAnimationFrame(animationFrameIdRef.current);
				animationFrameIdRef.current = null;
			}
			queuedEntriesRef.current = [];
			queuedCursorRef.current = appliedCursorRef.current;
		},
		[],
	);
}

export interface BridgeFileViewerTreeSelectionCoordinator {
	readonly handleClickedPath: (path: string) => void;
	readonly recordPierreSelectionPath: (path: string) => void;
}

export function createBridgeFileViewerTreeSelectionCoordinator(props: {
	readonly selectPath: (path: string) => void;
}): BridgeFileViewerTreeSelectionCoordinator {
	let pendingCounterpart: { readonly path: string; readonly source: 'click' | 'selection' } | null =
		null;
	return {
		handleClickedPath(path: string): void {
			if (pendingCounterpart?.path === path && pendingCounterpart.source === 'selection') {
				pendingCounterpart = null;
				return;
			}
			pendingCounterpart = { path, source: 'click' };
			props.selectPath(path);
		},
		recordPierreSelectionPath(path: string): void {
			if (pendingCounterpart?.path === path && pendingCounterpart.source === 'click') {
				pendingCounterpart = null;
				return;
			}
			pendingCounterpart = { path, source: 'selection' };
			props.selectPath(path);
		},
	};
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
	if (props.telemetryRecorder !== undefined) {
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
}

export type BridgeFileViewerTreeModelForAppend = BridgePierreTreeModelForExpansion;
