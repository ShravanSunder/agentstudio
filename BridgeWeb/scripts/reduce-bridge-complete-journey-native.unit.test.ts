import { describe, expect, test } from 'vitest';

import { reduceBridgeCompleteJourneyNativeInput } from './reduce-bridge-complete-journey-native.ts';

describe('native Bridge complete journey reduction', () => {
	test('parses three raw launch receipts and reduces four native cohorts', () => {
		const result = reduceBridgeCompleteJourneyNativeInput(makeInput());
		const reductions = result.reductions ?? [];

		expect(result.diagnosticOnly).toBe(false);
		expect(reductions).toHaveLength(4);
		expect(reductions.every((reduction) => reduction.carrier === 'native')).toBe(true);
		expect(reductions.every((reduction) => reduction.satisfied)).toBe(true);
		expect(result.cohorts.every((cohort) => cohort.launches.length === 3)).toBe(true);
		expect(result.cohorts[0]?.launches[0]?.evidence.telemetry).toMatchObject({
			kind: 'native-pane-reports',
			observedPaneReportCount: 400,
			proofEligiblePaneReportCount: 400,
		});
	});

	test('preserves a sub-acceptance diagnostic without weakening the 100-attempt gate', () => {
		const result = reduceBridgeCompleteJourneyNativeInput(makeInput(1));

		expect(result.diagnosticOnly).toBe(true);
		expect(result.reductions).toBeNull();
		expect(
			result.cohorts.every((cohort) =>
				cohort.launches.every((launch) => launch.attempts.length === 1),
			),
		).toBe(true);
	});

	test('rejects malformed receipts instead of coercing untrusted values', () => {
		const input = makeInput();
		const firstLaunch = input.launches[0];
		if (firstLaunch === undefined) throw new Error('Expected the first native launch.');
		const telemetryProof = firstLaunch.receipt.telemetryProof as Record<string, unknown>;
		telemetryProof['observedPaneReportCount'] = '400';

		expect(() => reduceBridgeCompleteJourneyNativeInput(input)).toThrow();
	});

	test('retains native telemetry failure evidence and reports an unsatisfied cohort', () => {
		const input = makeInput();
		const firstLaunch = input.launches[0];
		if (firstLaunch === undefined) throw new Error('Expected the first native launch.');
		firstLaunch.receipt.telemetryProof.lossyPaneReportCount = 1;

		const result = reduceBridgeCompleteJourneyNativeInput(input);
		const reductions = result.reductions ?? [];

		expect(reductions.every((reduction) => reduction.satisfied)).toBe(false);
	});
});

function makeInput(attemptCount = 100): {
	launches: Array<{
		launchId: string;
		receipt: ReturnType<typeof makeReceipt>;
		telemetryMarker: string;
		telemetryServiceVersion: string;
	}>;
	sourceHead: string;
	worktreeHash: string;
} {
	return {
		launches: Array.from({ length: 3 }, (_unused, launchIndex) => {
			const launchId = `native-launch-${launchIndex + 1}`;
			return {
				launchId,
				receipt: makeReceipt(launchId, attemptCount),
				telemetryMarker: `marker-${launchIndex + 1}`,
				telemetryServiceVersion: '0.1.0',
			};
		}),
		sourceHead: 'a'.repeat(40),
		worktreeHash: 'b'.repeat(64),
	};
}

interface TestAttempt {
	readonly attemptId: string;
	readonly durationMilliseconds: number;
	readonly outcome: 'succeeded';
	readonly phaseCompletionElapsedMilliseconds: {
		readonly commitPaint: number;
		readonly handshakeWorker: number;
		readonly pageApplication: number;
		readonly selectionContent: number;
		readonly sourceMetadata: number;
	};
}

interface TestReceipt {
	readonly attemptsByJourney: Readonly<Record<string, TestAttempt[]>>;
	readonly launchId: string;
	readonly telemetryProof: {
		drainFailureCount: number;
		expectedAttemptCount: number;
		lossyPaneReportCount: number;
		missingPaneReportCount: number;
		nativeBatchSequenceGapCount: number;
		observedPaneReportCount: number;
		optionalLossCount: number;
		proofEligiblePaneReportCount: number;
		requiredLossCount: number;
		workerSequenceGapCount: number;
	};
}

function makeReceipt(launchId: string, attemptCount: number): TestReceipt {
	return {
		attemptsByJourney: {
			fileToReview: makeAttempts(launchId, 'fileToReview', attemptCount),
			firstFile: makeAttempts(launchId, 'firstFile', attemptCount),
			firstReview: makeAttempts(launchId, 'firstReview', attemptCount),
			reviewToFile: makeAttempts(launchId, 'reviewToFile', attemptCount),
		},
		launchId,
		telemetryProof: {
			drainFailureCount: 0,
			expectedAttemptCount: attemptCount * 4,
			lossyPaneReportCount: 0,
			missingPaneReportCount: 0,
			nativeBatchSequenceGapCount: 0,
			observedPaneReportCount: attemptCount * 4,
			optionalLossCount: 0,
			proofEligiblePaneReportCount: attemptCount * 4,
			requiredLossCount: 0,
			workerSequenceGapCount: 0,
		},
	};
}

function makeAttempts(launchId: string, journey: string, attemptCount: number): TestAttempt[] {
	return Array.from({ length: attemptCount }, (_unused, attemptIndex) => ({
		attemptId: `${launchId}-${journey}-${attemptIndex}`,
		durationMilliseconds: 500,
		outcome: 'succeeded' as const,
		phaseCompletionElapsedMilliseconds: {
			commitPaint: 500,
			handshakeWorker: 200,
			pageApplication: 100,
			selectionContent: 400,
			sourceMetadata: 300,
		},
	}));
}
