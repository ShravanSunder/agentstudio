import type { CodeViewItem } from '@pierre/diffs';
import { CodeView, type CodeViewHandle } from '@pierre/diffs/react';
import type { ReactElement, ReactNode } from 'react';

import { cn } from '../../app/class-name.js';
import { BridgePierreWorkerPoolProvider } from '../workers/pierre/bridge-pierre-worker-pool.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import { bridgeCodeViewOptions } from './bridge-code-view-options.js';
import type {
	BridgeCodeViewMaterializationDiagnostic,
	BridgeCodeViewRenderedItemsSource,
} from './bridge-code-view-panel-support.js';
import type { BridgeCodeViewSelectionScrollDiagnostic } from './bridge-code-view-panel-types.js';

interface BridgeCodeViewPanelFrameProps {
	readonly handleCodeViewScroll: (
		scrollTop: number,
		viewer: BridgeCodeViewRenderedItemsSource,
	) => void;
	readonly headerRenderers: {
		readonly renderHeaderMetadata: (item: CodeViewItem) => ReactNode;
		readonly renderHeaderPrefix: (item: CodeViewItem) => ReactNode;
	};
	readonly initialItems: readonly BridgeCodeViewItem[];
	readonly materializationDiagnostic: BridgeCodeViewMaterializationDiagnostic;
	readonly materializationResourceEntryItemIds: string;
	readonly materializationResourceEntryCount: number;
	readonly selectedChangeKind: string;
	readonly selectedContentCacheKeyCount: number;
	readonly selectedContentCacheKeys: string;
	readonly selectedContentCharacterCount: number;
	readonly selectedContentLineCount: number;
	readonly selectedContentRoleCount: number;
	readonly selectedContentRoleNames: string;
	readonly selectedContentState: 'none' | 'pending' | 'ready';
	readonly selectedDisplayPath: string | null;
	readonly selectedInitialItemIndex: number;
	readonly selectedInitialItemIsFirst: boolean;
	readonly selectedItemId: string | null;
	readonly selectedPresentationKind: string;
	readonly selectedPresentationVersion: string | number;
	readonly selectionScrollDiagnostic: BridgeCodeViewSelectionScrollDiagnostic;
	readonly setCodeViewHandle: (handle: CodeViewHandle<undefined> | null) => void;
	readonly sourceKey: string;
	readonly visibleLoadingItemCount: number;
	readonly visibleReadyItemCount: number;
	readonly workerFactory?: () => Worker;
	readonly workerPoolEnabled?: boolean;
}

export function BridgeCodeViewPanelFrame(props: BridgeCodeViewPanelFrameProps): ReactElement {
	return (
		<section
			aria-label="Review content"
			className="bridge-code-view-panel relative h-full min-h-0 bg-[var(--bridge-canvas-bg)]"
			data-code-view-item-count={props.initialItems.length}
			data-code-view-rendered-content-resource-count={props.materializationResourceEntryCount}
			data-code-view-rendered-content-resource-item-ids={props.materializationResourceEntryItemIds}
			data-code-view-visible-loading-item-count={props.visibleLoadingItemCount}
			data-code-view-visible-ready-item-count={props.visibleReadyItemCount}
			data-selected-change-kind={props.selectedChangeKind}
			data-selected-content-cache-key-count={props.selectedContentCacheKeyCount}
			data-selected-content-cache-keys={props.selectedContentCacheKeys}
			data-selected-content-character-count={props.selectedContentCharacterCount}
			data-selected-content-line-count={props.selectedContentLineCount}
			data-selected-content-role-count={props.selectedContentRoleCount}
			data-selected-content-roles={props.selectedContentRoleNames}
			data-selected-content-state={props.selectedContentState}
			data-selected-initial-item-index={props.selectedInitialItemIndex}
			data-selected-initial-item-is-first={props.selectedInitialItemIsFirst}
			data-selected-materialized-addition-line-count={
				props.materializationDiagnostic.additionLineCount
			}
			data-selected-materialized-deletion-line-count={
				props.materializationDiagnostic.deletionLineCount
			}
			data-selected-materialized-duration-ms={props.materializationDiagnostic.durationMilliseconds}
			data-selected-materialized-file-line-count={props.materializationDiagnostic.fileLineCount}
			data-selected-materialized-item-type={props.materializationDiagnostic.itemType}
			data-selected-materialized-item-version={props.materializationDiagnostic.itemVersion}
			data-selected-materialized-model-content-state={
				props.materializationDiagnostic.modelContentState
			}
			data-selected-materialized-model-item-version={
				props.materializationDiagnostic.modelItemVersion
			}
			data-selected-materialized-update-result={props.materializationDiagnostic.updateResult}
			data-selection-scroll-did-scroll={props.selectionScrollDiagnostic.didScroll}
			data-selection-scroll-item-id={props.selectionScrollDiagnostic.itemId}
			data-selection-scroll-item-top={props.selectionScrollDiagnostic.itemTop}
			data-selection-scroll-reason={props.selectionScrollDiagnostic.reason}
			data-selection-scroll-remaining-frame-budget={
				props.selectionScrollDiagnostic.remainingFrameBudget
			}
			data-selected-presentation-kind={props.selectedPresentationKind}
			data-selected-presentation-version={props.selectedPresentationVersion}
			data-selected-display-path={props.selectedDisplayPath ?? undefined}
			data-selected-item-id={props.selectedItemId ?? undefined}
			data-bridge-code-view-overflow={bridgeCodeViewOptions.overflow}
			data-testid="bridge-code-view-panel"
		>
			<BridgePierreWorkerPoolProvider
				{...(props.workerPoolEnabled === undefined ? {} : { enabled: props.workerPoolEnabled })}
				{...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory })}
			>
				<CodeView
					className={cn(
						'bridge-code-view-scroll-owner bridge-scrollbar cv-scrollbar relative h-full min-h-0 w-full min-w-0 max-w-full',
						'flex-1 overflow-y-auto overflow-x-hidden overscroll-contain',
						'[overflow-anchor:none] [will-change:scroll-position]',
						'[&_diffs-container]:overflow-clip [&_diffs-container]:[contain:layout_paint_style]',
						'[&_diffs-container]:shadow-[0_-1px_0_var(--bridge-code-view-file-separator),0_1px_0_var(--bridge-code-view-file-separator)]',
					)}
					initialItems={props.initialItems}
					key={props.sourceKey}
					onScroll={props.handleCodeViewScroll}
					options={bridgeCodeViewOptions}
					ref={props.setCodeViewHandle}
					renderHeaderMetadata={props.headerRenderers.renderHeaderMetadata}
					renderHeaderPrefix={props.headerRenderers.renderHeaderPrefix}
					style={{ height: '100%' }}
				/>
			</BridgePierreWorkerPoolProvider>
		</section>
	);
}
