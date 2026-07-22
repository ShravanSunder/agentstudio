import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeTreeScrollFrameGapTelemetrySample } from '../../foundation/telemetry/bridge-viewer-telemetry-adapter.js';

export interface BridgeReviewTreeVisibleItemPublisher {
	readonly cancel: () => void;
	readonly publishNow: () => void;
	readonly schedule: () => void;
}

export interface CreateBridgeReviewTreeVisibleItemPublisherProps {
	readonly cancelAnimationFrame?: (frameId: number) => void;
	readonly captureVisibleItemIds: () => readonly string[];
	readonly onVisibleItemIdsChange: (itemIds: readonly string[]) => void;
	readonly requestAnimationFrame?: (callback: () => void) => number;
	readonly telemetryRecorder?: BridgeTelemetryRecorder | undefined;
	readonly telemetryTraceContext?: BridgeTraceContext | null | undefined;
	readonly viewer?: 'review';
}

export function createBridgeReviewTreeVisibleItemPublisher(
	props: CreateBridgeReviewTreeVisibleItemPublisherProps,
): BridgeReviewTreeVisibleItemPublisher {
	const requestFrame = props.requestAnimationFrame ?? requestAnimationFrame;
	const cancelFrame =
		props.cancelAnimationFrame ??
		(typeof cancelAnimationFrame === 'function' ? cancelAnimationFrame : undefined);
	let animationFrameId: number | null = null;
	let burstStartedAt: number | null = null;
	let lastFrameMark: number | null = null;
	let scheduledPublisherSkippedCount = 0;
	const frameGaps: number[] = [];
	const publishNow = (): void => {
		props.onVisibleItemIdsChange(props.captureVisibleItemIds());
	};
	const publishScheduledSettle = (): void => {
		const settledAt = performance.now();
		if (lastFrameMark !== null) {
			frameGaps.push(Math.max(0, settledAt - lastFrameMark));
		}
		const itemIds = props.captureVisibleItemIds();
		props.onVisibleItemIdsChange(itemIds);
		if (props.telemetryRecorder !== undefined) {
			recordBridgeTreeScrollFrameGapTelemetrySample({
				durationMilliseconds: Math.max(0, settledAt - (burstStartedAt ?? settledAt)),
				frameGapMaxMilliseconds: maxFrameGap(frameGaps),
				frameGapP95Milliseconds: percentileFrameGap(frameGaps, 0.95),
				framesOver16Milliseconds: frameGaps.filter((gap): boolean => gap > 16).length,
				framesOver33Milliseconds: frameGaps.filter((gap): boolean => gap > 33).length,
				framesOver50Milliseconds: frameGaps.filter((gap): boolean => gap > 50).length,
				scheduledPublisherSkippedCount,
				telemetryRecorder: props.telemetryRecorder,
				traceContext: props.telemetryTraceContext ?? null,
				viewer: props.viewer ?? 'review',
				visibleRowCount: itemIds.length,
			});
		}
		burstStartedAt = null;
		lastFrameMark = null;
		scheduledPublisherSkippedCount = 0;
		frameGaps.length = 0;
	};
	return {
		cancel: (): void => {
			if (animationFrameId === null) {
				return;
			}
			cancelFrame?.(animationFrameId);
			animationFrameId = null;
			burstStartedAt = null;
			lastFrameMark = null;
			scheduledPublisherSkippedCount = 0;
			frameGaps.length = 0;
		},
		publishNow,
		schedule: (): void => {
			const scheduledAt = performance.now();
			if (burstStartedAt === null) {
				burstStartedAt = scheduledAt;
			}
			if (lastFrameMark !== null) {
				frameGaps.push(Math.max(0, scheduledAt - lastFrameMark));
			}
			lastFrameMark = scheduledAt;
			if (animationFrameId !== null) {
				scheduledPublisherSkippedCount += 1;
				return;
			}
			animationFrameId = requestFrame((): void => {
				animationFrameId = null;
				publishScheduledSettle();
			});
		},
	};
}

function maxFrameGap(frameGaps: readonly number[]): number {
	return frameGaps.length === 0 ? 0 : Math.max(...frameGaps);
}

function percentileFrameGap(frameGaps: readonly number[], percentile: number): number {
	if (frameGaps.length === 0) {
		return 0;
	}
	const sortedGaps = [...frameGaps].toSorted((firstGap, secondGap): number => firstGap - secondGap);
	const index = Math.min(
		sortedGaps.length - 1,
		Math.max(0, Math.ceil(sortedGaps.length * percentile) - 1),
	);
	return sortedGaps[index] ?? 0;
}
