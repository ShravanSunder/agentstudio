import { describe, expect, test } from 'vitest';

import {
	bridgeLocalFirstProofCells,
	bridgeLocalFirstProofRunIdentityFingerprint,
	bridgeLocalFirstProofRunManifestHash,
	parseBridgeLocalFirstProofCohort as parseBridgeLocalFirstProofCohortWithOracle,
	type BridgeLocalFirstProofAttemptInput,
	type BridgeLocalFirstProofCellContract,
	type BridgeLocalFirstProofCohortInput,
	type BridgeLocalFirstProofRunIdentity,
} from './bridge-local-first-proof-contract.ts';
import { parseBridgeLocalFirstProofFixtureOracle } from './bridge-local-first-proof-evidence.ts';
import {
	makeBridgeLocalFirstTestFixtureOracle,
	makeBridgeLocalFirstTestInteractionEvidence,
	makeBridgeLocalFirstTestProofFixture,
	type BridgeLocalFirstTestDeepMutable,
	type BridgeLocalFirstTestProofFixtureOptions,
} from './bridge-local-first-proof-honesty.unit.test.ts';
import { reduceBridgeLocalFirstProofCohort as reduceBridgeLocalFirstProofCohortWithOracle } from './bridge-local-first-proof-reducer.ts';

const expectedRunFacts = {
	runId: 'run-current-worktree',
	headCommitSha: '0123456789abcdef0123456789abcdef01234567',
	dirtyStateHash: '1'.repeat(64),
	packagedBundleHash: '2'.repeat(64),
	fixtureId: 'bridge-local-first-large-corpus-v1',
	fixtureChecksum: '3'.repeat(64),
	viewport: { width: 1_728, height: 972, deviceScaleFactor: 2 },
	machineProfileHash: '4'.repeat(64),
	pierreVersion: '@pierre/diffs@1.2.10+@pierre/trees@1.0.0-beta.4',
	workerMode: 'pane-comm-worker' as const,
};
const expectedRunManifestHash = bridgeLocalFirstProofRunManifestHash(expectedRunFacts);
const expectedRunIdentity: BridgeLocalFirstProofRunIdentity = {
	...expectedRunFacts,
	runManifestHash: expectedRunManifestHash,
	runIdentityFingerprint: bridgeLocalFirstProofRunIdentityFingerprint({
		...expectedRunFacts,
		runManifestHash: expectedRunManifestHash,
	}),
};
const executableSha256 = 'a'.repeat(64);
const fixtureOracle = parseBridgeLocalFirstProofFixtureOracle({
	expectedFixtureChecksum: expectedRunIdentity.fixtureChecksum,
	expectedFixtureId: expectedRunIdentity.fixtureId,
	rawOracle: makeBridgeLocalFirstTestFixtureOracle(expectedRunIdentity, 101),
});

function parseBridgeLocalFirstProofCohort(
	rawCohort: unknown,
	expectedRunIdentityInput: BridgeLocalFirstProofRunIdentity,
): ReturnType<typeof parseBridgeLocalFirstProofCohortWithOracle> {
	return parseBridgeLocalFirstProofCohortWithOracle(
		rawCohort,
		expectedRunIdentityInput,
		fixtureOracle,
	);
}

function reduceBridgeLocalFirstProofCohort(
	rawCohort: unknown,
	expectedRunIdentityInput: BridgeLocalFirstProofRunIdentity,
): ReturnType<typeof reduceBridgeLocalFirstProofCohortWithOracle> {
	return reduceBridgeLocalFirstProofCohortWithOracle(
		rawCohort,
		expectedRunIdentityInput,
		fixtureOracle,
	);
}

describe('bridge local-first proof contract', () => {
	test('admits a complete fresh cohort and freezes every identity boundary', () => {
		const cohort = parseBridgeLocalFirstProofCohort(makeCompleteCohort(), expectedRunIdentity);
		const firstCell = requiredValue(cohort.cells[0]);
		const firstLaunch = requiredValue(firstCell.launches[0]);
		const firstAttempt = requiredValue(firstLaunch.attempts[0]);

		expect(Object.isFrozen(cohort.runIdentity)).toBe(true);
		expect(Object.isFrozen(firstCell.identity)).toBe(true);
		expect(Object.isFrozen(firstLaunch.identity)).toBe(true);
		expect(Object.isFrozen(firstAttempt.identity)).toBe(true);
	});

	test('retains every failure as its deadline-valued sample', () => {
		const failureKinds = [
			'timeout',
			'stale',
			'wrong',
			'blank',
			'disappeared',
			'missing_endpoint',
		] as const;
		const cohortInput = makeCompleteCohort({
			makeAttempt: ({ attemptIndex, defaultAttempt }) => {
				const failureKind = attemptIndex >= 94 ? failureKinds.at(attemptIndex - 94) : undefined;
				return failureKind === undefined
					? defaultAttempt
					: {
							identity: defaultAttempt.identity,
							outcome: 'failed',
							failureKind,
							deadlineDurationMilliseconds: 1_000,
						};
			},
		});
		const reduction = reduceBridgeLocalFirstProofCohort(cohortInput, expectedRunIdentity);
		const firstLaunch = requiredValue(requiredValue(reduction.cells[0]).launches[0]);

		expect(firstLaunch.sampleCount).toBe(100);
		expect(firstLaunch.failureCount).toBe(6);
		expect(firstLaunch.p95DurationMilliseconds).toBe(1_000);
		expect(firstLaunch.p99DurationMilliseconds).toBe(1_000);
	});

	test('uses nearest-rank launch, pooled, and maximum worst-launch percentiles', () => {
		const reduction = reduceBridgeLocalFirstProofCohort(
			makeCompleteCohort({
				makeAttempt: ({ attemptIndex, defaultAttempt, launchIndex }) => ({
					identity: defaultAttempt.identity,
					outcome: 'succeeded',
					durationMilliseconds: launchIndex * 100 + attemptIndex + 1,
					deadlineDurationMilliseconds: defaultAttempt.deadlineDurationMilliseconds,
				}),
			}),
			expectedRunIdentity,
		);
		const firstCell = requiredValue(reduction.cells[0]);

		expect(firstCell.launches.map((launch) => launch.p95DurationMilliseconds)).toEqual([
			95, 195, 295,
		]);
		expect(firstCell.launches.map((launch) => launch.p99DurationMilliseconds)).toEqual([
			99, 199, 299,
		]);
		expect(firstCell.pooled.p95DurationMilliseconds).toBe(285);
		expect(firstCell.pooled.p99DurationMilliseconds).toBe(297);
		expect(firstCell.worstLaunch.p95DurationMilliseconds).toBe(295);
		expect(firstCell.worstLaunch.p99DurationMilliseconds).toBe(299);
		expect(firstCell.worstLaunch.p95DurationMilliseconds).not.toBe(195);
	});

	test('rejects a launch with only 99 attempted measured actions', () => {
		expect(() =>
			parseBridgeLocalFirstProofCohort(
				makeCompleteCohort({ measuredAttemptCount: 99 }),
				expectedRunIdentity,
			),
		).toThrow(/at least 100 measured attempts/u);
	});

	test('admits more than 100 measured actions without changing the closed launch count', () => {
		expect(() =>
			parseBridgeLocalFirstProofCohort(
				makeCompleteCohort({ measuredAttemptCount: 101 }),
				expectedRunIdentity,
			),
		).not.toThrow();
	});

	test('rejects sibling expected and observed endpoint values without a fixture oracle', () => {
		const cohort = makeCompleteCohort();
		const evidence = requiredValue(
			requiredValue(requiredValue(cohort.cells[0]).launches[0]).interactionEvidence[0],
		);
		if (evidence.external.endpoint.kind !== 'selection_feedback') {
			throw new Error('test fixture expected selection feedback');
		}
		Reflect.set(evidence.external.endpoint, 'expectedSelectionIdentity', 'forged-selection');
		evidence.external.endpoint.observedSelectionIdentity = 'forged-selection';

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/expectedSelectionIdentity|unrecognized/iu,
		);
		const observedOnlyCohort = makeCompleteCohort();
		const observedEvidence = requiredValue(
			requiredValue(requiredValue(observedOnlyCohort.cells[0]).launches[0]).interactionEvidence[0],
		);
		if (observedEvidence.external.endpoint.kind !== 'selection_feedback') {
			throw new Error('test fixture expected selection feedback');
		}
		observedEvidence.external.endpoint.observedSelectionIdentity = 'forged-selection';
		expect(() => parseBridgeLocalFirstProofCohort(observedOnlyCohort, expectedRunIdentity)).toThrow(
			/endpoint oracle derived stale/u,
		);
	});

	test('rejects non-monotonic internal stages and spans outside the interaction', () => {
		const stageCohort = makeCompleteCohort();
		const stageEvidence = firstTelemetryOnInteractionEvidence(stageCohort);
		if (stageEvidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		const firstEvent = requiredValue(stageEvidence.internal.events[0]);
		requiredValue(stageEvidence.internal.events[1]).observedAtMonotonicMilliseconds =
			firstEvent.observedAtMonotonicMilliseconds - 1;
		const spanCohort = makeCompleteCohort();
		const spanEvidence = firstTelemetryOnInteractionEvidence(spanCohort);
		if (spanEvidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		const span = requiredValue(spanEvidence.internal.spans[0]);
		span.startedAtMonotonicMilliseconds = 0;
		span.completedAtMonotonicMilliseconds = 1;

		expect(() => parseBridgeLocalFirstProofCohort(stageCohort, expectedRunIdentity)).toThrow(
			/internal lifecycle timestamps are not monotonic/u,
		);
		expect(() => parseBridgeLocalFirstProofCohort(spanCohort, expectedRunIdentity)).toThrow(
			/internal span is outside interaction/u,
		);
	});

	test('rejects empty event-loop arrays without independent callback and rAF coverage', () => {
		const cohort = makeCompleteCohort();
		const evidence = requiredValue(
			requiredValue(requiredValue(cohort.cells[0]).launches[0]).interactionEvidence[0],
		);
		evidence.external.eventLoop.observerCoverage.callbackTimestamps = [];
		evidence.external.eventLoop.observerCoverage.animationFrameTimestamps = [];

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/event-loop observer coverage/u,
		);
		const endpointBoundCohort = makeCompleteCohort();
		const endpointBoundEvidence = requiredValue(
			requiredValue(requiredValue(endpointBoundCohort.cells[0]).launches[0]).interactionEvidence[0],
		);
		endpointBoundEvidence.external.eventLoop.observerCoverage.animationFrameTimestamps = [
			endpointBoundEvidence.external.runtimeTiming.stimulusAtMonotonicMilliseconds,
			endpointBoundEvidence.external.runtimeTiming.endpointObservedAtMonotonicMilliseconds,
		];
		expect(() =>
			parseBridgeLocalFirstProofCohort(endpointBoundCohort, expectedRunIdentity),
		).toThrow(/does not bound interaction/u);
	});

	test('rejects fewer than three fresh launches', () => {
		expect(() =>
			parseBridgeLocalFirstProofCohort(makeCompleteCohort({ launchCount: 2 }), expectedRunIdentity),
		).toThrow(/exactly 3 fresh launches/u);
	});

	test('rejects an omitted terminal attempt from the attempted-action ledger', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		firstLaunch.attempts.pop();

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/attempt ledger expected 100 terminal attempts, got 99/u,
		);
	});

	test('rejects a nonterminal failure outcome', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		const firstAttempt = requiredValue(firstLaunch.attempts[0]);
		Reflect.set(firstLaunch.attempts, 0, {
			identity: firstAttempt.identity,
			outcome: 'pending',
		});

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow();
	});

	test.each([Number.NaN, Number.POSITIVE_INFINITY, -1])(
		'rejects the invalid success duration %s',
		(invalidDurationMilliseconds) => {
			const cohort = makeCompleteCohort();
			const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
			const firstAttempt = requiredValue(firstLaunch.attempts[0]);
			firstLaunch.attempts[0] = {
				identity: firstAttempt.identity,
				outcome: 'succeeded',
				durationMilliseconds: invalidDurationMilliseconds,
				deadlineDurationMilliseconds: firstAttempt.deadlineDurationMilliseconds,
			};

			expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow();
		},
	);

	test.each([Number.NaN, Number.POSITIVE_INFINITY, -1])(
		'rejects the invalid failure deadline %s',
		(invalidDeadlineDurationMilliseconds) => {
			const cohort = makeCompleteCohort();
			const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
			const firstAttempt = requiredValue(firstLaunch.attempts[0]);
			firstLaunch.attempts[0] = {
				identity: firstAttempt.identity,
				outcome: 'failed',
				failureKind: 'timeout',
				deadlineDurationMilliseconds: invalidDeadlineDurationMilliseconds,
			};

			expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow();
		},
	);

	test.each([0, 999, 1_001])(
		'rejects the non-prescribed failure deadline %s',
		(invalidDeadline) => {
			const cohort = makeCompleteCohort();
			const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
			const firstAttempt = requiredValue(firstLaunch.attempts[0]);
			firstLaunch.attempts[0] = {
				identity: firstAttempt.identity,
				outcome: 'failed',
				failureKind: 'timeout',
				deadlineDurationMilliseconds: invalidDeadline,
			};

			expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow();
		},
	);

	test('rejects deadline drift within a successful launch ledger', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		const firstAttempt = requiredValue(firstLaunch.attempts[0]);
		if (firstAttempt.outcome !== 'succeeded') {
			throw new Error('test fixture expected successful attempt');
		}
		firstAttempt.deadlineDurationMilliseconds = 1_001;

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/attempt deadline must equal 1000 ms/u,
		);
	});

	test('rejects duplicate immutable attempt identities', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		const firstAttempt = requiredValue(firstLaunch.attempts[0]);
		const secondAttempt = requiredValue(firstLaunch.attempts[1]);
		secondAttempt.identity.attemptId = firstAttempt.identity.attemptId;

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/duplicate attempt identity/u,
		);
		const wrongOracleCohort = makeCompleteCohort();
		requiredValue(
			requiredValue(requiredValue(wrongOracleCohort.cells[0]).launches[0]).attempts[0],
		).identity.oracleEntryId = 'oracle:wrong-action';
		expect(() => parseBridgeLocalFirstProofCohort(wrongOracleCohort, expectedRunIdentity)).toThrow(
			/fixture oracle action identity mismatch/u,
		);
	});

	test('rejects duplicate measured interaction identities within one launch', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		const firstAttempt = requiredValue(firstLaunch.attempts[0]);
		const secondAttempt = requiredValue(firstLaunch.attempts[1]);
		secondAttempt.identity.interactionId = firstAttempt.identity.interactionId;

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/globally reused interaction identity/u,
		);
	});

	test('rejects a measured interaction that reuses the warmup identity', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		const firstAttempt = requiredValue(firstLaunch.attempts[0]);
		firstAttempt.identity.interactionId = firstLaunch.warmup.interactionId;

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/globally reused interaction identity/u,
		);
	});

	test('rejects a missing required lifecycle stage', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		firstLaunch.lifecycleStages.splice(2, 1);

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/missing required lifecycle stage/u,
		);
	});

	test('rejects a warmup correctness failure before measured actions', () => {
		const cohort = makeCompleteCohort();
		const launch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		const externalEvidence = structuredClone(launch.warmup.externalEvidence);
		externalEvidence.endpoint = {
			kind: 'failure',
			failureKind: 'timeout',
		};
		launch.warmup = {
			interactionId: launch.warmup.interactionId,
			oracleEntryId: launch.warmup.oracleEntryId,
			outcome: 'failed',
			failureKind: 'timeout',
			deadlineDurationMilliseconds: 1_000,
			externalEvidence,
		};

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/warmup correctness failed/u,
		);
	});

	test('rejects a lifecycle stage that exceeds its contract-owned deadline', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		for (const stage of firstLaunch.lifecycleStages.slice(1)) {
			stage.completedAtMonotonicMilliseconds += 10_001;
		}

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/runtime_ready exceeded its 10000 ms lifecycle deadline/u,
		);
	});

	test('rejects an action, drain, or exit lifecycle window that does not chain', () => {
		const cohort = makeCompleteCohort();
		const launch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		for (const stage of launch.lifecycleStages.slice(4)) {
			stage.startedAtMonotonicMilliseconds += 1;
			stage.completedAtMonotonicMilliseconds += 1;
		}

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/lifecycle stage does not chain to previous evidence/u,
		);
	});

	test('rejects raw interaction evidence outside the measured action window', () => {
		const cohort = makeCompleteCohort();
		const launch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		const lastEvidence = requiredValue(launch.interactionEvidence.at(-1));
		const measuredStage = requiredValue(launch.lifecycleStages[3]);
		const telemetryStage = requiredValue(launch.lifecycleStages[4]);
		const exitStage = requiredValue(launch.lifecycleStages[5]);
		measuredStage.completedAtMonotonicMilliseconds =
			lastEvidence.external.runtimeTiming.endpointObservedAtMonotonicMilliseconds - 1;
		telemetryStage.startedAtMonotonicMilliseconds = measuredStage.completedAtMonotonicMilliseconds;
		telemetryStage.completedAtMonotonicMilliseconds =
			telemetryStage.startedAtMonotonicMilliseconds + 1;
		exitStage.startedAtMonotonicMilliseconds = telemetryStage.completedAtMonotonicMilliseconds;
		exitStage.completedAtMonotonicMilliseconds = exitStage.startedAtMonotonicMilliseconds + 1;

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/action is outside measured lifecycle window/u,
		);
	});

	test('rejects an omitted correlated interaction lifecycle stage', () => {
		const cohort = makeCompleteCohort();
		const evidence = firstTelemetryOnInteractionEvidence(cohort);
		if (evidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		evidence.internal.events.splice(1, 1);

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/internal lifecycle stage count mismatch/u,
		);
	});

	test('admits an exact 8 ms owned synchronous slice and rejects anything above it', () => {
		const boundaryCohort = makeCompleteCohort();
		const boundaryLaunch = requiredTelemetryOnLaunch(boundaryCohort);
		const boundaryAttempt = requiredValue(boundaryLaunch.attempts[0]);
		if (boundaryAttempt.outcome !== 'succeeded') {
			throw new Error('test fixture expected successful attempt');
		}
		boundaryAttempt.durationMilliseconds = 9;
		boundaryLaunch.interactionEvidence[0] = makeInteractionEvidence({
			attempt: boundaryAttempt,
			attemptIndex: 0,
			cell: requiredValue(
				bridgeLocalFirstProofCells.find((cell) => cell.cellId === boundaryLaunch.identity.cellId),
			),
		});
		const boundaryEvidence = firstTelemetryOnInteractionEvidence(boundaryCohort);
		if (boundaryEvidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		const boundarySlice = requiredValue(boundaryEvidence.internal.synchronousSlices[0]);
		boundarySlice.completedAtMonotonicMilliseconds =
			boundarySlice.startedAtMonotonicMilliseconds + 8;
		const overBudgetCohort = structuredClone(boundaryCohort);
		const overBudgetEvidence = firstTelemetryOnInteractionEvidence(overBudgetCohort);
		if (overBudgetEvidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		const overBudgetSlice = requiredValue(overBudgetEvidence.internal.synchronousSlices[0]);
		overBudgetSlice.completedAtMonotonicMilliseconds =
			overBudgetSlice.startedAtMonotonicMilliseconds + 8.001;

		expect(() =>
			parseBridgeLocalFirstProofCohort(boundaryCohort, expectedRunIdentity),
		).not.toThrow();
		expect(() => parseBridgeLocalFirstProofCohort(overBudgetCohort, expectedRunIdentity)).toThrow(
			/owned synchronous slice exceeded 8 ms/u,
		);
	});

	test('rejects a main-thread task at the exact 50 ms stop line', () => {
		const cohort = makeCompleteCohort();
		const evidence = requiredValue(
			requiredValue(requiredValue(cohort.cells[0]).launches[0]).interactionEvidence[0],
		);
		if (evidence.external.eventLoop.runtime !== 'controlled_dev_chromium') {
			throw new Error('test fixture expected Chromium event-loop evidence');
		}
		const stimulusAt = evidence.external.runtimeTiming.stimulusAtMonotonicMilliseconds;
		evidence.external.eventLoop.observationCompletedAtMonotonicMilliseconds = stimulusAt + 50;
		evidence.external.eventLoop.longTasks.push({
			interactionId: evidence.interactionId,
			startedAtMonotonicMilliseconds: stimulusAt,
			completedAtMonotonicMilliseconds: stimulusAt + 50,
		});

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/event-loop gap reached 50 ms/u,
		);
	});

	test('rejects wrong, duplicate, or conflicting correlated lifecycle stages', () => {
		const wrongInteractionCohort = makeCompleteCohort();
		const wrongEvidence = firstTelemetryOnInteractionEvidence(wrongInteractionCohort);
		if (wrongEvidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		requiredValue(wrongEvidence.internal.events[0]).interactionId = 'interaction:wrong';
		const duplicateStageCohort = makeCompleteCohort();
		const duplicateEvidence = firstTelemetryOnInteractionEvidence(duplicateStageCohort);
		if (duplicateEvidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		const firstEvent = requiredValue(duplicateEvidence.internal.events[0]);
		requiredValue(duplicateEvidence.internal.events[1]).stage = firstEvent.stage;

		expect(() =>
			parseBridgeLocalFirstProofCohort(wrongInteractionCohort, expectedRunIdentity),
		).toThrow(/internal lifecycle mismatch/u);
		expect(() =>
			parseBridgeLocalFirstProofCohort(duplicateStageCohort, expectedRunIdentity),
		).toThrow(/internal lifecycle mismatch/u);
	});

	test('rejects a producer sequence gap and a successful attempt after its deadline', () => {
		const gapCohort = makeCompleteCohort();
		const gapEvidence = firstTelemetryOnInteractionEvidence(gapCohort);
		if (gapEvidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		requiredValue(gapEvidence.internal.events[0]).producerSequence += 1;
		const lateCohort = makeCompleteCohort();
		const lateLaunch = requiredValue(requiredValue(lateCohort.cells[0]).launches[0]);
		const lateAttempt = requiredValue(lateLaunch.attempts[0]);
		if (lateAttempt.outcome !== 'succeeded') {
			throw new Error('test fixture expected successful attempt');
		}
		lateAttempt.durationMilliseconds = 1_001;
		lateLaunch.interactionEvidence[0] = makeInteractionEvidence({
			attempt: lateAttempt,
			attemptIndex: 0,
			cell: requiredValue(bridgeLocalFirstProofCells[0]),
		});

		expect(() => parseBridgeLocalFirstProofCohort(gapCohort, expectedRunIdentity)).toThrow(
			/telemetry sequence gap/u,
		);
		expect(() => parseBridgeLocalFirstProofCohort(lateCohort, expectedRunIdentity)).toThrow(
			/success completed after its deadline/u,
		);
	});

	test('rejects a missing telemetry drain record', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		Reflect.deleteProperty(firstLaunch, 'telemetryProof');

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow();
	});

	test('rejects a required telemetry loss range', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredTelemetryOnLaunch(cohort);
		const telemetryProof = firstLaunch.telemetryProof;
		if (telemetryProof.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on proof');
		}
		telemetryProof.lossRanges.push({
			producer: 'main',
			firstMissingSequence: 1,
			lastMissingSequence: 1,
			required: true,
		});

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/required telemetry loss/u,
		);
	});

	test('rejects telemetry-on proof when an interaction omits its internal lifecycle', () => {
		const cohort = makeCompleteCohort();
		const evidence = firstTelemetryOnInteractionEvidence(cohort);
		if (evidence.internal.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on evidence');
		}
		evidence.internal.events = [];

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/internal lifecycle stage count mismatch/u,
		);
	});

	test('rejects telemetry-on proof when a producer drain high-watermark is missing', () => {
		const cohort = makeCompleteCohort();
		const telemetryOnLaunch = requiredTelemetryOnLaunch(cohort);
		const telemetryProof = telemetryOnLaunch.telemetryProof;
		if (telemetryProof.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on proof');
		}
		telemetryProof.drainReceipts.pop();

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/requires both drain receipts/u,
		);
		const lateDrainCohort = makeCompleteCohort();
		const lateDrainLaunch = requiredTelemetryOnLaunch(lateDrainCohort);
		if (lateDrainLaunch.telemetryProof.mode !== 'on') {
			throw new Error('test fixture expected telemetry-on proof');
		}
		requiredValue(lateDrainLaunch.telemetryProof.drainReceipts[0]).drainedAtMonotonicMilliseconds =
			requiredValue(lateDrainLaunch.lifecycleStages[4]).completedAtMonotonicMilliseconds + 1;
		expect(() => parseBridgeLocalFirstProofCohort(lateDrainCohort, expectedRunIdentity)).toThrow(
			/telemetry drain is outside settlement window/u,
		);
	});

	test('rejects telemetry worker or drain proof in a telemetry-off cell', () => {
		const cohort = makeCompleteCohort();
		const telemetryOffLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		telemetryOffLaunch.telemetryProof = structuredClone(
			requiredTelemetryOnLaunch(cohort).telemetryProof,
		);

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/telemetry-off launch constructed telemetry/u,
		);
	});

	test.each([
		['headCommitSha', 'fedcba9876543210fedcba9876543210fedcba98'],
		['fixtureId', 'stale-fixture'],
		['fixtureChecksum', '5'.repeat(64)],
		['pierreVersion', '@pierre/diffs@stale'],
	] as const)('rejects stale run identity field %s', (identityField, staleValue) => {
		const cohort = makeCompleteCohort();
		cohort.runIdentity[identityField] = staleValue;
		cohort.runIdentity.runManifestHash = bridgeLocalFirstProofRunManifestHash(cohort.runIdentity);
		cohort.runIdentity.runIdentityFingerprint = bridgeLocalFirstProofRunIdentityFingerprint(
			cohort.runIdentity,
		);

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			new RegExp(`stale run identity: ${identityField}`, 'u'),
		);
	});

	test('rejects an incomplete closed cell manifest', () => {
		const cohort = makeCompleteCohort();
		cohort.cells.pop();

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/exactly 84 manifest cells/u,
		);
	});

	test('rejects parent identity drift inside a launch artifact', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		firstLaunch.identity.cellId = 'stale-cell-id';

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/launch identity does not match parent cell/u,
		);
	});

	test('rejects resumed launch provenance from another run identity', () => {
		const cohort = makeCompleteCohort();
		const firstLaunch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		firstLaunch.identity.runIdentityFingerprint = '7'.repeat(64);

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/launch identity does not match parent cell/u,
		);
	});

	test('rejects a packaged launch whose bundle hash does not match the run identity', () => {
		const cohort = makeCompleteCohort();
		const packagedCell = requiredValue(
			cohort.cells.find((cell) => cell.identity.runtime === 'packaged_wkwebview'),
		);
		const firstLaunch = requiredValue(packagedCell.launches[0]);
		if (firstLaunch.identity.runtimeProcessIdentity.runtime !== 'packaged_wkwebview') {
			throw new Error('test fixture expected packaged process identity');
		}
		firstLaunch.identity.runtimeProcessIdentity.bundleHash = '8'.repeat(64);

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/launch packaged app identity mismatch/u,
		);
	});

	test('rejects a launch whose hashed process start token was tampered independently', () => {
		const cohort = makeCompleteCohort();
		const launch = requiredValue(requiredValue(cohort.cells[0]).launches[0]);
		launch.identity.processStartToken = `${launch.identity.processStartToken}:tampered`;

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/process instance identity does not match concrete launch evidence/u,
		);
	});

	test('rejects one concrete OS process instance reused across runtime partitions', () => {
		const cohort = makeCompleteCohort();
		const browserLaunch = requiredValue(
			requiredValue(
				cohort.cells.find((cell) => cell.identity.runtime === 'controlled_dev_chromium'),
			).launches[0],
		);
		const nativeLaunch = requiredValue(
			requiredValue(cohort.cells.find((cell) => cell.identity.runtime === 'packaged_wkwebview'))
				.launches[0],
		);
		nativeLaunch.identity.processId = browserLaunch.identity.processId;
		nativeLaunch.identity.processStartToken = browserLaunch.identity.processStartToken;
		nativeLaunch.identity.executableSha256 = browserLaunch.identity.executableSha256;
		nativeLaunch.identity.processInstanceId = browserLaunch.identity.processInstanceId;
		if (nativeLaunch.identity.runtimeProcessIdentity.runtime !== 'packaged_wkwebview') {
			throw new Error('test fixture expected packaged process identity');
		}
		nativeLaunch.identity.runtimeProcessIdentity.appProcessId = browserLaunch.identity.processId;

		expect(() => parseBridgeLocalFirstProofCohort(cohort, expectedRunIdentity)).toThrow(
			/duplicate process instance identity/u,
		);
	});
});

interface MakeCompleteCohortProps {
	readonly launchCount?: number;
	readonly measuredAttemptCount?: number;
	readonly makeAttempt?: (props: {
		readonly attemptIndex: number;
		readonly defaultAttempt: DeepMutable<BridgeLocalFirstProofAttemptInput>;
		readonly launchIndex: number;
	}) => DeepMutable<BridgeLocalFirstProofAttemptInput>;
}

type DeepMutable<TValue> = BridgeLocalFirstTestDeepMutable<TValue>;

function contractTestFixtureOptions(
	props: MakeCompleteCohortProps = {},
): BridgeLocalFirstTestProofFixtureOptions {
	return {
		runIdentity: expectedRunIdentity,
		executableSha256,
		...(props.launchCount === undefined ? {} : { launchCount: props.launchCount }),
		...(props.measuredAttemptCount === undefined
			? {}
			: { measuredAttemptCount: props.measuredAttemptCount }),
		...(props.makeAttempt === undefined ? {} : { makeAttempt: props.makeAttempt }),
		stimulusBaseMilliseconds: 100,
		stimulusStrideMilliseconds: 1_000,
		successfulDurationMilliseconds: ({ attemptIndex }): number => attemptIndex + 1,
	};
}

function makeCompleteCohort(
	props: MakeCompleteCohortProps = {},
): DeepMutable<BridgeLocalFirstProofCohortInput> {
	return makeBridgeLocalFirstTestProofFixture(contractTestFixtureOptions(props)).cohort;
}

function makeInteractionEvidence(props: {
	readonly attempt: DeepMutable<BridgeLocalFirstProofAttemptInput>;
	readonly attemptIndex: number;
	readonly cell: BridgeLocalFirstProofCellContract;
}): DeepMutable<
	BridgeLocalFirstProofCohortInput['cells'][number]['launches'][number]['interactionEvidence'][number]
> {
	return makeBridgeLocalFirstTestInteractionEvidence({
		...props,
		options: contractTestFixtureOptions(),
	});
}

function requiredValue<TValue>(value: TValue | undefined): TValue {
	if (value === undefined) throw new Error('unit-test fixture expected value');
	return value;
}

function requiredTelemetryOnLaunch(
	cohort: DeepMutable<BridgeLocalFirstProofCohortInput>,
): DeepMutable<BridgeLocalFirstProofCohortInput>['cells'][number]['launches'][number] {
	const telemetryOnCell = cohort.cells.find((cell) => cell.identity.telemetryState === 'on');
	return requiredValue(requiredValue(telemetryOnCell).launches[0]);
}

function firstTelemetryOnInteractionEvidence(
	cohort: DeepMutable<BridgeLocalFirstProofCohortInput>,
): DeepMutable<
	BridgeLocalFirstProofCohortInput['cells'][number]['launches'][number]['interactionEvidence'][number]
> {
	return requiredValue(requiredTelemetryOnLaunch(cohort).interactionEvidence[0]);
}
