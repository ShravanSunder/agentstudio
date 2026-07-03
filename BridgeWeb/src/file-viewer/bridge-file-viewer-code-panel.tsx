import type { CodeViewOptions } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import { useLayoutEffect, useMemo, useRef, type ReactElement } from 'react';

import { bridgeCodeViewOptions } from '../review-viewer/code-view/bridge-code-view-panel.js';
import { BridgePierreWorkerPoolProvider } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import {
	bridgeFileViewerCodeViewItemsForPanelState,
	type BridgeFileViewerCodePanelContent,
	type BridgeFileViewerCodePanelState,
} from './bridge-file-viewer-code-view-items.js';

const bridgeFileViewerCodeViewOptions: CodeViewOptions<undefined> = {
	...bridgeCodeViewOptions,
	disableFileHeader: true,
	itemMetrics: {
		paddingBottom: 0,
		paddingTop: 0,
		spacing: 0,
	},
	layout: {
		gap: bridgeCodeViewOptions.layout?.gap ?? 1,
		paddingTop: bridgeCodeViewOptions.layout?.paddingTop ?? 0,
		paddingBottom: 0,
	},
	stickyHeaders: false,
	unsafeCSS: `
		${bridgeCodeViewOptions.unsafeCSS ?? ''}

		[data-file] [data-code] {
			padding-bottom: 0;
			padding-top: 0;
		}
	`,
};

export type { BridgeFileViewerCodePanelContent, BridgeFileViewerCodePanelState };

export interface BridgeFileViewerCodePanelProps {
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly renderedFileContent: BridgeFileViewerCodePanelContent | null;
	readonly totalHeightPixels: number | null;
	readonly staleNotice?: ReactElement | null;
}

export function BridgeFileViewerCodePanel(props: BridgeFileViewerCodePanelProps): ReactElement {
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const lastScrollTopRef = useRef(0);
	const previousOpenStateRef = useRef<{
		readonly path: string | null;
		readonly status: BridgeFileViewerCodePanelState['status'];
	}>({ path: null, status: 'idle' });
	const previousRenderedPathRef = useRef<string | null>(null);
	const codeViewItems = useMemo(
		() =>
			bridgeFileViewerCodeViewItemsForPanelState({
				openFileState: props.openFileState,
				renderedFileContent: props.renderedFileContent,
			}),
		[props.openFileState, props.renderedFileContent],
	);
	const shouldRenderContentState =
		props.renderedFileContent === null && props.openFileState.status !== 'loading';
	useLayoutEffect((): void => {
		const currentPath = props.openFileState.status === 'idle' ? null : props.openFileState.path;
		const currentRenderedPath = props.renderedFileContent?.path ?? null;
		const currentStatus = props.openFileState.status;
		const previousOpenState = previousOpenStateRef.current;
		const shouldRestoreSameFileScroll =
			currentPath !== null &&
			currentPath === previousOpenState.path &&
			currentStatus === 'ready' &&
			(previousOpenState.status === 'loading' || previousOpenState.status === 'refreshing');
		if (
			currentRenderedPath !== null &&
			currentRenderedPath !== previousRenderedPathRef.current &&
			!shouldRestoreSameFileScroll
		) {
			previousRenderedPathRef.current = currentRenderedPath;
			lastScrollTopRef.current = 0;
			requestAnimationFrame((): void => {
				codeViewHandleRef.current?.scrollTo({
					type: 'position',
					position: 0,
					behavior: 'instant',
				});
			});
		}
		if (shouldRestoreSameFileScroll) {
			if (currentRenderedPath !== null) {
				previousRenderedPathRef.current = currentRenderedPath;
			}
			const scrollTop = lastScrollTopRef.current;
			requestAnimationFrame((): void => {
				if (scrollTop > 0) {
					codeViewHandleRef.current?.scrollTo({
						type: 'position',
						position: scrollTop,
						behavior: 'instant',
					});
				}
			});
		}
		previousOpenStateRef.current = { path: currentPath, status: currentStatus };
	}, [props.openFileState, props.renderedFileContent?.path]);
	return (
		<section
			aria-label="Selected file"
			className="relative min-h-0 min-w-0 overflow-hidden bg-[var(--bridge-canvas-bg)]"
			data-bridge-code-view-overflow={bridgeFileViewerCodeViewOptions.overflow}
			data-pierre-code-view-owner="CodeView.file"
			data-shiki-rendering="pierre"
			data-testid="bridge-file-viewer-code-canvas"
			data-worktree-open-file-body-preview={props.renderedFileContent?.body.slice(0, 160)}
			data-worktree-rendered-file-path={props.renderedFileContent?.path}
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
		>
			<BridgePierreWorkerPoolProvider
				{...(props.codeViewWorkerPoolEnabled === undefined
					? {}
					: { enabled: props.codeViewWorkerPoolEnabled })}
				{...(props.codeViewWorkerFactory === undefined
					? {}
					: { workerFactory: props.codeViewWorkerFactory })}
			>
				<div className="h-full min-h-0 min-w-0" data-testid="bridge-file-viewer-code-view">
					<CodeView
						className="bridge-code-view-scroll-owner bridge-scrollbar cv-scrollbar relative h-full min-h-0 min-w-0 flex-1 overflow-y-auto overflow-x-hidden overscroll-contain [overflow-anchor:none] [will-change:scroll-position] [&_diffs-container]:overflow-clip [&_diffs-container]:[contain:layout_paint_style]"
						items={codeViewItems}
						onScroll={(scrollTop): void => {
							lastScrollTopRef.current = scrollTop;
						}}
						options={bridgeFileViewerCodeViewOptions}
						ref={codeViewHandleRef}
						style={{ height: '100%' }}
					/>
				</div>
				{shouldRenderContentState ? (
					<div className="pointer-events-none absolute inset-0">
						<BridgeFileViewerContentState state={props.openFileState} />
					</div>
				) : null}
			</BridgePierreWorkerPoolProvider>
			{props.staleNotice ?? null}
		</section>
	);
}

function BridgeFileViewerContentState(props: {
	readonly state: BridgeFileViewerCodePanelState;
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
		>
			<div className="sticky top-0 flex min-h-screen items-center justify-center">{label}</div>
		</div>
	);
}
