import {
	parseBridgeLocalFirstProofCohort,
	type BridgeLocalFirstProofRunIdentity,
	type BridgeLocalFirstValidatedProofCohort,
} from './bridge-local-first-proof-contract.ts';
import {
	bridgeLocalFirstProofExternalDurationMilliseconds,
	type BridgeLocalFirstValidatedFixtureOracle,
} from './bridge-local-first-proof-evidence.ts';
import {
	bridgeLocalFirstProofApplicabilityByCellId,
	bridgeLocalFirstProofInternalSlo,
} from './bridge-local-first-proof-manifest.ts';

type BridgeLocalFirstValidatedProofCell = BridgeLocalFirstValidatedProofCohort['cells'][number];
type BridgeLocalFirstValidatedProofLaunch = BridgeLocalFirstValidatedProofCell['launches'][number];
type BridgeLocalFirstValidatedProofAttempt =
	BridgeLocalFirstValidatedProofLaunch['attempts'][number];
type BridgeLocalFirstValidatedInteractionEvidence =
	BridgeLocalFirstValidatedProofLaunch['interactionEvidence'][number];

export interface BridgeLocalFirstProofPercentileSummary {
	readonly sampleCount: number;
	readonly failureCount: number;
	readonly p95DurationMilliseconds: number;
	readonly p99DurationMilliseconds: number;
}

export function validateBridgeLocalFirstInternalSloBudgets(
	cohort: BridgeLocalFirstValidatedProofCohort,
): void {
	for (const cell of cohort.cells) {
		validateBridgeLocalFirstInternalSloCellBudgets(cell);
	}
}

export function validateBridgeLocalFirstInternalSloCellBudgets(
	cell: BridgeLocalFirstValidatedProofCell,
): void {
	if (cell.identity.telemetryState === 'off') return;
	const applicability = bridgeLocalFirstProofApplicabilityByCellId.get(cell.identity.cellId);
	if (applicability === undefined) {
		throw new Error(`${cell.identity.cellId}: missing internal SLO applicability`);
	}
	if (applicability.selectedCommQueue === 'required') {
		validateInternalSpanBudgets({
			cell,
			kind: 'selected_comm_queue',
			label: 'comm queue',
			p95BudgetMilliseconds: bridgeLocalFirstProofInternalSlo.commQueueP95Milliseconds,
			p99BudgetMilliseconds: bridgeLocalFirstProofInternalSlo.commQueueP99Milliseconds,
		});
	}
	if (applicability.pierreSubmission === 'required') {
		validateInternalSpanBudgets({
			cell,
			kind: 'main_to_pierre',
			label: 'main-to-Pierre',
			p95BudgetMilliseconds: bridgeLocalFirstProofInternalSlo.mainToPierreP95Milliseconds,
			p99BudgetMilliseconds: bridgeLocalFirstProofInternalSlo.mainToPierreP99Milliseconds,
		});
	}
}

function validateInternalSpanBudgets(props: {
	readonly cell: BridgeLocalFirstValidatedProofCell;
	readonly kind: 'main_to_pierre' | 'selected_comm_queue';
	readonly label: string;
	readonly p95BudgetMilliseconds: number;
	readonly p99BudgetMilliseconds: number;
}): void {
	const pooledSamples: number[] = [];
	const launchSummaries = props.cell.launches.map((launch) => {
		const samples = launch.interactionEvidence.flatMap((evidence) => {
			if (evidence.internal.mode !== 'on') {
				throw new Error(`${launch.identity.launchId}: telemetry-on cell has no internal evidence`);
			}
			return evidence.internal.spans
				.filter((span) => span.kind === props.kind)
				.map((span) => span.completedAtMonotonicMilliseconds - span.startedAtMonotonicMilliseconds);
		});
		if (samples.length !== launch.attempts.length) {
			throw new Error(
				`${launch.identity.launchId}: ${props.label} sample count does not match attempted actions`,
			);
		}
		pooledSamples.push(...samples);
		return validateInternalPercentiles({
			label: `${launch.identity.launchId}: ${props.label}`,
			p95BudgetMilliseconds: props.p95BudgetMilliseconds,
			p99BudgetMilliseconds: props.p99BudgetMilliseconds,
			samples,
		});
	});
	validateInternalPercentiles({
		label: `${props.cell.identity.cellId}/pooled ${props.label}`,
		p95BudgetMilliseconds: props.p95BudgetMilliseconds,
		p99BudgetMilliseconds: props.p99BudgetMilliseconds,
		samples: pooledSamples,
	});
	validateWorstInternalPercentiles({
		cellId: props.cell.identity.cellId,
		label: props.label,
		launches: launchSummaries,
		p95BudgetMilliseconds: props.p95BudgetMilliseconds,
		p99BudgetMilliseconds: props.p99BudgetMilliseconds,
	});
}

interface InternalPercentileSummary {
	readonly p95DurationMilliseconds: number;
	readonly p99DurationMilliseconds: number;
}

function validateInternalPercentiles(props: {
	readonly label: string;
	readonly p95BudgetMilliseconds: number;
	readonly p99BudgetMilliseconds: number;
	readonly samples: readonly number[];
}): InternalPercentileSummary {
	const p95DurationMilliseconds = nearestRankPercentile(props.samples, 0.95);
	const p99DurationMilliseconds = nearestRankPercentile(props.samples, 0.99);
	if (p95DurationMilliseconds >= props.p95BudgetMilliseconds) {
		throw new Error(`${props.label} p95 ${p95DurationMilliseconds} ms exceeds strict budget`);
	}
	if (p99DurationMilliseconds >= props.p99BudgetMilliseconds) {
		throw new Error(`${props.label} p99 ${p99DurationMilliseconds} ms exceeds strict budget`);
	}
	return { p95DurationMilliseconds, p99DurationMilliseconds };
}

function validateWorstInternalPercentiles(props: {
	readonly cellId: string;
	readonly label: string;
	readonly launches: readonly InternalPercentileSummary[];
	readonly p95BudgetMilliseconds: number;
	readonly p99BudgetMilliseconds: number;
}): void {
	const worstP95 = Math.max(...props.launches.map((summary) => summary.p95DurationMilliseconds));
	const worstP99 = Math.max(...props.launches.map((summary) => summary.p99DurationMilliseconds));
	if (worstP95 >= props.p95BudgetMilliseconds || worstP99 >= props.p99BudgetMilliseconds) {
		throw new Error(`${props.cellId}/worst-launch ${props.label} exceeded strict budget`);
	}
}

export interface BridgeLocalFirstProofLaunchReduction extends BridgeLocalFirstProofPercentileSummary {
	readonly launchId: string;
	readonly launchIndex: number;
}

export interface BridgeLocalFirstProofCellReduction {
	readonly identity: BridgeLocalFirstValidatedProofCell['identity'];
	readonly launches: readonly BridgeLocalFirstProofLaunchReduction[];
	readonly pooled: BridgeLocalFirstProofPercentileSummary;
	readonly worstLaunch: {
		readonly p95LaunchId: string;
		readonly p95DurationMilliseconds: number;
		readonly p99LaunchId: string;
		readonly p99DurationMilliseconds: number;
	};
}

export interface BridgeLocalFirstProofCohortReduction {
	readonly runIdentity: BridgeLocalFirstValidatedProofCohort['runIdentity'];
	readonly cells: readonly BridgeLocalFirstProofCellReduction[];
	readonly totals: {
		readonly cellCount: number;
		readonly launchCount: number;
		readonly measuredAttemptCount: number;
		readonly failureCount: number;
	};
}

export function reduceBridgeLocalFirstProofCohort(
	rawCohort: unknown,
	expectedRunIdentity: BridgeLocalFirstProofRunIdentity,
	fixtureOracle: BridgeLocalFirstValidatedFixtureOracle,
): BridgeLocalFirstProofCohortReduction {
	const cohort = parseBridgeLocalFirstProofCohort(rawCohort, expectedRunIdentity, fixtureOracle);
	return reduceBridgeLocalFirstValidatedProofCohort(cohort);
}

export function reduceBridgeLocalFirstValidatedProofCohort(
	cohort: BridgeLocalFirstValidatedProofCohort,
): BridgeLocalFirstProofCohortReduction {
	let measuredAttemptCount = 0;
	let failureCount = 0;
	const cells = cohort.cells.map((cell): BridgeLocalFirstProofCellReduction => {
		const pooledSamples: number[] = [];
		const launches = cell.launches.map((launch): BridgeLocalFirstProofLaunchReduction => {
			const samples = launch.attempts.map((attempt, attemptIndex) =>
				attemptDurationSample(attempt, launch.interactionEvidence[attemptIndex]),
			);
			const launchFailureCount = launch.attempts.reduce(
				(count, attempt) => count + (attempt.outcome === 'failed' ? 1 : 0),
				0,
			);
			pooledSamples.push(...samples);
			measuredAttemptCount += samples.length;
			failureCount += launchFailureCount;
			return Object.freeze({
				launchId: launch.identity.launchId,
				launchIndex: launch.identity.launchIndex,
				sampleCount: samples.length,
				failureCount: launchFailureCount,
				p95DurationMilliseconds: nearestRankPercentile(samples, 0.95),
				p99DurationMilliseconds: nearestRankPercentile(samples, 0.99),
			});
		});
		const p95WorstLaunch = maximumLaunchPercentile(launches, 'p95DurationMilliseconds');
		const p99WorstLaunch = maximumLaunchPercentile(launches, 'p99DurationMilliseconds');
		return Object.freeze({
			identity: cell.identity,
			launches: Object.freeze(launches),
			pooled: Object.freeze({
				sampleCount: pooledSamples.length,
				failureCount: launches.reduce((count, launch) => count + launch.failureCount, 0),
				p95DurationMilliseconds: nearestRankPercentile(pooledSamples, 0.95),
				p99DurationMilliseconds: nearestRankPercentile(pooledSamples, 0.99),
			}),
			worstLaunch: Object.freeze({
				p95LaunchId: p95WorstLaunch.launchId,
				p95DurationMilliseconds: p95WorstLaunch.p95DurationMilliseconds,
				p99LaunchId: p99WorstLaunch.launchId,
				p99DurationMilliseconds: p99WorstLaunch.p99DurationMilliseconds,
			}),
		});
	});

	return Object.freeze({
		runIdentity: cohort.runIdentity,
		cells: Object.freeze(cells),
		totals: Object.freeze({
			cellCount: cells.length,
			launchCount: cells.reduce((count, cell) => count + cell.launches.length, 0),
			measuredAttemptCount,
			failureCount,
		}),
	});
}

function attemptDurationSample(
	attempt: BridgeLocalFirstValidatedProofAttempt,
	evidence: BridgeLocalFirstValidatedInteractionEvidence | undefined,
): number {
	if (attempt.outcome === 'failed') {
		return attempt.deadlineDurationMilliseconds;
	}
	if (evidence === undefined) {
		throw new Error(`${attempt.identity.attemptId}: missing duration evidence`);
	}
	return bridgeLocalFirstProofExternalDurationMilliseconds(evidence.external);
}

function nearestRankPercentile(samples: readonly number[], percentile: number): number {
	if (samples.length === 0) {
		throw new Error('nearest-rank percentile requires at least one sample');
	}
	if (!Number.isFinite(percentile) || percentile <= 0 || percentile > 1) {
		throw new Error(`nearest-rank percentile must be within (0, 1], got ${percentile}`);
	}
	const sortedSamples = [...samples];
	// oxlint-disable-next-line unicorn/no-array-sort -- A local numeric copy is the percentile oracle input.
	sortedSamples.sort((left, right): number => left - right);
	const rankIndex = Math.ceil(sortedSamples.length * percentile) - 1;
	const sample = sortedSamples[rankIndex];
	if (sample === undefined) {
		throw new Error(`nearest-rank percentile ${percentile} produced no sample`);
	}
	return sample;
}

function maximumLaunchPercentile(
	launches: readonly BridgeLocalFirstProofLaunchReduction[],
	percentileField: 'p95DurationMilliseconds' | 'p99DurationMilliseconds',
): BridgeLocalFirstProofLaunchReduction {
	const firstLaunch = launches[0];
	if (firstLaunch === undefined) {
		throw new Error('worst-launch reduction requires at least one launch');
	}
	return launches.slice(1).reduce((worstLaunch, candidateLaunch) => {
		return candidateLaunch[percentileField] > worstLaunch[percentileField]
			? candidateLaunch
			: worstLaunch;
	}, firstLaunch);
}
