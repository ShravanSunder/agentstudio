import type {
	BridgeContentRole,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	createBridgeChildTraceContext,
	type BridgeTraceContext,
} from '../../foundation/telemetry/bridge-trace-context.js';
import {
	recordBridgeCodeViewHydrationTelemetrySamples,
	recordBridgeCodeViewItemMaterializeTelemetrySample,
	recordBridgeReviewContentDemandTelemetrySample,
	recordBridgeSelectedContentDroppedTelemetrySample,
	recordBridgeSelectedContentPaintedTelemetrySample,
	recordBridgeViewerContentFetchTelemetrySample,
	recordBridgeProjectionCoordinatorTelemetrySample,
	recordBridgeProjectionBuildTelemetrySample,
	recordBridgeViewerContentQueueTelemetrySample,
} from '../../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { ApplyBridgeCodeViewItemUpdateResult } from '../code-view/bridge-code-view-controller.js';
import type {
	BridgeCodeViewContentFacts,
	BridgeCodeViewItem,
} from '../code-view/bridge-code-view-materialization.js';
import type { ReviewContentDemandTelemetry } from '../content/review-content-demand-types.js';
import type {
	BridgeReviewProjectionMode,
	BridgeReviewProjectionResult,
} from '../models/review-projection-models.js';

export interface RecordBridgeProjectionBuildTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly reviewPackage: BridgeReviewPackage;
	readonly projectionMode: BridgeReviewProjectionMode;
	readonly durationMilliseconds: number | null;
	readonly executionLane: 'sync' | 'worker';
	readonly treePathCount: number;
}

export interface RecordBridgeProjectionCoordinatorTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly phase: 'projection_input_build' | 'projection_store_apply' | 'projection_total';
	readonly durationMilliseconds: number;
	readonly executionLane: 'sync' | 'worker';
	readonly reviewPackage: BridgeReviewPackage;
	readonly result: 'failed' | 'success';
}

export interface RecordBridgeViewerContentQueueTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly item: BridgeReviewItemDescriptor;
	readonly interest: 'selected' | 'visible' | 'nearby' | 'speculative' | 'background';
}

export interface RecordBridgeViewerContentFetchTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly contentRole: BridgeContentRole | 'unknown';
	readonly durationMilliseconds: number;
	readonly interest: 'selected' | 'visible' | 'nearby' | 'speculative' | 'background';
	readonly result: 'success' | 'deferred' | 'failed';
	readonly resultReason: string | null;
}

export interface RecordBridgeCodeViewHydrationTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly projection: BridgeReviewProjectionResult;
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentFacts;
	readonly workerPoolEnabled: boolean;
}

export interface RecordBridgeCodeViewItemMaterializeTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly projection: BridgeReviewProjectionResult;
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentFacts;
	readonly durationMilliseconds: number;
	readonly result: ApplyBridgeCodeViewItemUpdateResult;
	readonly selected: boolean;
}

export interface RecordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly projection: BridgeReviewProjectionResult;
	readonly item: BridgeReviewItemDescriptor;
	readonly codeViewItem: BridgeCodeViewItem;
	readonly durationMilliseconds: number;
	readonly result: ApplyBridgeCodeViewItemUpdateResult;
	readonly selected: boolean;
}

export interface RecordBridgeSelectedContentPaintedTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly clickToPaintMilliseconds: number;
	readonly frameWaitMilliseconds: number;
	readonly materializeMilliseconds: number;
	readonly transport?: 'swift' | 'worker';
}

export interface RecordBridgeSelectedContentDroppedTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly dropReason: string;
}

export interface RecordBridgeReviewContentDemandTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly telemetry: ReviewContentDemandTelemetry;
}

type BridgeTelemetryBucket = 'empty' | 'small' | 'medium' | 'large' | 'huge';

export function recordBridgeProjectionBuildTelemetry(
	props: RecordBridgeProjectionBuildTelemetryProps,
): void {
	const itemCount = props.reviewPackage.orderedItemIds.length;
	recordBridgeProjectionBuildTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: childTraceContext(props.parentTraceContext),
		durationMilliseconds: props.durationMilliseconds,
		executionLane: props.executionLane,
		fixtureClass: fixtureClassForItemCount(itemCount),
		itemCountBucket: countBucket(itemCount),
		projectionKind: projectionKindAttribute(props.projectionMode),
		treePathCountBucket: countBucket(props.treePathCount),
	});
}

export function recordBridgeProjectionCoordinatorTelemetry(
	props: RecordBridgeProjectionCoordinatorTelemetryProps,
): void {
	recordBridgeProjectionCoordinatorTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		phase: props.phase,
		durationMilliseconds: props.durationMilliseconds,
		executionLane: props.executionLane,
		itemCount: props.reviewPackage.orderedItemIds.length,
		result: props.result,
	});
}

export function recordBridgeViewerContentQueueTelemetry(
	props: RecordBridgeViewerContentQueueTelemetryProps,
): void {
	recordBridgeViewerContentQueueTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: childTraceContext(props.parentTraceContext),
		contentRole: preferredContentRole(props.item),
		interest: props.interest,
	});
}

export function recordBridgeViewerContentFetchTelemetry(
	props: RecordBridgeViewerContentFetchTelemetryProps,
): void {
	recordBridgeViewerContentFetchTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		contentRole: props.contentRole,
		durationMilliseconds: props.durationMilliseconds,
		interest: props.interest,
		result: props.result,
		resultReason: props.resultReason,
	});
}

export function recordBridgeCodeViewHydrationTelemetry(
	props: RecordBridgeCodeViewHydrationTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	const contentByteCount = contentByteCountForResources(props.resources);
	recordBridgeCodeViewHydrationTelemetrySamples({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: childTraceContext(props.parentTraceContext),
		contentBytesBucket: byteCountBucket(contentByteCount),
		itemCountBucket: countBucket(props.projection.orderedItemIds.length),
		languageClass: languageClassForItem(props.item),
		workerLane: props.workerPoolEnabled ? 'pierre' : 'none',
	});
}

export function recordBridgeCodeViewItemMaterializeTelemetry(
	props: RecordBridgeCodeViewItemMaterializeTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	recordBridgeCodeViewItemMaterializeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: childTraceContext(props.parentTraceContext),
		contentBytesBucket: byteCountBucket(contentByteCountForResources(props.resources)),
		durationMilliseconds: props.durationMilliseconds,
		itemCountBucket: countBucket(props.projection.orderedItemIds.length),
		languageClass: languageClassForItem(props.item),
		result: props.result,
		selected: props.selected,
		transport: 'swift',
		viewer: 'review',
	});
}

export function recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetry(
	props: RecordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	recordBridgeCodeViewItemMaterializeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: childTraceContext(props.parentTraceContext),
		contentBytesBucket: byteCountBucket(contentByteCountForCodeViewItem(props.codeViewItem)),
		durationMilliseconds: props.durationMilliseconds,
		itemCountBucket: countBucket(props.projection.orderedItemIds.length),
		languageClass: languageClassForItem(props.item),
		result: props.result,
		selected: props.selected,
		transport: 'worker',
		viewer: 'review',
	});
}

export function recordBridgeSelectedContentPaintedTelemetry(
	props: RecordBridgeSelectedContentPaintedTelemetryProps,
): void {
	recordBridgeSelectedContentPaintedTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		clickToPaintMilliseconds: props.clickToPaintMilliseconds,
		frameWaitMilliseconds: props.frameWaitMilliseconds,
		materializeMilliseconds: props.materializeMilliseconds,
		transport: props.transport ?? 'swift',
		viewer: 'review',
	});
}

export function recordBridgeSelectedContentDroppedTelemetry(
	props: RecordBridgeSelectedContentDroppedTelemetryProps,
): void {
	recordBridgeSelectedContentDroppedTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		dropReason: props.dropReason,
		viewer: 'review',
	});
}

export function recordBridgeReviewContentDemandTelemetry(
	props: RecordBridgeReviewContentDemandTelemetryProps,
): void {
	recordBridgeReviewContentDemandTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		activeIntentCount: props.telemetry.activeIntentCount,
		deferredCount: props.telemetry.deferredCount,
		durationMilliseconds: props.telemetry.durationMilliseconds,
		failedCount: props.telemetry.failedCount,
		foregroundIntentCount: props.telemetry.foregroundIntentCount,
		idleIntentCount: props.telemetry.idleIntentCount,
		interest: props.telemetry.interest,
		intentCount: props.telemetry.intentCount,
		loadedCount: props.telemetry.loadedCount,
		nearbyIntentCount: props.telemetry.nearbyIntentCount,
		result: reviewContentDemandResultForTelemetry(props.telemetry),
		resultReason: props.telemetry.resultReason ?? null,
		speculativeIntentCount: props.telemetry.speculativeIntentCount,
		viewer: 'review',
		visibleIntentCount: props.telemetry.visibleIntentCount,
	});
}

function reviewContentDemandResultForTelemetry(
	telemetry: ReviewContentDemandTelemetry,
): 'deferred' | 'failed' | 'success' {
	switch (telemetry.resultStatus) {
		case undefined:
		case 'ready':
			return 'success';
		case 'deferred':
			return 'deferred';
		case 'failed':
			return 'failed';
	}
	return assertNever(telemetry.resultStatus);
}

function childTraceContext(
	parentTraceContext: BridgeTraceContext | null,
): BridgeTraceContext | null {
	return parentTraceContext === null ? null : createBridgeChildTraceContext(parentTraceContext);
}

function fixtureClassForItemCount(itemCount: number): 'smoke' | 'medium' | 'large' | 'huge' {
	if (itemCount <= 50) {
		return 'smoke';
	}
	if (itemCount <= 500) {
		return 'medium';
	}
	if (itemCount <= 5_000) {
		return 'large';
	}
	return 'huge';
}

function countBucket(count: number): BridgeTelemetryBucket {
	if (count <= 0) {
		return 'empty';
	}
	if (count <= 50) {
		return 'small';
	}
	if (count <= 500) {
		return 'medium';
	}
	if (count <= 5_000) {
		return 'large';
	}
	return 'huge';
}

function byteCountBucket(byteCount: number): BridgeTelemetryBucket {
	if (byteCount <= 0) {
		return 'empty';
	}
	if (byteCount <= 32_768) {
		return 'small';
	}
	if (byteCount <= 512_000) {
		return 'medium';
	}
	if (byteCount <= 5_000_000) {
		return 'large';
	}
	return 'huge';
}

function projectionKindAttribute(mode: BridgeReviewProjectionMode): string {
	switch (mode.kind) {
		case 'normalReview':
			return 'normal_review';
		case 'guidedReview':
			return 'guided_review';
		case 'plansAndSpecs':
			return 'plans_and_specs';
	}
	return assertNever(mode);
}

function preferredContentRole(item: BridgeReviewItemDescriptor): BridgeContentRole | 'unknown' {
	return (
		item.contentRoles.head?.role ??
		item.contentRoles.file?.role ??
		item.contentRoles.diff?.role ??
		item.contentRoles.base?.role ??
		'unknown'
	);
}

function languageClassForItem(
	item: BridgeReviewItemDescriptor,
): 'config' | 'markdown' | 'other' | 'swift' | 'text' | 'typescript' {
	const language = item.language?.toLowerCase() ?? item.extension?.toLowerCase() ?? '';
	if (language === 'swift') {
		return 'swift';
	}
	if (
		language === 'typescript' ||
		language === 'tsx' ||
		language === 'javascript' ||
		language === 'jsx'
	) {
		return 'typescript';
	}
	if (language === 'markdown' || language === 'md' || language === 'mdx') {
		return 'markdown';
	}
	if (
		language === 'json' ||
		language === 'jsonc' ||
		language === 'toml' ||
		language === 'yaml' ||
		language === 'yml'
	) {
		return 'config';
	}
	if (language === 'text' || language === 'txt') {
		return 'text';
	}
	return 'other';
}

function contentByteCountForResources(resources: BridgeCodeViewContentFacts): number {
	return Object.values(resources).reduce((total: number, resource): number => {
		if (resource === undefined) {
			return total;
		}
		if (resource.byteLength !== undefined) {
			return total + resource.byteLength;
		}
		return total + resource.sizeBytes;
	}, 0);
}

function contentByteCountForCodeViewItem(item: BridgeCodeViewItem): number {
	if (item.type === 'file') {
		return item.file.contents.length;
	}
	return (
		item.fileDiff.additionLines.reduce((total: number, line): number => total + line.length, 0) +
		item.fileDiff.deletionLines.reduce((total: number, line): number => total + line.length, 0)
	);
}

function assertNever(value: never): never {
	throw new Error(`Unhandled review projection mode: ${JSON.stringify(value)}`);
}
