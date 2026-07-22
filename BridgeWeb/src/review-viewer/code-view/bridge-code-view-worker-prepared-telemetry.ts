import type { CodeViewItem } from '@pierre/diffs';

import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import type { BridgeReviewProjectionResult } from '../models/review-projection-models.js';
import type { ApplyBridgeCodeViewItemUpdateResult } from './bridge-code-view-controller.js';
import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';
import {
	recordBridgeSelectedContentPaintedProbeAnchoredDelivery,
	scheduleSelectedContentPaintedTelemetry,
	shouldScheduleSelectedContentPaintedTelemetry,
} from './bridge-code-view-painted-telemetry.js';
import {
	isBridgeCodeViewItem,
	isMaterializedBridgeCodeViewContentState,
	recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanel,
} from './bridge-code-view-panel-support.js';
import type { SelectedContentPaintTelemetryStart } from './bridge-code-view-panel-types.js';

export interface BridgeCodeViewWorkerPreparedTelemetryContext {
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly projection: BridgeReviewProjectionResult;
	readonly reviewPackage: BridgeReviewPackage;
	readonly selectedContentPaintTelemetryStart: SelectedContentPaintTelemetryStart | null;
	readonly selectedItemId: string | null;
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
}

interface RecordBridgeCodeViewWorkerPreparedApplyTelemetryProps extends BridgeCodeViewWorkerPreparedTelemetryContext {
	readonly codeViewItem: BridgeCodeViewItem;
	readonly didFindMatchingPaintedContent: boolean;
	readonly materializationCompletedAtMilliseconds: number;
	readonly materializationStartedAtMilliseconds: number;
	readonly updateResult: ApplyBridgeCodeViewItemUpdateResult;
}

export function recordBridgeCodeViewWorkerPreparedApplyTelemetry(
	props: RecordBridgeCodeViewWorkerPreparedApplyTelemetryProps,
): void {
	if (
		props.telemetryRecorder === undefined ||
		!isMaterializedBridgeCodeViewContentState(props.codeViewItem.bridgeMetadata.contentState)
	) {
		return;
	}
	const reviewItem = props.reviewPackage.itemsById[props.codeViewItem.bridgeMetadata.itemId];
	if (reviewItem === undefined) {
		return;
	}
	recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanel({
		codeViewItem: props.codeViewItem,
		durationMilliseconds:
			props.materializationCompletedAtMilliseconds - props.materializationStartedAtMilliseconds,
		item: reviewItem,
		parentTraceContext: props.parentTraceContext,
		projection: props.projection,
		result: props.updateResult,
		selectedItemId: props.selectedItemId,
		telemetryRecorder: props.telemetryRecorder,
	});
	const isSelectedItem = props.selectedItemId === props.codeViewItem.bridgeMetadata.itemId;
	if (!isSelectedItem) {
		return;
	}
	const paintTelemetryStart = props.selectedContentPaintTelemetryStart;
	const hasPaintTelemetryAnchor = paintTelemetryStart?.itemId === props.codeViewItem.id;
	const selectionDemandStartedAtMilliseconds = hasPaintTelemetryAnchor
		? paintTelemetryStart.startedAtMilliseconds
		: null;
	recordBridgeSelectedContentPaintedProbeAnchoredDelivery({
		didFindMatchingPaintedContent: props.didFindMatchingPaintedContent,
		hasAnchor: hasPaintTelemetryAnchor,
		hasTelemetryRecorder: true,
		isSelectedItem,
	});
	if (
		!shouldScheduleSelectedContentPaintedTelemetry({
			didFindMatchingPaintedContent: props.didFindMatchingPaintedContent,
			selectionDemandStartedAtMilliseconds,
			updateResult: props.updateResult,
		})
	) {
		return;
	}
	scheduleSelectedContentPaintedTelemetry({
		materializationCompletedAtMilliseconds: props.materializationCompletedAtMilliseconds,
		materializationStartedAtMilliseconds: props.materializationStartedAtMilliseconds,
		selectionDemandStartedAtMilliseconds,
		telemetryRecorder: props.telemetryRecorder,
		traceContext: hasPaintTelemetryAnchor ? paintTelemetryStart.actionTraceContext : null,
		transport: 'worker',
	});
}

export function applyResultForSetItemsItem(props: {
	readonly currentItem: CodeViewItem | undefined;
	readonly nextItem: BridgeCodeViewItem;
}): ApplyBridgeCodeViewItemUpdateResult {
	if (!isBridgeCodeViewItem(props.currentItem)) {
		return 'added';
	}
	return props.currentItem.type === props.nextItem.type &&
		props.currentItem.version === props.nextItem.version
		? 'unchanged'
		: 'updated';
}
