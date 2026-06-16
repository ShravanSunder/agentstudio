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
	recordBridgeProjectionBuildTelemetrySample,
	recordBridgeViewerContentQueueTelemetrySample,
} from '../../foundation/telemetry/bridge-viewer-telemetry-adapter.js';
import type { BridgeCodeViewContentResources } from '../code-view/bridge-code-view-materialization.js';
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

export interface RecordBridgeViewerContentQueueTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly item: BridgeReviewItemDescriptor;
}

export interface RecordBridgeCodeViewHydrationTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly projection: BridgeReviewProjectionResult;
	readonly item: BridgeReviewItemDescriptor;
	readonly resources: BridgeCodeViewContentResources;
	readonly workerPoolEnabled: boolean;
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

export function recordBridgeViewerContentQueueTelemetry(
	props: RecordBridgeViewerContentQueueTelemetryProps,
): void {
	recordBridgeViewerContentQueueTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: childTraceContext(props.parentTraceContext),
		contentRole: preferredContentRole(props.item),
	});
}

export function recordBridgeCodeViewHydrationTelemetry(
	props: RecordBridgeCodeViewHydrationTelemetryProps,
): void {
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
		case 'allFiles':
			return 'all_files';
		case 'changedFiles':
			return 'changed_files';
		case 'currentChangeSet':
			return 'current_change_set';
		case 'custom':
			return 'custom';
		case 'docsAndPlans':
			return 'docs_and_plans';
		case 'guidedReview':
			return 'guided_review';
		case 'source':
			return 'source';
		case 'tests':
			return 'tests';
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

function contentByteCountForResources(resources: BridgeCodeViewContentResources): number {
	return Object.values(resources).reduce((total: number, resource): number => {
		if (resource === undefined) {
			return total;
		}
		return total + resource.text.length;
	}, 0);
}

function assertNever(value: never): never {
	throw new Error(`Unhandled review projection mode: ${JSON.stringify(value)}`);
}
