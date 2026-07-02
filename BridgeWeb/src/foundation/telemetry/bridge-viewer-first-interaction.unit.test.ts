import { beforeEach, describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from './bridge-telemetry-recorder.js';
import {
	recordBridgeViewerFirstInteractionReady,
	resetBridgeViewerFirstInteractionStateForTesting,
	setBridgeViewerNativeOpenAnchor,
} from './bridge-viewer-first-interaction.js';

function makeCapturingRecorder(samples: BridgeTelemetrySample[]): BridgeTelemetryRecorder {
	return {
		isEnabled: (): boolean => true,
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		flush: (): boolean => true,
	};
}

const nativeTraceparent = '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01';

describe('bridge viewer first interaction telemetry', () => {
	beforeEach(() => {
		resetBridgeViewerFirstInteractionStateForTesting();
	});

	test('emits the first interaction as cold with native end-to-end duration and joined trace', () => {
		// Arrange
		const samples: BridgeTelemetrySample[] = [];
		const recorder = makeCapturingRecorder(samples);
		setBridgeViewerNativeOpenAnchor({
			openEpochUnixMillis: 1_000_000,
			traceparent: nativeTraceparent,
		});

		// Act
		recordBridgeViewerFirstInteractionReady({
			viewer: 'file',
			telemetryRecorder: recorder,
			mountStartedAtPerfNow: 40,
			visibleItemCount: 12,
			fallbackTraceContext: null,
			now: (): number => 1_000_287,
			perfNow: (): number => 300,
		});

		// Assert
		expect(samples).toHaveLength(1);
		const sample = samples[0];
		expect(sample?.name).toBe('performance.bridge.viewer.time_to_first_interaction');
		expect(sample?.stringAttributes['agentstudio.bridge.viewer.ttfi_variant']).toBe('cold');
		expect(sample?.stringAttributes['agentstudio.bridge.viewer']).toBe('file');
		expect(sample?.durationMilliseconds).toBe(287);
		expect(sample?.numericAttributes['agentstudio.bridge.visible_item.count']).toBe(12);
		expect(sample?.traceContext?.traceId).toBe('0af7651916cd43dd8448eb211c80319c');
		expect(sample?.traceContext?.parentSpanId).toBe('b7ad6b7169203331');
	});

	test('emits later interactions as warm with browser-local mount duration', () => {
		// Arrange
		const samples: BridgeTelemetrySample[] = [];
		const recorder = makeCapturingRecorder(samples);
		setBridgeViewerNativeOpenAnchor({
			openEpochUnixMillis: 1_000_000,
			traceparent: nativeTraceparent,
		});
		recordBridgeViewerFirstInteractionReady({
			viewer: 'file',
			telemetryRecorder: recorder,
			mountStartedAtPerfNow: 40,
			visibleItemCount: 12,
			fallbackTraceContext: null,
			now: (): number => 1_000_287,
			perfNow: (): number => 300,
		});

		// Act — a review<->fileview switch remounts the tree in the already-booted pane
		recordBridgeViewerFirstInteractionReady({
			viewer: 'review',
			telemetryRecorder: recorder,
			mountStartedAtPerfNow: 5_000,
			visibleItemCount: 8,
			fallbackTraceContext: null,
			now: (): number => 9_999_999,
			perfNow: (): number => 5_140,
		});

		// Assert
		expect(samples).toHaveLength(2);
		const warm = samples[1];
		expect(warm?.stringAttributes['agentstudio.bridge.viewer.ttfi_variant']).toBe('warm');
		expect(warm?.stringAttributes['agentstudio.bridge.viewer']).toBe('review');
		expect(warm?.durationMilliseconds).toBe(140);
	});

	test('falls back to warm when no native open anchor was propagated', () => {
		// Arrange
		const samples: BridgeTelemetrySample[] = [];
		const recorder = makeCapturingRecorder(samples);

		// Act
		recordBridgeViewerFirstInteractionReady({
			viewer: 'file',
			telemetryRecorder: recorder,
			mountStartedAtPerfNow: 10,
			visibleItemCount: 3,
			fallbackTraceContext: null,
			now: (): number => 500,
			perfNow: (): number => 120,
		});

		// Assert
		expect(samples).toHaveLength(1);
		expect(samples[0]?.stringAttributes['agentstudio.bridge.viewer.ttfi_variant']).toBe('warm');
		expect(samples[0]?.durationMilliseconds).toBe(110);
	});

	test('does not emit when the recorder is undefined', () => {
		// Arrange
		const samples: BridgeTelemetrySample[] = [];
		setBridgeViewerNativeOpenAnchor({
			openEpochUnixMillis: 1_000_000,
			traceparent: nativeTraceparent,
		});

		// Act
		recordBridgeViewerFirstInteractionReady({
			viewer: 'file',
			telemetryRecorder: undefined,
			mountStartedAtPerfNow: 0,
			visibleItemCount: 0,
			fallbackTraceContext: null,
			now: (): number => 1_000_100,
			perfNow: (): number => 100,
		});

		// Assert
		expect(samples).toHaveLength(0);
	});
});
