import type { BridgeTelemetryRecorder } from './bridge-telemetry-recorder.js';
import {
	createBridgeChildTraceContext,
	parseBridgeTraceparent,
	type BridgeTraceContext,
} from './bridge-trace-context.js';
import { recordBridgeViewerFirstInteractionReadyTelemetrySample } from './bridge-viewer-telemetry-adapter.js';

/**
 * Page-lifetime state that anchors the BridgeViewer time-to-first-interaction (TTFI)
 * metric. The native side threads the viewer-open wall-clock epoch and a root
 * traceparent through the handshake telemetry config; the first tree/metadata rows
 * that become painted-and-interactive consume that anchor as the `cold` variant. Any
 * later re-mount (a review<->fileview mode switch in an already-booted pane) reports
 * the `warm` variant, timed from that mount rather than from native pane creation.
 */
interface BridgeViewerNativeOpenAnchor {
	readonly openEpochUnixMillis: number;
	readonly rootTraceContext: BridgeTraceContext | null;
}

let nativeOpenAnchor: BridgeViewerNativeOpenAnchor | null = null;
let hasEmittedColdFirstInteraction = false;

export interface SetBridgeViewerNativeOpenAnchorProps {
	readonly openEpochUnixMillis: number | null | undefined;
	readonly traceparent: string | null | undefined;
}

export function setBridgeViewerNativeOpenAnchor(props: SetBridgeViewerNativeOpenAnchorProps): void {
	if (
		props.openEpochUnixMillis === null ||
		props.openEpochUnixMillis === undefined ||
		!Number.isFinite(props.openEpochUnixMillis)
	) {
		return;
	}
	nativeOpenAnchor = {
		openEpochUnixMillis: props.openEpochUnixMillis,
		rootTraceContext:
			props.traceparent === null || props.traceparent === undefined
				? null
				: parseBridgeTraceparent(props.traceparent),
	};
}

export function resetBridgeViewerFirstInteractionStateForTesting(): void {
	nativeOpenAnchor = null;
	hasEmittedColdFirstInteraction = false;
}

export interface RecordBridgeViewerFirstInteractionReadyProps {
	readonly viewer: 'file' | 'review';
	readonly telemetryRecorder: BridgeTelemetryRecorder | undefined;
	readonly mountStartedAtPerfNow: number;
	readonly visibleItemCount: number;
	readonly fallbackTraceContext: BridgeTraceContext | null;
	readonly now?: () => number;
	readonly perfNow?: () => number;
}

/**
 * Emit one `performance.bridge.viewer.time_to_first_interaction` sample at the moment
 * the first rows are painted and their selection/click handlers are attached. Callers
 * must guard against duplicate calls per mount; this function only owns the
 * once-per-page `cold` classification.
 */
export function recordBridgeViewerFirstInteractionReady(
	props: RecordBridgeViewerFirstInteractionReadyProps,
): void {
	const recorder = props.telemetryRecorder;
	if (recorder === undefined || !recorder.isEnabled('web')) {
		return;
	}
	const now = props.now ?? Date.now;
	const perfNow = props.perfNow ?? ((): number => performance.now());
	const isCold = !hasEmittedColdFirstInteraction && nativeOpenAnchor !== null;
	const variant: 'cold' | 'warm' = isCold ? 'cold' : 'warm';
	const durationMilliseconds =
		isCold && nativeOpenAnchor !== null
			? Math.max(0, now() - nativeOpenAnchor.openEpochUnixMillis)
			: Math.max(0, perfNow() - props.mountStartedAtPerfNow);
	const parentTraceContext = isCold
		? (nativeOpenAnchor?.rootTraceContext ?? null)
		: props.fallbackTraceContext;
	const traceContext =
		parentTraceContext === null ? null : createBridgeChildTraceContext(parentTraceContext);
	if (isCold) {
		hasEmittedColdFirstInteraction = true;
	}
	recordBridgeViewerFirstInteractionReadyTelemetrySample({
		durationMilliseconds,
		telemetryRecorder: recorder,
		traceContext,
		variant,
		viewer: props.viewer,
		visibleItemCount: props.visibleItemCount,
	});
}
