import type { CodeViewItem, CodeViewOptions } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import { useLayoutEffect, useMemo, useRef, type ReactElement } from 'react';

import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { bridgeCodeViewOptions } from '../review-viewer/code-view/bridge-code-view-panel.js';
import { BridgePierreWorkerPoolProvider } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';

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

export type BridgeFileViewerCodePanelState =
	| { readonly status: 'idle' }
	| {
			readonly descriptor: WorktreeFileDescriptor;
			readonly path: string;
			readonly status: 'failed' | 'loading' | 'ready' | 'refreshing' | 'stale' | 'unavailable';
	  };

export interface BridgeFileViewerCodePanelContent {
	readonly body: string;
	readonly bodyVersion: number;
	readonly descriptor: WorktreeFileDescriptor;
	readonly path: string;
}

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
		(): readonly CodeViewItem[] =>
			codeViewItemsForPanelState({
				openFileState: props.openFileState,
				renderedFileContent: props.renderedFileContent,
			}),
		[props.openFileState, props.renderedFileContent],
	);
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
				{props.renderedFileContent === null ? (
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

function codeViewItemsForPanelState(props: {
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly renderedFileContent: BridgeFileViewerCodePanelContent | null;
}): readonly CodeViewItem[] {
	if (props.renderedFileContent === null) {
		return codeViewPlaceholderItemsForOpenFileState(props.openFileState);
	}
	const content = props.renderedFileContent;
	const descriptor = content.descriptor;
	const reservedContent = contentBodyReservedForSelectedFileExtent({
		content,
		openFileState: props.openFileState,
	});
	return [
		{
			id: `file:${descriptor.fileId}`,
			type: 'file',
			file: {
				name: content.path,
				contents: reservedContent.body,
				cacheKey:
					reservedContent.cacheKeySegment === null
						? `${descriptor.contentHandle}:${descriptor.contentHash ?? 'unknown'}`
						: `${descriptor.contentHandle}:${descriptor.contentHash ?? 'unknown'}:${reservedContent.cacheKeySegment}`,
				...(reservedContent.cacheKeySegment === null ? {} : { lang: 'text' }),
			},
			version: content.bodyVersion + reservedContent.versionOffset,
		},
	];
}

function codeViewPlaceholderItemsForOpenFileState(
	openFileState: BridgeFileViewerCodePanelState,
): readonly CodeViewItem[] {
	if (
		openFileState.status === 'idle' ||
		openFileState.descriptor.isBinary ||
		openFileState.descriptor.virtualizedExtentKind !== 'exactLineCount' ||
		openFileState.descriptor.lineCount === undefined ||
		openFileState.descriptor.lineCount <= 0
	) {
		return [];
	}
	return [
		{
			id: `file-placeholder:${openFileState.descriptor.fileId}`,
			type: 'file',
			file: {
				name: openFileState.path,
				contents: Array.from(
					{ length: openFileState.descriptor.lineCount },
					(): string => ' ',
				).join('\n'),
				cacheKey: `${openFileState.descriptor.contentHandle}:placeholder:${openFileState.descriptor.lineCount}`,
				lang: 'text',
			},
			version: openFileState.descriptor.lineCount,
		},
	];
}

function contentBodyReservedForSelectedFileExtent(props: {
	readonly content: BridgeFileViewerCodePanelContent;
	readonly openFileState: BridgeFileViewerCodePanelState;
}): {
	readonly body: string;
	readonly cacheKeySegment: string | null;
	readonly versionOffset: number;
} {
	if (
		props.openFileState.status === 'idle' ||
		props.openFileState.path === props.content.path ||
		props.openFileState.descriptor.isBinary ||
		props.openFileState.descriptor.virtualizedExtentKind !== 'exactLineCount' ||
		props.openFileState.descriptor.lineCount === undefined
	) {
		return {
			body: props.content.body,
			cacheKeySegment: null,
			versionOffset: 0,
		};
	}
	const minimumLineCount = props.openFileState.descriptor.lineCount;
	const body = textPaddedToMinimumRenderedLineCount({
		minimumLineCount,
		text: props.content.body,
	});
	return {
		body,
		cacheKeySegment: `reserved:${props.openFileState.path}:${minimumLineCount}`,
		versionOffset: minimumLineCount,
	};
}

function textPaddedToMinimumRenderedLineCount(props: {
	readonly minimumLineCount: number;
	readonly text: string;
}): string {
	if (props.minimumLineCount <= 0) {
		return props.text;
	}
	const currentLineCount = renderedLineCountForPierreFileContent(props.text);
	const missingLineCount = Math.max(props.minimumLineCount - currentLineCount, 0);
	if (missingLineCount === 0) {
		return props.text;
	}
	return `${props.text}${'\n'.repeat(missingLineCount)} `;
}

function renderedLineCountForPierreFileContent(text: string): number {
	if (text.length === 0) {
		return 0;
	}
	return (text.match(/\n/gu)?.length ?? 0) + 1;
}
