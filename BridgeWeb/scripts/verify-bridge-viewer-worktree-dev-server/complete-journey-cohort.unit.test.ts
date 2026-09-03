import { describe, expect, test } from 'vitest';

import {
	reduceBridgeCompleteJourneyCohort,
	type BridgeCompleteJourneyAttempt,
	type BridgeCompleteJourneyLaunchEvidence,
} from './complete-journey-cohort.ts';

describe('Bridge complete journey cohort', () => {
	test('accepts three launches whose pooled and per-launch p95/p99 satisfy the budgets', () => {
		const reduction = reduceBridgeCompleteJourneyCohort(
			makeCohort((launchIndex, attemptIndex) => 400 + launchIndex * 10 + attemptIndex),
		);

		expect(reduction.satisfied).toBe(true);
		expect(reduction.failureCount).toBe(0);
		expect(reduction.sampleCount).toBe(300);
		expect(reduction.launches).toHaveLength(3);
		expect(reduction.pooled.p95Milliseconds).toBeLessThanOrEqual(600);
		expect(reduction.pooled.p99Milliseconds).toBeLessThanOrEqual(1_000);
	});

	test('rejects a p95 miss even when every attempt completes', () => {
		const reduction = reduceBridgeCompleteJourneyCohort(
			makeCohort((_launchIndex, attemptIndex) => (attemptIndex < 94 ? 500 : 700)),
		);

		expect(reduction.satisfied).toBe(false);
		expect(reduction.pooled.p95Milliseconds).toBe(700);
	});

	test('keeps failed attempts visible and rejects the cohort', () => {
		const cohort = makeCohort(() => 500);
		const firstLaunch = cohort.launches[0];
		if (firstLaunch === undefined) throw new Error('Expected the first launch.');
		firstLaunch.attempts[4] = {
			attemptId: 'launch-0-attempt-4',
			durationMilliseconds: 1_500,
			failureReason: 'usable_paint_timeout',
			outcome: 'failed',
			phaseCompletionElapsedMilliseconds: {
				pageApplication: 300,
			},
		};

		const reduction = reduceBridgeCompleteJourneyCohort(cohort);

		expect(reduction.satisfied).toBe(false);
		expect(reduction.failureCount).toBe(1);
		expect(reduction.sampleCount).toBe(300);
	});

	test('rejects fewer than three launches or fewer than 100 attempts per launch', () => {
		const twoLaunches = makeCohort(() => 500);
		twoLaunches.launches.pop();
		expect(() => reduceBridgeCompleteJourneyCohort(twoLaunches)).toThrow(/exactly 3 launches/u);

		const shortLaunch = makeCohort(() => 500);
		shortLaunch.launches[0]?.attempts.pop();
		expect(() => reduceBridgeCompleteJourneyCohort(shortLaunch)).toThrow(/at least 100 attempts/u);
	});

	test('rejects a successful attempt whose phase completions move backward', () => {
		const cohort = makeCohort(() => 500);
		const firstLaunch = cohort.launches[0];
		const firstAttempt = firstLaunch?.attempts[0];
		if (firstAttempt === undefined || firstAttempt.outcome !== 'succeeded') {
			throw new Error('Expected the first successful attempt.');
		}
		if (firstLaunch === undefined) throw new Error('Expected the first launch.');
		firstLaunch.attempts[0] = {
			...firstAttempt,
			phaseCompletionElapsedMilliseconds: {
				commitPaint: 500,
				handshakeWorker: 200,
				pageApplication: 100,
				selectionContent: 450,
				sourceMetadata: 150,
			},
		};

		expect(() => reduceBridgeCompleteJourneyCohort(cohort)).toThrow(
			/phase completions must be monotonic/u,
		);
	});

	test('rejects a launch whose source, cache, fixture, or telemetry evidence is incomplete', () => {
		const cohort = makeCohort(() => 500);
		Object.assign(cohort.launches[0] ?? {}, {
			evidence: {
				cacheState: 'fresh-empty-vite-cache',
				fixtureIdentity: 'current-worktree',
				sourceHead: 'a'.repeat(40),
				telemetryMarker: '',
				telemetryServiceVersion: 'development',
				telemetry: {
					acceptedSampleCount: 1,
					failedBatchCount: 0,
					kind: 'development-batches',
				},
				worktreeHash: 'worktree-hash',
			},
		});

		expect(() => reduceBridgeCompleteJourneyCohort(cohort)).toThrow(
			/complete journey launch evidence/u,
		);
	});

	test('accepts complete native pane proof and rejects loss without changing durations', () => {
		const cohort = makeCohort(() => 500);
		cohort.carrier = 'native';
		for (const launch of cohort.launches) {
			launch.evidence = makeNativeLaunchEvidence(launch.launchId);
		}
		expect(reduceBridgeCompleteJourneyCohort(cohort).satisfied).toBe(true);

		const firstLaunch = cohort.launches[0];
		if (
			firstLaunch === undefined ||
			firstLaunch.evidence.telemetry.kind !== 'native-pane-reports'
		) {
			throw new Error('Expected native launch evidence.');
		}
		firstLaunch.evidence = makeNativeLaunchEvidence(firstLaunch.launchId, {
			lossyPaneReportCount: 1,
		});
		expect(reduceBridgeCompleteJourneyCohort(cohort).satisfied).toBe(false);
	});

	test('rejects native proof whose observed and missing reports do not cover every attempt', () => {
		const cohort = makeCohort(() => 500);
		cohort.carrier = 'native';
		const firstLaunch = cohort.launches[0];
		if (firstLaunch === undefined) throw new Error('Expected the first launch.');
		firstLaunch.evidence = makeNativeLaunchEvidence('native-launch-0', {
			missingPaneReportCount: 1,
		});

		expect(() => reduceBridgeCompleteJourneyCohort(cohort)).toThrow(
			/complete journey launch evidence/u,
		);
	});
});

function makeNativeLaunchEvidence(
	launchId: string,
	overrides: {
		readonly lossyPaneReportCount?: number;
		readonly missingPaneReportCount?: number;
	} = {},
): BridgeCompleteJourneyLaunchEvidence {
	return {
		cacheState: 'fresh-isolated-app-data' as const,
		fixtureIdentity: 'pinned-real-worktree' as const,
		sourceHead: 'a'.repeat(40),
		telemetryMarker: `marker-${launchId}`,
		telemetryServiceVersion: 'packaged-debug',
		telemetry: {
			drainFailureCount: 0,
			expectedAttemptCount: 100,
			kind: 'native-pane-reports' as const,
			lossyPaneReportCount: overrides.lossyPaneReportCount ?? 0,
			missingPaneReportCount: overrides.missingPaneReportCount ?? 0,
			nativeBatchSequenceGapCount: 0,
			observedPaneReportCount: 100,
			optionalLossCount: 0,
			proofEligiblePaneReportCount: 100,
			requiredLossCount: 0,
			workerSequenceGapCount: 0,
		},
		worktreeHash: 'worktree-hash',
	};
}

function makeCohort(durationForAttempt: (launchIndex: number, attemptIndex: number) => number): {
	carrier: 'development' | 'native';
	journey: 'firstFile';
	launches: Array<{
		attempts: BridgeCompleteJourneyAttempt[];
		evidence:
			| {
					cacheState: 'fresh-empty-vite-cache';
					fixtureIdentity: 'current-worktree';
					sourceHead: string;
					telemetryMarker: string;
					telemetryServiceVersion: string;
					telemetry: {
						acceptedSampleCount: number;
						failedBatchCount: number;
						kind: 'development-batches';
					};
					worktreeHash: string;
			  }
			| ReturnType<typeof makeNativeLaunchEvidence>;
		launchId: string;
	}>;
} {
	return {
		carrier: 'development',
		journey: 'firstFile',
		launches: Array.from({ length: 3 }, (_, launchIndex) => ({
			attempts: Array.from({ length: 100 }, (_unused, attemptIndex) => {
				const durationMilliseconds = durationForAttempt(launchIndex, attemptIndex);
				return {
					attemptId: `launch-${launchIndex}-attempt-${attemptIndex}`,
					durationMilliseconds,
					outcome: 'succeeded',
					phaseCompletionElapsedMilliseconds: {
						commitPaint: durationMilliseconds,
						handshakeWorker: Math.min(durationMilliseconds, 150),
						pageApplication: Math.min(durationMilliseconds, 100),
						selectionContent: Math.min(durationMilliseconds, 350),
						sourceMetadata: Math.min(durationMilliseconds, 250),
					},
				} satisfies BridgeCompleteJourneyAttempt;
			}),
			evidence: {
				cacheState: 'fresh-empty-vite-cache',
				fixtureIdentity: 'current-worktree',
				sourceHead: 'a'.repeat(40),
				telemetryMarker: `marker-${launchIndex}`,
				telemetryServiceVersion: 'development',
				telemetry: {
					acceptedSampleCount: 100,
					failedBatchCount: 0,
					kind: 'development-batches',
				},
				worktreeHash: 'worktree-hash',
			},
			launchId: `launch-${launchIndex}`,
		})),
	};
}
