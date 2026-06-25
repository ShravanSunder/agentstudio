import type { CodeViewItem } from '@pierre/diffs';
import { CodeView } from '@pierre/diffs/react';
import { useLayoutEffect, useRef, type CSSProperties, type ReactElement } from 'react';

import type { WorktreeFileDescriptor } from '../../features/worktree-file/models/worktree-file-protocol-models.js';
import { BridgePierreWorkerPoolProvider } from '../workers/pierre/bridge-pierre-worker-pool.js';
import { bridgeCodeViewOptions } from './bridge-code-view-panel.js';

export type BridgeFileViewerCodePanelState =
	| { readonly status: 'idle' }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed' | 'loading' | 'ready' | 'refreshing' | 'stale' | 'unavailable';
	  };

export interface BridgeFileViewerCodePanelProps {
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly openFileBody: string | null;
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly totalHeightPixels: number | null;
	readonly staleNotice?: ReactElement | null;
}

export function BridgeFileViewerCodePanel(props: BridgeFileViewerCodePanelProps): ReactElement {
	const scrollContainerRef = useRef<HTMLElement | null>(null);
	const lastScrollTopRef = useRef(0);
	const previousOpenStateRef = useRef<{
		readonly path: string | null;
		readonly status: BridgeFileViewerCodePanelState['status'];
	}>({ path: null, status: 'idle' });
	const codeViewItems = codeViewItemsForOpenFile({
		openFileBody: props.openFileBody,
		openFileState: props.openFileState,
	});
	useLayoutEffect((): void => {
		const currentPath = props.openFileState.status === 'idle' ? null : props.openFileState.path;
		const currentStatus = props.openFileState.status;
		const previousOpenState = previousOpenStateRef.current;
		if (
			currentPath !== null &&
			currentPath === previousOpenState.path &&
			currentStatus === 'ready' &&
			(previousOpenState.status === 'loading' || previousOpenState.status === 'refreshing')
		) {
			const scrollTop = lastScrollTopRef.current;
			requestAnimationFrame((): void => {
				if (scrollTop > 0 && scrollContainerRef.current !== null) {
					scrollContainerRef.current.scrollTop = scrollTop;
				}
			});
		}
		previousOpenStateRef.current = { path: currentPath, status: currentStatus };
	}, [props.openFileState]);
	return (
		<section
			aria-label="Selected file"
			className="bridge-scrollbar min-h-0 min-w-0 overflow-auto overscroll-contain bg-[var(--bridge-canvas-bg)]"
			data-pierre-code-view-owner="CodeView.file"
			data-shiki-rendering="pierre"
			data-testid="bridge-file-viewer-code-canvas"
			data-worker-backed-highlighting={
				props.codeViewWorkerPoolEnabled === true ? 'requested' : 'disabled'
			}
			{...(props.openFileState.status === 'idle'
				? {}
				: {
						'data-worktree-open-file-path': props.openFileState.path,
						'data-worktree-open-file-state': props.openFileState.status,
					})}
			{...(props.totalHeightPixels === null
				? {}
				: { 'data-worktree-open-file-total-size': String(props.totalHeightPixels) })}
			onScroll={(event) => {
				lastScrollTopRef.current = event.currentTarget.scrollTop;
			}}
			ref={scrollContainerRef}
		>
			<div className="relative h-full min-h-0 min-w-0" data-testid="bridge-file-viewer-code-view">
				<BridgePierreWorkerPoolProvider
					{...(props.codeViewWorkerPoolEnabled === undefined
						? {}
						: { enabled: props.codeViewWorkerPoolEnabled })}
					{...(props.codeViewWorkerFactory === undefined
						? {}
						: { workerFactory: props.codeViewWorkerFactory })}
				>
					{codeViewItems.length === 0 ? (
						<BridgeFileViewerContentState
							state={props.openFileState}
							totalHeightPixels={props.totalHeightPixels}
						/>
					) : (
						<CodeView items={codeViewItems} options={bridgeCodeViewOptions} />
					)}
				</BridgePierreWorkerPoolProvider>
				{props.staleNotice ?? null}
			</div>
		</section>
	);
}

function BridgeFileViewerContentState(props: {
	readonly state: BridgeFileViewerCodePanelState;
	readonly totalHeightPixels: number | null;
}): ReactElement {
	const label =
		props.state.status === 'idle'
			? 'Select a file'
			: props.state.status === 'loading'
				? 'Loading file'
				: 'Content unavailable';
	return (
		<div
			className="relative flex min-h-full items-start justify-center text-sm text-[var(--bridge-text-secondary)]"
			data-testid="bridge-file-viewer-content-state"
			role="status"
			style={reservedExtentStyleForState({
				state: props.state,
				totalHeightPixels: props.totalHeightPixels,
			})}
		>
			<div className="sticky top-0 flex min-h-screen items-center justify-center">{label}</div>
		</div>
	);
}

function reservedExtentStyleForState(props: {
	readonly state: BridgeFileViewerCodePanelState;
	readonly totalHeightPixels: number | null;
}): CSSProperties | undefined {
	if (props.state.status === 'idle' || props.totalHeightPixels === null) {
		return undefined;
	}
	return { minHeight: props.totalHeightPixels };
}

function codeViewItemsForOpenFile(props: {
	readonly openFileBody: string | null;
	readonly openFileState: BridgeFileViewerCodePanelState;
}): readonly CodeViewItem[] {
	if (props.openFileState.status === 'idle' || props.openFileBody === null) {
		return [];
	}
	const descriptor = props.openFileState.descriptor;
	return [
		{
			id: `file:${descriptor.fileId}`,
			type: 'file',
			file: {
				name: props.openFileState.path,
				contents: props.openFileBody,
				cacheKey: `${descriptor.contentHandle}:${descriptor.contentHash ?? 'unknown'}`,
			},
			version: codeViewItemVersionForDescriptor(descriptor),
		},
	];
}

function codeViewItemVersionForDescriptor(descriptor: WorktreeFileDescriptor): number {
	if (descriptor.contentHash === undefined) {
		return 0;
	}
	const hashHex = descriptor.contentHash.startsWith('sha256:')
		? descriptor.contentHash.slice('sha256:'.length)
		: descriptor.contentHash;
	const version = Number.parseInt(hashHex.slice(0, 8), 16);
	return Number.isFinite(version) ? version : 0;
}
