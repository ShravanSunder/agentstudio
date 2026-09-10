import { describe, expect, test } from 'vitest';

import { makeBridgeContentHandle } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { bridgeCodeViewContentRoleFactsForHandle } from '../code-view/bridge-code-view-materialization.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import {
	recordBridgeCodeViewHydrationTelemetry,
	scheduleBridgeReviewActivationSelectedContentPaint,
} from './bridge-review-viewer-telemetry.js';

describe('Bridge review viewer telemetry', () => {
	test('records a selected-preview paint witness for the exact activation sequence', () => {
		const samples: BridgeTelemetrySample[] = [];
		const requestedFrames: Array<() => void> = [];
		scheduleBridgeReviewActivationSelectedContentPaint({
			activationSequence: 9,
			activationStartedAtPerfNow: 100,
			cancelAnimationFrame: (): void => {},
			now: () => 140,
			requestAnimationFrame: (callback): number => {
				requestedFrames.push(callback);
				return 1;
			},
			telemetryRecorder: capturingTelemetryRecorder(samples),
			traceContext: null,
		});

		requestedFrames[0]?.();

		expect(samples).toEqual([
			expect.objectContaining({
				durationMilliseconds: 40,
				name: 'performance.bridge.web.selected_content_painted',
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.activation.sequence': 9,
				}),
			}),
		]);
	});

	test('cancels a selected-preview paint witness superseded before its frame', () => {
		const samples: BridgeTelemetrySample[] = [];
		const requestedFrames: Array<() => void> = [];
		const cancelledFrameIds: number[] = [];
		const cancel = scheduleBridgeReviewActivationSelectedContentPaint({
			activationSequence: 9,
			activationStartedAtPerfNow: 100,
			cancelAnimationFrame: (frameId): void => {
				cancelledFrameIds.push(frameId);
			},
			now: () => 140,
			requestAnimationFrame: (callback): number => {
				requestedFrames.push(callback);
				return 7;
			},
			telemetryRecorder: capturingTelemetryRecorder(samples),
			traceContext: null,
		});

		cancel();
		requestedFrames[0]?.();

		expect(cancelledFrameIds).toEqual([7]);
		expect(samples).toEqual([]);
	});

	test('accepts body-free content facts when web telemetry is disabled', () => {
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const selectedItem = reviewPackage.itemsById['source-high'];
		if (selectedItem === undefined) {
			throw new Error('expected source-high fixture item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const resource = bridgeCodeViewContentRoleFactsForHandle({
			byteLength: 512_000,
			handle: makeBridgeContentHandle('source-high', 'head'),
		});
		const telemetryRecorder = disabledTelemetryRecorder();

		recordBridgeCodeViewHydrationTelemetry({
			telemetryRecorder,
			parentTraceContext: null,
			projection,
			item: selectedItem,
			resources: { head: resource },
			workerPoolEnabled: true,
		});
	});
});

function disabledTelemetryRecorder(): BridgeTelemetryRecorder {
	return {
		isEnabled: (): boolean => false,
		record: (): void => {},
		measure: <TResult>(props: { readonly operation: () => TResult }): TResult => props.operation(),
		flush: (): boolean => true,
	};
}

function capturingTelemetryRecorder(samples: BridgeTelemetrySample[]): BridgeTelemetryRecorder {
	return {
		isEnabled: (): boolean => true,
		record: (sample): void => {
			samples.push(sample);
		},
		measure: <TResult>(props: { readonly operation: () => TResult }): TResult => props.operation(),
		flush: (): boolean => true,
	};
}
