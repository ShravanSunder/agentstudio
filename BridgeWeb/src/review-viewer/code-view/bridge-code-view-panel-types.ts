import type { CodeViewScrollBehavior } from '@pierre/diffs';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import type { BridgeCodeViewItemPresentation } from './bridge-code-view-materialization.js';
import type { BridgeCodeViewProgrammaticRevealIntent } from './bridge-code-view-programmatic-reveal-gate.js';

export interface BridgeCodeViewPanelProps {
	readonly reviewPackage: BridgeReviewPackage;
	readonly projection: BridgeReviewProjectionResult;
	readonly selectedItemId: string | null;
	readonly selectedCodeViewItem?: BridgeMainCodeViewItem | null;
	readonly selectedContentLoadingItemId?: string | null;
	readonly selectedItemPresentation?: BridgeCodeViewItemPresentation | null;
	readonly visibleCodeViewItems?: readonly BridgeMainCodeViewItem[];
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
	readonly revealIntent?: BridgeCodeViewProgrammaticRevealIntent;
}

export interface BridgeCodeViewSelectionScrollDiagnostic {
	readonly didScroll: boolean;
	readonly itemId: string;
	readonly itemTop: number | 'missing';
	readonly reason: string;
	readonly remainingFrameBudget: number;
}

export const codeViewMaterializationRetryFrameBudget = 30;
export const codeViewSelectionScrollRetryFrameBudget = 30;
export const codeViewVisibleMetadataScrollThrottleMilliseconds = 120;
export const codeViewVisibleHydrationScrollIdleMilliseconds = 120;
export const bridgeCodeViewInstantRevealPolicy = {
	externalScrollAbortThresholdPixels: 240,
	hydrationRearmViewportOffsetTolerancePixels: 4,
	hydrationRearmWindowMilliseconds: 2_000,
	renderedHeaderOffsetTolerancePixels: 1,
	retargetEpsilonPixels: 1,
	stableFrameCount: 2,
	viewportOffsetTolerancePixels: 0,
} as const;

export const initialSelectionScrollDiagnostic: BridgeCodeViewSelectionScrollDiagnostic = {
	didScroll: false,
	itemId: 'none',
	itemTop: 'missing',
	reason: 'not-run',
	remainingFrameBudget: 0,
};
