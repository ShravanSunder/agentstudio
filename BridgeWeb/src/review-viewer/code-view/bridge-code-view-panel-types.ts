import type { CodeViewScrollBehavior } from '@pierre/diffs';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import type {
	BridgeCodeViewContentResources,
	BridgeCodeViewItemPresentation,
} from './bridge-code-view-materialization.js';

export interface BridgeCodeViewPanelProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly selectedContentLoadingItemId?: string | null;
	readonly selectedContentResources?: BridgeCodeViewContentResources | null;
	readonly selectedItemPresentation?: BridgeCodeViewItemPresentation | null;
	readonly visibleContentResourcesByItemId?: ReadonlyMap<string, BridgeCodeViewContentResources>;
	readonly visibleLoadingItemIds?: ReadonlySet<string>;
	readonly visibleLoadingItemCount?: number;
	readonly visibleReadyItemCount?: number;
	readonly workerPoolEnabled?: boolean;
	readonly workerFactory?: () => Worker;
	readonly telemetryRecorder?: BridgeTelemetryRecorder;
	readonly telemetryParentTraceContext?: BridgeTraceContext | null;
	readonly onControlHandleChange?: (handle: BridgeCodeViewControlHandle | null) => void;
	readonly onScrollActivityChange?: (isActive: boolean) => void;
	readonly onVisibleItemIdsChange?: (itemIds: readonly string[]) => void;
}

export interface BridgeCodeViewControlHandle {
	readonly scrollToItem: (itemId: string, options?: BridgeCodeViewScrollToItemOptions) => boolean;
	readonly setItemCollapsed: (itemId: string, collapsed: boolean) => boolean;
}

export interface BridgeCodeViewScrollToItemOptions {
	readonly behavior?: CodeViewScrollBehavior;
	readonly expandIfCollapsed?: boolean;
}

export interface BridgeCodeViewSelectionScrollDiagnostic {
	readonly didScroll: boolean;
	readonly itemId: string;
	readonly itemTop: number | 'missing';
	readonly reason: string;
	readonly remainingFrameBudget: number;
}

export const codeViewMaterializationRetryFrameBudget = 30;
export const codeViewSelectedHeaderPinFrameBudget = 30;
export const codeViewSelectionScrollRetryFrameBudget = 30;
export const codeViewVisibleMetadataScrollThrottleMilliseconds = 120;
export const codeViewVisibleHydrationScrollIdleMilliseconds = 120;

export const initialSelectionScrollDiagnostic: BridgeCodeViewSelectionScrollDiagnostic = {
	didScroll: false,
	itemId: 'none',
	itemTop: 'missing',
	reason: 'not-run',
	remainingFrameBudget: 0,
};
