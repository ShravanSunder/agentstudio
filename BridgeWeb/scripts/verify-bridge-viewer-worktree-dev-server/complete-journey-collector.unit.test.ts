import { describe, expect, test } from 'vitest';

import { bridgeCompleteJourneyFailedAttempt } from './complete-journey-collector.ts';
import {
	bridgeCompleteJourneyActivationSequenceAfter,
	bridgeCompleteJourneyTelemetryWitnessesSatisfied,
} from './complete-journey-telemetry.ts';
import type { WorktreeBridgeTelemetrySampleProof } from './types.ts';

describe('Bridge complete journey telemetry correlation', () => {
	test('preserves completed phases when a later journey phase fails', () => {
		const attempt = bridgeCompleteJourneyFailedAttempt({
			attemptId: 'development-launch-1-firstReview-4',
			durationMilliseconds: 975,
			failureReason: 'review_usable_paint_failed',
			phaseCompletionElapsedMilliseconds: {
				handshakeWorker: 250,
				pageApplication: 120,
				selectionContent: 700,
				sourceMetadata: 520,
			},
		});

		expect(attempt).toEqual({
			attemptId: 'development-launch-1-firstReview-4',
			durationMilliseconds: 975,
			failureReason: 'review_usable_paint_failed',
			outcome: 'failed',
			phaseCompletionElapsedMilliseconds: {
				handshakeWorker: 250,
				pageApplication: 120,
				selectionContent: 700,
				sourceMetadata: 520,
			},
		});
	});

	test('uses the page-scoped tree witness with direct DOM paint proof for first Review', () => {
		const samples = [
			makeTelemetrySample({
				name: 'performance.bridge.viewer.time_to_first_interaction',
				viewer: 'review',
			}),
		];

		expect(
			bridgeCompleteJourneyTelemetryWitnessesSatisfied({
				activationSequence: null,
				samples,
				viewer: 'review',
			}),
		).toBe(true);
	});

	test('accepts a sequenced File tree witness from the exact fresh page attempt', () => {
		const samples = [
			makeTelemetrySample({
				activationSequence: 1,
				name: 'performance.bridge.viewer.time_to_first_interaction',
				viewer: 'file',
			}),
		];

		expect(
			bridgeCompleteJourneyTelemetryWitnessesSatisfied({
				activationSequence: null,
				samples,
				viewer: 'file',
			}),
		).toBe(true);
	});

	test('rejects stale or wrong-viewer witnesses for a Review switch', () => {
		const samples = [
			makeTelemetrySample({
				activationSequence: 8,
				name: 'performance.bridge.viewer.time_to_first_interaction',
				viewer: 'review',
			}),
			makeTelemetrySample({
				activationSequence: 9,
				name: 'performance.bridge.web.selected_content_painted',
				viewer: 'file',
			}),
		];

		expect(
			bridgeCompleteJourneyTelemetryWitnessesSatisfied({
				activationSequence: 9,
				samples,
				viewer: 'review',
			}),
		).toBe(false);
	});

	test('accepts File switch witnesses keyed by activation and demand request sequence', () => {
		const samples = [
			makeTelemetrySample({
				activationSequence: 17,
				name: 'performance.bridge.viewer.time_to_first_interaction',
				viewer: 'file',
			}),
			makeTelemetrySample({
				activationSequence: 17,
				activationSequenceAttribute: 'agentstudio.bridge.demand.request.sequence',
				name: 'performance.bridge.web.file_open_ready',
				viewer: 'file',
			}),
		];

		expect(
			bridgeCompleteJourneyTelemetryWitnessesSatisfied({
				activationSequence: 17,
				samples,
				viewer: 'file',
			}),
		).toBe(true);
	});

	test('selects exactly one new target activation and rejects ambiguous overlap', () => {
		const oneNewActivation = [
			makeTelemetrySample({
				activationSequence: 3,
				name: 'performance.bridge.web.viewer_activation',
				viewer: 'review',
			}),
			makeTelemetrySample({
				activationSequence: 4,
				name: 'performance.bridge.web.viewer_activation',
				viewer: 'file',
			}),
		];
		expect(
			bridgeCompleteJourneyActivationSequenceAfter({
				minimumExclusive: 3,
				samples: oneNewActivation,
				viewer: 'file',
			}),
		).toBe(4);

		const overlappingActivations = [
			...oneNewActivation,
			makeTelemetrySample({
				activationSequence: 5,
				name: 'performance.bridge.web.viewer_activation',
				viewer: 'file',
			}),
		];
		expect(() =>
			bridgeCompleteJourneyActivationSequenceAfter({
				minimumExclusive: 3,
				samples: overlappingActivations,
				viewer: 'file',
			}),
		).toThrow(/exactly one new File activation/u);
	});
});

function makeTelemetrySample(props: {
	readonly activationSequence?: number;
	readonly activationSequenceAttribute?:
		| 'agentstudio.bridge.activation.sequence'
		| 'agentstudio.bridge.demand.request.sequence';
	readonly name: string;
	readonly viewer: 'file' | 'review';
}): WorktreeBridgeTelemetrySampleProof {
	return {
		durationMilliseconds: 1,
		name: props.name,
		numericAttributes:
			props.activationSequence === undefined
				? {}
				: {
						[props.activationSequenceAttribute ?? 'agentstudio.bridge.activation.sequence']:
							props.activationSequence,
					},
		phase: null,
		result: 'success',
		slice: null,
		transport: 'content',
		viewer: props.viewer,
	};
}
