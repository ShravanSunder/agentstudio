import type { CodeViewOptions } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import { useCallback, useLayoutEffect, useMemo, useRef, type ReactElement } from 'react';

import type { BridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
	observeBridgeCodeViewRenderFulfillment,
	reconcileBridgeCodeViewRenderFulfillment,
} from '../review-viewer/code-view/bridge-code-view-render-fulfillment.js';
import { BridgePierreWorkerPoolProvider } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import {
	bridgeFileViewerCodeViewItemsForPanelState,
	type BridgeFileViewerCodePanelState,
	type BridgeFileViewerSelectedCodeViewItem,
} from './bridge-file-viewer-code-view-items.js';
import { bridgeFileViewerCodeViewOptions } from './bridge-file-viewer-code-view-options.js';

export type { BridgeFileViewerCodePanelState, BridgeFileViewerSelectedCodeViewItem };

export interface BridgeFileViewerCodePanelProps {
	readonly codeViewOptions?: Readonly<CodeViewOptions<undefined>>;
	readonly codeViewWorkerFactory?: () => Worker;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly openFileState: BridgeFileViewerCodePanelState;
	readonly renderFulfillmentCoordinator: Pick<
		BridgeMainRenderFulfillmentCoordinator,
		'observePostRender' | 'reconcilePublication'
	>;
	readonly selectedCodeViewItem: BridgeFileViewerSelectedCodeViewItem | null;
	readonly totalHeightPixels: number | null;
	readonly staleNotice?: ReactElement | null;
}

export function BridgeFileViewerCodePanel(props: BridgeFileViewerCodePanelProps): ReactElement {
	const codeViewHandleRef = useRef<CodeViewHandle<undefined> | null>(null);
	const previousRenderedIdentityRef = useRef<{
		readonly fileId: string;
		readonly path: string;
	} | null>(null);
	const scrollEffectVersionRef = useRef(0);
	const codeViewItems = useMemo(
		() =>
			bridgeFileViewerCodeViewItemsForPanelState({
				openFileState: props.openFileState,
				selectedCodeViewItem: props.selectedCodeViewItem,
			}),
		[props.openFileState, props.selectedCodeViewItem],
	);
	const shouldRenderContentState = props.openFileState.status !== 'ready';
	useLayoutEffect((): void => {
		if (props.selectedCodeViewItem === null) return;
		reconcileBridgeCodeViewRenderFulfillment({
			exactPresentationItem: props.selectedCodeViewItem,
			getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
			renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
		});
	});
	const handleCodeViewPostRender = useCallback<
		NonNullable<CodeViewOptions<undefined>['onPostRender']>
	>(
		(node, _instance, phase, context): void => {
			observeBridgeCodeViewRenderFulfillment({
				contextItem: context.item,
				getCodeViewHandle: (): CodeViewHandle<undefined> | null => codeViewHandleRef.current,
				itemId: context.item.id,
				phase,
				renderedElement: node,
				renderFulfillmentCoordinator: props.renderFulfillmentCoordinator,
				selectedCodeViewItem: props.selectedCodeViewItem,
				visibleCodeViewItems: undefined,
			});
		},
		[props.renderFulfillmentCoordinator, props.selectedCodeViewItem],
	);
	const codeViewOptions = useMemo<CodeViewOptions<undefined>>(
		() => ({
			...(props.codeViewOptions ?? bridgeFileViewerCodeViewOptions),
			onPostRender: handleCodeViewPostRender,
		}),
		[handleCodeViewPostRender, props.codeViewOptions],
	);
	useLayoutEffect((): void => {
		const selectedItem = props.selectedCodeViewItem;
		if (selectedItem === null) return;
		const currentIdentity = {
			fileId: selectedItem.bridgeMetadata.itemId,
			path: selectedItem.bridgeMetadata.displayPath,
		};
		const previousIdentity = previousRenderedIdentityRef.current;
		previousRenderedIdentityRef.current = currentIdentity;
		if (
			previousIdentity !== null &&
			previousIdentity.fileId === currentIdentity.fileId &&
			previousIdentity.path === currentIdentity.path
		) {
			return;
		}
		const effectVersion = scrollEffectVersionRef.current + 1;
		scrollEffectVersionRef.current = effectVersion;
		requestAnimationFrame((): void => {
			if (scrollEffectVersionRef.current !== effectVersion) return;
			codeViewHandleRef.current?.scrollTo({
				behavior: 'instant',
				position: 0,
				type: 'position',
			});
		});
	}, [props.selectedCodeViewItem]);
	return (
		<section
			aria-label="Selected file"
			className="relative min-h-0 min-w-0 overflow-hidden bg-[var(--bridge-canvas-bg)]"
			data-bridge-code-view-overflow={codeViewOptions.overflow}
			data-pierre-code-view-owner="CodeView.file"
			data-shiki-rendering="pierre"
			data-testid="bridge-file-viewer-code-canvas"
			data-worktree-open-file-body-preview={props.selectedCodeViewItem?.file.contents.slice(0, 160)}
			data-worktree-rendered-file-path={props.selectedCodeViewItem?.bridgeMetadata.displayPath}
			data-worktree-rendered-content-roles={props.selectedCodeViewItem?.bridgeMetadata.contentRoles.join(
				',',
			)}
			data-worktree-rendered-content-state={props.selectedCodeViewItem?.bridgeMetadata.contentState}
			data-worktree-rendered-item-id={props.selectedCodeViewItem?.bridgeMetadata.itemId}
			data-worktree-rendered-line-count={props.selectedCodeViewItem?.bridgeMetadata.lineCount}
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
				<div
					className={`h-full min-h-0 min-w-0 ${props.openFileState.status === 'ready' ? '' : 'invisible'}`}
					data-testid="bridge-file-viewer-code-view"
				>
					<CodeView
						className="bridge-code-view-scroll-owner bridge-scrollbar cv-scrollbar relative h-full min-h-0 min-w-0 flex-1 overflow-y-auto overflow-x-hidden overscroll-contain [overflow-anchor:none] [will-change:scroll-position] [&_diffs-container]:overflow-clip [&_diffs-container]:[contain:layout_paint_style]"
						items={codeViewItems}
						options={codeViewOptions}
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
			: props.state.status === 'loading' || props.state.status === 'stale'
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
