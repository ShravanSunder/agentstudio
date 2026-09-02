export type BridgeCompleteJourneyCarrier = 'development' | 'native';
export type BridgeCompleteJourney = 'fileToReview' | 'firstFile' | 'firstReview' | 'reviewToFile';
export type BridgeCompleteJourneyPhase =
	| 'commitPaint'
	| 'handshakeWorker'
	| 'pageApplication'
	| 'selectionContent'
	| 'sourceMetadata';

export type BridgeCompleteJourneyPhaseCompletions = Partial<
	Readonly<Record<BridgeCompleteJourneyPhase, number>>
>;

interface BridgeCompleteJourneyAttemptBase {
	readonly attemptId: string;
	readonly durationMilliseconds: number;
	readonly phaseCompletionElapsedMilliseconds: BridgeCompleteJourneyPhaseCompletions;
}

export type BridgeCompleteJourneyAttempt =
	| (BridgeCompleteJourneyAttemptBase & {
			readonly outcome: 'succeeded';
	  })
	| (BridgeCompleteJourneyAttemptBase & {
			readonly failureReason: string;
			readonly outcome: 'failed';
	  });

export interface BridgeCompleteJourneyLaunch {
	readonly attempts: readonly BridgeCompleteJourneyAttempt[];
	readonly evidence: BridgeCompleteJourneyLaunchEvidence;
	readonly launchId: string;
}

export interface BridgeCompleteJourneyLaunchEvidence {
	readonly cacheState: 'fresh-empty-vite-cache' | 'fresh-isolated-app-data';
	readonly fixtureIdentity: 'current-worktree' | 'packaged-disposable-worktree';
	readonly sourceHead: string;
	readonly telemetryMarker: string;
	readonly telemetryServiceVersion: string;
	readonly telemetry: BridgeCompleteJourneyTelemetryEvidence;
	readonly worktreeHash: string;
}

export type BridgeCompleteJourneyTelemetryEvidence =
	| {
			readonly acceptedSampleCount: number;
			readonly failedBatchCount: number;
			readonly kind: 'development-batches';
	  }
	| {
			readonly drainFailureCount: number;
			readonly expectedAttemptCount: number;
			readonly kind: 'native-pane-reports';
			readonly lossyPaneReportCount: number;
			readonly missingPaneReportCount: number;
			readonly nativeBatchSequenceGapCount: number;
			readonly observedPaneReportCount: number;
			readonly optionalLossCount: number;
			readonly proofEligiblePaneReportCount: number;
			readonly requiredLossCount: number;
			readonly workerSequenceGapCount: number;
	  };

export interface BridgeCompleteJourneyCohort {
	readonly carrier: BridgeCompleteJourneyCarrier;
	readonly journey: BridgeCompleteJourney;
	readonly launches: readonly BridgeCompleteJourneyLaunch[];
}

export interface BridgeCompleteJourneyDurationSummary {
	readonly maxMilliseconds: number;
	readonly medianMilliseconds: number;
	readonly minMilliseconds: number;
	readonly p95Milliseconds: number;
	readonly p99Milliseconds: number;
	readonly sampleCount: number;
}

export interface BridgeCompleteJourneyLaunchReduction {
	readonly evidence: BridgeCompleteJourneyLaunchEvidence;
	readonly failureCount: number;
	readonly launchId: string;
	readonly phaseContributions: Readonly<
		Partial<Record<BridgeCompleteJourneyPhase, BridgeCompleteJourneyDurationSummary>>
	>;
	readonly summary: BridgeCompleteJourneyDurationSummary;
}

export interface BridgeCompleteJourneyCohortReduction {
	readonly carrier: BridgeCompleteJourneyCarrier;
	readonly failureCount: number;
	readonly journey: BridgeCompleteJourney;
	readonly launches: readonly BridgeCompleteJourneyLaunchReduction[];
	readonly phaseContributions: Readonly<
		Partial<Record<BridgeCompleteJourneyPhase, BridgeCompleteJourneyDurationSummary>>
	>;
	readonly pooled: BridgeCompleteJourneyDurationSummary;
	readonly sampleCount: number;
	readonly satisfied: boolean;
	readonly worstLaunch: {
		readonly p95LaunchId: string;
		readonly p95Milliseconds: number;
		readonly p99LaunchId: string;
		readonly p99Milliseconds: number;
	};
}

export const bridgeCompleteJourneyRequiredLaunchCount = 3;
export const bridgeCompleteJourneyMinimumAttemptsPerLaunch = 100;
export const bridgeCompleteJourneyP95BudgetMilliseconds = 600;
export const bridgeCompleteJourneyP99BudgetMilliseconds = 1_000;

const orderedBridgeCompleteJourneyPhases = [
	'pageApplication',
	'handshakeWorker',
	'sourceMetadata',
	'selectionContent',
	'commitPaint',
] as const satisfies readonly BridgeCompleteJourneyPhase[];

export function reduceBridgeCompleteJourneyCohort(
	cohort: BridgeCompleteJourneyCohort,
): BridgeCompleteJourneyCohortReduction {
	validateBridgeCompleteJourneyCohort(cohort);
	const pooledDurations: number[] = [];
	const pooledPhaseContributions = emptyPhaseContributionSamples();
	let failureCount = 0;
	const launches = cohort.launches.map((launch): BridgeCompleteJourneyLaunchReduction => {
		const durations = launch.attempts.map((attempt): number => attempt.durationMilliseconds);
		const phaseContributions = phaseContributionSamplesForAttempts(launch.attempts);
		pooledDurations.push(...durations);
		appendPhaseContributionSamples(pooledPhaseContributions, phaseContributions);
		const launchFailureCount = launch.attempts.filter(
			(attempt): boolean => attempt.outcome === 'failed',
		).length;
		failureCount += launchFailureCount;
		return {
			evidence: launch.evidence,
			failureCount: launchFailureCount,
			launchId: launch.launchId,
			phaseContributions: summarizePhaseContributionSamples(phaseContributions),
			summary: summarizeDurations(durations),
		};
	});
	const pooled = summarizeDurations(pooledDurations);
	const worstP95Launch = maximumLaunchPercentile(launches, 'p95Milliseconds');
	const worstP99Launch = maximumLaunchPercentile(launches, 'p99Milliseconds');
	return {
		carrier: cohort.carrier,
		failureCount,
		journey: cohort.journey,
		launches,
		phaseContributions: summarizePhaseContributionSamples(pooledPhaseContributions),
		pooled,
		sampleCount: pooled.sampleCount,
		satisfied:
			failureCount === 0 &&
			launches.every(({ evidence }): boolean =>
				bridgeCompleteJourneyTelemetryEvidenceSatisfied(evidence.telemetry),
			) &&
			launches.every(({ summary }): boolean => durationSummarySatisfiesBudgets(summary)) &&
			durationSummarySatisfiesBudgets(pooled),
		worstLaunch: {
			p95LaunchId: worstP95Launch.launchId,
			p95Milliseconds: worstP95Launch.summary.p95Milliseconds,
			p99LaunchId: worstP99Launch.launchId,
			p99Milliseconds: worstP99Launch.summary.p99Milliseconds,
		},
	};
}

function validateBridgeCompleteJourneyCohort(cohort: BridgeCompleteJourneyCohort): void {
	if (cohort.launches.length !== bridgeCompleteJourneyRequiredLaunchCount) {
		throw new Error(
			`Bridge complete journey cohort requires exactly ${bridgeCompleteJourneyRequiredLaunchCount} launches.`,
		);
	}
	const launchIds = new Set<string>();
	const attemptIds = new Set<string>();
	for (const launch of cohort.launches) {
		if (launch.launchId.length === 0 || launchIds.has(launch.launchId)) {
			throw new Error('Bridge complete journey launch IDs must be unique and non-empty.');
		}
		launchIds.add(launch.launchId);
		validateBridgeCompleteJourneyLaunchEvidence(launch.evidence);
		if (launch.attempts.length < bridgeCompleteJourneyMinimumAttemptsPerLaunch) {
			throw new Error(
				`Bridge complete journey launch ${launch.launchId} requires at least ${bridgeCompleteJourneyMinimumAttemptsPerLaunch} attempts.`,
			);
		}
		for (const attempt of launch.attempts) {
			validateBridgeCompleteJourneyAttempt(attempt, attemptIds);
		}
	}
}

function validateBridgeCompleteJourneyLaunchEvidence(
	evidence: BridgeCompleteJourneyLaunchEvidence | undefined,
): void {
	if (
		evidence === undefined ||
		!['fresh-empty-vite-cache', 'fresh-isolated-app-data'].includes(evidence.cacheState) ||
		!['current-worktree', 'packaged-disposable-worktree'].includes(evidence.fixtureIdentity) ||
		!/^[0-9a-f]{40}$/u.test(evidence.sourceHead) ||
		evidence.telemetryMarker.length === 0 ||
		evidence.telemetryServiceVersion.length === 0 ||
		evidence.worktreeHash.length === 0 ||
		!bridgeCompleteJourneyTelemetryEvidenceIsValid(evidence.telemetry)
	) {
		throw new Error('Expected complete journey launch evidence.');
	}
}

function bridgeCompleteJourneyTelemetryEvidenceIsValid(
	evidence: BridgeCompleteJourneyTelemetryEvidence | undefined,
): boolean {
	if (evidence === undefined) return false;
	if (evidence.kind === 'development-batches') {
		return nonnegativeSafeIntegers([evidence.acceptedSampleCount, evidence.failedBatchCount]);
	}
	return (
		evidence.expectedAttemptCount > 0 &&
		nonnegativeSafeIntegers([
			evidence.drainFailureCount,
			evidence.expectedAttemptCount,
			evidence.lossyPaneReportCount,
			evidence.missingPaneReportCount,
			evidence.nativeBatchSequenceGapCount,
			evidence.observedPaneReportCount,
			evidence.optionalLossCount,
			evidence.proofEligiblePaneReportCount,
			evidence.requiredLossCount,
			evidence.workerSequenceGapCount,
		]) &&
		evidence.observedPaneReportCount + evidence.missingPaneReportCount ===
			evidence.expectedAttemptCount &&
		evidence.proofEligiblePaneReportCount <= evidence.observedPaneReportCount &&
		evidence.lossyPaneReportCount <= evidence.observedPaneReportCount
	);
}

function bridgeCompleteJourneyTelemetryEvidenceSatisfied(
	evidence: BridgeCompleteJourneyTelemetryEvidence,
): boolean {
	if (evidence.kind === 'development-batches') return evidence.failedBatchCount === 0;
	return (
		evidence.observedPaneReportCount === evidence.expectedAttemptCount &&
		evidence.missingPaneReportCount === 0 &&
		evidence.proofEligiblePaneReportCount === evidence.expectedAttemptCount &&
		evidence.lossyPaneReportCount === 0 &&
		evidence.requiredLossCount === 0 &&
		evidence.optionalLossCount === 0 &&
		evidence.workerSequenceGapCount === 0 &&
		evidence.nativeBatchSequenceGapCount === 0 &&
		evidence.drainFailureCount === 0
	);
}

function nonnegativeSafeIntegers(values: readonly number[]): boolean {
	return values.every((value): boolean => Number.isSafeInteger(value) && value >= 0);
}

function validateBridgeCompleteJourneyAttempt(
	attempt: BridgeCompleteJourneyAttempt,
	attemptIds: Set<string>,
): void {
	if (attempt.attemptId.length === 0 || attemptIds.has(attempt.attemptId)) {
		throw new Error('Bridge complete journey attempt IDs must be unique and non-empty.');
	}
	attemptIds.add(attempt.attemptId);
	if (!Number.isFinite(attempt.durationMilliseconds) || attempt.durationMilliseconds < 0) {
		throw new Error(`${attempt.attemptId}: duration must be finite and nonnegative.`);
	}
	if (attempt.outcome === 'failed') {
		if (attempt.failureReason.length === 0) {
			throw new Error(`${attempt.attemptId}: failed attempt requires a reason.`);
		}
		validateKnownPhaseValues(attempt);
		return;
	}
	let previousCompletion = 0;
	for (const phase of orderedBridgeCompleteJourneyPhases) {
		const completion = attempt.phaseCompletionElapsedMilliseconds[phase];
		if (
			completion === undefined ||
			!Number.isFinite(completion) ||
			completion < previousCompletion
		) {
			throw new Error(`${attempt.attemptId}: phase completions must be monotonic and complete.`);
		}
		previousCompletion = completion;
	}
	if (previousCompletion > attempt.durationMilliseconds) {
		throw new Error(`${attempt.attemptId}: final phase exceeds total duration.`);
	}
}

function validateKnownPhaseValues(attempt: BridgeCompleteJourneyAttempt): void {
	for (const completion of Object.values(attempt.phaseCompletionElapsedMilliseconds)) {
		if (
			!Number.isFinite(completion) ||
			completion < 0 ||
			completion > attempt.durationMilliseconds
		) {
			throw new Error(`${attempt.attemptId}: phase completion is outside the attempt duration.`);
		}
	}
}

function summarizeDurations(durations: readonly number[]): BridgeCompleteJourneyDurationSummary {
	if (durations.length === 0) throw new Error('Cannot summarize an empty duration set.');
	const sortedDurations = durations.toSorted((left, right): number => left - right);
	return {
		maxMilliseconds: requiredNumber(sortedDurations.at(-1)),
		medianMilliseconds: nearestRankPercentile(sortedDurations, 0.5),
		minMilliseconds: requiredNumber(sortedDurations[0]),
		p95Milliseconds: nearestRankPercentile(sortedDurations, 0.95),
		p99Milliseconds: nearestRankPercentile(sortedDurations, 0.99),
		sampleCount: sortedDurations.length,
	};
}

function nearestRankPercentile(sortedDurations: readonly number[], percentile: number): number {
	const rank = Math.ceil(percentile * sortedDurations.length);
	return requiredNumber(sortedDurations[Math.max(0, rank - 1)]);
}

function durationSummarySatisfiesBudgets(summary: BridgeCompleteJourneyDurationSummary): boolean {
	return (
		summary.p95Milliseconds <= bridgeCompleteJourneyP95BudgetMilliseconds &&
		summary.p99Milliseconds <= bridgeCompleteJourneyP99BudgetMilliseconds
	);
}

type PhaseContributionSamples = Record<BridgeCompleteJourneyPhase, number[]>;

function emptyPhaseContributionSamples(): PhaseContributionSamples {
	return {
		commitPaint: [],
		handshakeWorker: [],
		pageApplication: [],
		selectionContent: [],
		sourceMetadata: [],
	};
}

function phaseContributionSamplesForAttempts(
	attempts: readonly BridgeCompleteJourneyAttempt[],
): PhaseContributionSamples {
	const samples = emptyPhaseContributionSamples();
	for (const attempt of attempts) {
		let previousCompletion = 0;
		for (const phase of orderedBridgeCompleteJourneyPhases) {
			const completion = attempt.phaseCompletionElapsedMilliseconds[phase];
			if (completion === undefined) continue;
			samples[phase].push(Math.max(0, completion - previousCompletion));
			previousCompletion = completion;
		}
	}
	return samples;
}

function appendPhaseContributionSamples(
	target: PhaseContributionSamples,
	source: PhaseContributionSamples,
): void {
	for (const phase of orderedBridgeCompleteJourneyPhases) target[phase].push(...source[phase]);
}

function summarizePhaseContributionSamples(
	samples: PhaseContributionSamples,
): Partial<Record<BridgeCompleteJourneyPhase, BridgeCompleteJourneyDurationSummary>> {
	return Object.fromEntries(
		orderedBridgeCompleteJourneyPhases.flatMap((phase) =>
			samples[phase].length === 0 ? [] : [[phase, summarizeDurations(samples[phase])]],
		),
	);
}

function maximumLaunchPercentile(
	launches: readonly BridgeCompleteJourneyLaunchReduction[],
	percentile: 'p95Milliseconds' | 'p99Milliseconds',
): BridgeCompleteJourneyLaunchReduction {
	const firstLaunch = launches[0];
	if (firstLaunch === undefined) throw new Error('Expected at least one complete journey launch.');
	return launches.reduce((worstLaunch, launch) =>
		launch.summary[percentile] > worstLaunch.summary[percentile] ? launch : worstLaunch,
	);
}

function requiredNumber(value: number | undefined): number {
	if (value === undefined) throw new Error('Expected a percentile sample.');
	return value;
}
