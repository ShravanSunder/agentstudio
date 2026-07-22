import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from '../../foundation/telemetry/bridge-trace-context.js';
import { recordBridgeSelectedContentPaintedTelemetry } from '../telemetry/bridge-review-viewer-telemetry.js';
import {
	bridgeCodeViewApplyResultDidRenderContent,
	type ApplyBridgeCodeViewItemUpdateResult,
} from './bridge-code-view-controller.js';

const selectedContentPaintedGenerationByRecorder = new WeakMap<BridgeTelemetryRecorder, number>();
const selectedContentPaintedDemandByRecorder = new WeakMap<BridgeTelemetryRecorder, number>();

type BridgeSelectedContentPaintedProbeReason =
	| 'already_painted_by_hydration'
	| 'anchored_delivery_entry'
	| 'early_return_duplicate_selection_demand'
	| 'early_return_missing_selection_demand'
	| 'flush_called'
	| 'generation_superseded'
	| 'none'
	| 'raf_fired'
	| 'raf_scheduled'
	| 'sample_recorded'
	| 'schedule_entered';

type BridgeSelectedContentPaintedProbeEarlyReturnReason =
	| 'duplicate_selection_demand'
	| 'missing_selection_demand'
	| 'none';

export interface BridgeSelectedContentPaintedProbe {
	anchoredDeliveryEntryCount: number;
	anchoredDeliveryAnchorPresentCount: number;
	anchoredDeliverySelectedMatchCount: number;
	anchoredDeliveryTelemetryRecorderPresentCount: number;
	alreadyPaintedByHydrationCount: number;
	scheduleEnteredCount: number;
	earlyReturnCount: number;
	rafScheduledCount: number;
	rafFiredCount: number;
	generationSupersededCount: number;
	sampleRecordedCount: number;
	flushCalledCount: number;
	lastAnchoredDeliveryHadAnchor: boolean;
	lastAnchoredDeliverySelectedMatched: boolean;
	lastAnchoredDeliveryHadTelemetryRecorder: boolean;
	lastReason: BridgeSelectedContentPaintedProbeReason;
	lastScheduleEarlyReturnReason: BridgeSelectedContentPaintedProbeEarlyReturnReason;
}

interface RecordBridgeSelectedContentPaintedProbeAnchoredDeliveryProps {
	readonly hasAnchor: boolean;
	readonly isSelectedItem: boolean;
	readonly hasTelemetryRecorder: boolean;
	readonly didFindMatchingPaintedContent: boolean;
}

declare global {
	interface Window {
		__bridgeSelectedContentPaintedProbe?: BridgeSelectedContentPaintedProbe;
	}
}

export function recordBridgeSelectedContentPaintedProbeAnchoredDelivery(
	props: RecordBridgeSelectedContentPaintedProbeAnchoredDeliveryProps,
): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.anchoredDeliveryEntryCount += 1;
	if (props.hasAnchor) {
		probe.anchoredDeliveryAnchorPresentCount += 1;
	}
	if (props.isSelectedItem) {
		probe.anchoredDeliverySelectedMatchCount += 1;
	}
	if (props.hasTelemetryRecorder) {
		probe.anchoredDeliveryTelemetryRecorderPresentCount += 1;
	}
	probe.lastAnchoredDeliveryHadAnchor = props.hasAnchor;
	probe.lastAnchoredDeliverySelectedMatched = props.isSelectedItem;
	probe.lastAnchoredDeliveryHadTelemetryRecorder = props.hasTelemetryRecorder;
	probe.lastReason = 'anchored_delivery_entry';
	if (props.didFindMatchingPaintedContent) {
		recordBridgeSelectedContentPaintedProbeAlreadyPaintedByHydration();
	}
}

export function recordBridgeSelectedContentPaintedProbeAlreadyPaintedByHydration(): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.alreadyPaintedByHydrationCount += 1;
	probe.lastReason = 'already_painted_by_hydration';
}

function recordBridgeSelectedContentPaintedProbeScheduleEntered(): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.scheduleEnteredCount += 1;
	probe.lastReason = 'schedule_entered';
}

function recordBridgeSelectedContentPaintedProbeEarlyReturn(
	reason: BridgeSelectedContentPaintedProbeEarlyReturnReason,
): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.earlyReturnCount += 1;
	probe.lastScheduleEarlyReturnReason = reason;
	probe.lastReason =
		reason === 'duplicate_selection_demand'
			? 'early_return_duplicate_selection_demand'
			: 'early_return_missing_selection_demand';
}

function recordBridgeSelectedContentPaintedProbeRafScheduled(): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.rafScheduledCount += 1;
	probe.lastReason = 'raf_scheduled';
}

function recordBridgeSelectedContentPaintedProbeRafFired(): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.rafFiredCount += 1;
	probe.lastReason = 'raf_fired';
}

function recordBridgeSelectedContentPaintedProbeGenerationSuperseded(): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.generationSupersededCount += 1;
	probe.lastReason = 'generation_superseded';
}

function recordBridgeSelectedContentPaintedProbeSampleRecorded(): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.sampleRecordedCount += 1;
	probe.lastReason = 'sample_recorded';
}

function recordBridgeSelectedContentPaintedProbeFlushCalled(): void {
	const probe = bridgeSelectedContentPaintedProbe();
	if (probe === null) {
		return;
	}
	probe.flushCalledCount += 1;
	probe.lastReason = 'flush_called';
}

function bridgeSelectedContentPaintedProbe(): BridgeSelectedContentPaintedProbe | null {
	const probeWindow = (globalThis as typeof globalThis & { readonly window?: Window }).window;
	if (probeWindow === undefined || typeof probeWindow !== 'object') {
		return null;
	}
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	probeWindow.__bridgeSelectedContentPaintedProbe ??= {
		anchoredDeliveryEntryCount: 0,
		anchoredDeliveryAnchorPresentCount: 0,
		anchoredDeliverySelectedMatchCount: 0,
		anchoredDeliveryTelemetryRecorderPresentCount: 0,
		alreadyPaintedByHydrationCount: 0,
		scheduleEnteredCount: 0,
		earlyReturnCount: 0,
		rafScheduledCount: 0,
		rafFiredCount: 0,
		generationSupersededCount: 0,
		sampleRecordedCount: 0,
		flushCalledCount: 0,
		lastAnchoredDeliveryHadAnchor: false,
		lastAnchoredDeliverySelectedMatched: false,
		lastAnchoredDeliveryHadTelemetryRecorder: false,
		lastReason: 'none',
		lastScheduleEarlyReturnReason: 'none',
	};
	// oxlint-disable-next-line no-underscore-dangle -- Intentional Bridge debug surface name.
	return probeWindow.__bridgeSelectedContentPaintedProbe;
}

export function shouldScheduleSelectedContentPaintedTelemetry(props: {
	readonly didFindMatchingPaintedContent: boolean;
	readonly selectionDemandStartedAtMilliseconds: number | null;
	readonly updateResult: ApplyBridgeCodeViewItemUpdateResult;
}): boolean {
	if (props.selectionDemandStartedAtMilliseconds === null) {
		return false;
	}
	return (
		bridgeCodeViewApplyResultDidRenderContent(props.updateResult) ||
		props.didFindMatchingPaintedContent
	);
}

export function scheduleSelectedContentPaintedTelemetry(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly selectionDemandStartedAtMilliseconds: number | null;
	readonly materializationStartedAtMilliseconds: number;
	readonly materializationCompletedAtMilliseconds: number;
	readonly now?: () => number;
	readonly requestAnimationFrame?: (callback: FrameRequestCallback) => number;
	readonly transport?: 'swift' | 'worker';
}): void {
	recordBridgeSelectedContentPaintedProbeScheduleEntered();
	if (props.selectionDemandStartedAtMilliseconds === null) {
		recordBridgeSelectedContentPaintedProbeEarlyReturn('missing_selection_demand');
		return;
	}
	const selectionDemandStartedAtMilliseconds = props.selectionDemandStartedAtMilliseconds;
	if (
		selectedContentPaintedDemandByRecorder.get(props.telemetryRecorder) ===
		selectionDemandStartedAtMilliseconds
	) {
		recordBridgeSelectedContentPaintedProbeEarlyReturn('duplicate_selection_demand');
		return;
	}
	selectedContentPaintedDemandByRecorder.set(
		props.telemetryRecorder,
		selectionDemandStartedAtMilliseconds,
	);
	const now = props.now ?? performance.now.bind(performance);
	const requestFrame = props.requestAnimationFrame ?? requestAnimationFrame;
	const paintedGeneration =
		(selectedContentPaintedGenerationByRecorder.get(props.telemetryRecorder) ?? 0) + 1;
	selectedContentPaintedGenerationByRecorder.set(props.telemetryRecorder, paintedGeneration);
	recordBridgeSelectedContentPaintedProbeRafScheduled();
	requestFrame((): void => {
		recordBridgeSelectedContentPaintedProbeRafFired();
		if (
			selectedContentPaintedGenerationByRecorder.get(props.telemetryRecorder) !== paintedGeneration
		) {
			recordBridgeSelectedContentPaintedProbeGenerationSuperseded();
			return;
		}
		selectedContentPaintedGenerationByRecorder.delete(props.telemetryRecorder);
		const paintedAtMilliseconds = now();
		recordBridgeSelectedContentPaintedProbeSampleRecorded();
		recordBridgeSelectedContentPaintedTelemetry({
			telemetryRecorder: props.telemetryRecorder,
			traceContext: props.traceContext,
			clickToPaintMilliseconds: paintedAtMilliseconds - selectionDemandStartedAtMilliseconds,
			frameWaitMilliseconds: paintedAtMilliseconds - props.materializationCompletedAtMilliseconds,
			materializeMilliseconds:
				props.materializationCompletedAtMilliseconds - props.materializationStartedAtMilliseconds,
			transport: props.transport ?? 'swift',
		});
		recordBridgeSelectedContentPaintedProbeFlushCalled();
	});
}
