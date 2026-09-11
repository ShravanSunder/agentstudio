import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

import { z } from 'zod';

import {
	bridgeCompleteJourneyMinimumAttemptsPerLaunch,
	reduceBridgeCompleteJourneyCohort,
	type BridgeCompleteJourney,
	type BridgeCompleteJourneyAttempt,
	type BridgeCompleteJourneyCohort,
	type BridgeCompleteJourneyCohortReduction,
	type BridgeCompleteJourneyTelemetryEvidence,
} from './verify-bridge-viewer-worktree-dev-server/complete-journey-cohort.ts';

const phaseCompletionSchema = z
	.object({
		commitPaint: z.number().finite().nonnegative().optional(),
		handshakeWorker: z.number().finite().nonnegative().optional(),
		pageApplication: z.number().finite().nonnegative().optional(),
		selectionContent: z.number().finite().nonnegative().optional(),
		sourceMetadata: z.number().finite().nonnegative().optional(),
	})
	.strict();

const completePhaseCompletionSchema = z
	.object({
		commitPaint: z.number().finite().nonnegative(),
		handshakeWorker: z.number().finite().nonnegative(),
		pageApplication: z.number().finite().nonnegative(),
		selectionContent: z.number().finite().nonnegative(),
		sourceMetadata: z.number().finite().nonnegative(),
	})
	.strict();

const attemptSchema = z.discriminatedUnion('outcome', [
	z
		.object({
			attemptId: z.string().min(1),
			durationMilliseconds: z.number().finite().nonnegative(),
			outcome: z.literal('succeeded'),
			phaseCompletionElapsedMilliseconds: completePhaseCompletionSchema,
		})
		.strict(),
	z
		.object({
			attemptId: z.string().min(1),
			durationMilliseconds: z.number().finite().nonnegative(),
			failureReason: z.string().min(1),
			outcome: z.literal('failed'),
			phaseCompletionElapsedMilliseconds: phaseCompletionSchema,
		})
		.strict(),
]);

const nativeTelemetryProofSchema = z
	.object({
		drainFailureCount: z.number().int().nonnegative(),
		expectedAttemptCount: z.number().int().positive(),
		lossyPaneReportCount: z.number().int().nonnegative(),
		missingPaneReportCount: z.number().int().nonnegative(),
		nativeBatchSequenceGapCount: z.number().int().nonnegative(),
		observedPaneReportCount: z.number().int().nonnegative(),
		optionalLossCount: z.number().int().nonnegative(),
		proofEligiblePaneReportCount: z.number().int().nonnegative(),
		requiredLossCount: z.number().int().nonnegative(),
		workerSequenceGapCount: z.number().int().nonnegative(),
	})
	.strict();

const launchReceiptSchema = z
	.object({
		attemptsByJourney: z
			.object({
				fileToReview: z.array(attemptSchema),
				firstFile: z.array(attemptSchema),
				firstReview: z.array(attemptSchema),
				reviewToFile: z.array(attemptSchema),
			})
			.strict(),
		launchId: z.string().min(1),
		telemetryProof: nativeTelemetryProofSchema,
	})
	.strict();

const nativeInputSchema = z
	.object({
		launches: z
			.array(
				z
					.object({
						launchId: z.string().min(1),
						receipt: launchReceiptSchema,
						telemetryMarker: z.string().min(1),
						telemetryServiceVersion: z.string().min(1),
					})
					.strict(),
			)
			.length(3),
		sourceHead: z.string().regex(/^[0-9a-f]{40}$/u),
		worktreeHash: z.string().min(1),
	})
	.strict();

const journeys = [
	'firstFile',
	'firstReview',
	'fileToReview',
	'reviewToFile',
] as const satisfies readonly BridgeCompleteJourney[];

export interface BridgeCompleteJourneyNativeReductionResult {
	readonly cohorts: readonly BridgeCompleteJourneyCohort[];
	readonly diagnosticOnly: boolean;
	readonly reductions: readonly BridgeCompleteJourneyCohortReduction[] | null;
}

export function reduceBridgeCompleteJourneyNativeInput(
	value: unknown,
): BridgeCompleteJourneyNativeReductionResult {
	const input = nativeInputSchema.parse(value);
	const launchIds = new Set<string>();
	const telemetryMarkers = new Set<string>();
	const attemptCounts = new Set<number>();
	for (const launch of input.launches) {
		if (
			launchIds.has(launch.launchId) ||
			launch.receipt.launchId !== launch.launchId ||
			telemetryMarkers.has(launch.telemetryMarker)
		) {
			throw new Error('Native complete journey launch identities must be unique and exact.');
		}
		launchIds.add(launch.launchId);
		telemetryMarkers.add(launch.telemetryMarker);
		const expectedPaneReportCount = journeys.reduce((total, journey): number => {
			attemptCounts.add(launch.receipt.attemptsByJourney[journey].length);
			return total + launch.receipt.attemptsByJourney[journey].length;
		}, 0);
		if (launch.receipt.telemetryProof.expectedAttemptCount !== expectedPaneReportCount) {
			throw new Error(
				`${launch.launchId}: telemetry proof does not cover every native pane attempt.`,
			);
		}
	}
	if (attemptCounts.size !== 1) {
		throw new Error('Native complete journey launches must use one exact attempt count.');
	}
	const attemptCount = attemptCounts.values().next().value ?? 0;
	if (attemptCount <= 0) {
		throw new Error('Native complete journey launches require at least one attempt.');
	}
	const diagnosticOnly = attemptCount < bridgeCompleteJourneyMinimumAttemptsPerLaunch;

	const cohorts = journeys.map(
		(journey): BridgeCompleteJourneyCohort => ({
			carrier: 'native',
			journey,
			launches: input.launches.map((launch) => ({
				attempts: launch.receipt.attemptsByJourney[journey].map(normalizeAttempt),
				evidence: {
					cacheState: 'fresh-isolated-app-data',
					fixtureIdentity: 'pinned-real-worktree',
					sourceHead: input.sourceHead,
					telemetry: nativeTelemetryEvidence(launch.receipt.telemetryProof),
					telemetryMarker: launch.telemetryMarker,
					telemetryServiceVersion: launch.telemetryServiceVersion,
					worktreeHash: input.worktreeHash,
				},
				launchId: launch.launchId,
			})),
		}),
	);
	return {
		cohorts,
		diagnosticOnly,
		reductions: diagnosticOnly ? null : cohorts.map(reduceBridgeCompleteJourneyCohort),
	};
}

function normalizeAttempt(attempt: z.infer<typeof attemptSchema>): BridgeCompleteJourneyAttempt {
	if (attempt.outcome === 'failed') {
		const phases = attempt.phaseCompletionElapsedMilliseconds;
		return {
			attemptId: attempt.attemptId,
			durationMilliseconds: attempt.durationMilliseconds,
			failureReason: attempt.failureReason,
			outcome: 'failed',
			phaseCompletionElapsedMilliseconds: {
				...(phases.commitPaint === undefined ? {} : { commitPaint: phases.commitPaint }),
				...(phases.handshakeWorker === undefined
					? {}
					: { handshakeWorker: phases.handshakeWorker }),
				...(phases.pageApplication === undefined
					? {}
					: { pageApplication: phases.pageApplication }),
				...(phases.selectionContent === undefined
					? {}
					: { selectionContent: phases.selectionContent }),
				...(phases.sourceMetadata === undefined ? {} : { sourceMetadata: phases.sourceMetadata }),
			},
		};
	}
	const phases = attempt.phaseCompletionElapsedMilliseconds;
	return {
		attemptId: attempt.attemptId,
		durationMilliseconds: attempt.durationMilliseconds,
		outcome: 'succeeded',
		phaseCompletionElapsedMilliseconds: {
			commitPaint: phases.commitPaint,
			handshakeWorker: phases.handshakeWorker,
			pageApplication: phases.pageApplication,
			selectionContent: phases.selectionContent,
			sourceMetadata: phases.sourceMetadata,
		},
	};
}

function nativeTelemetryEvidence(
	proof: z.infer<typeof nativeTelemetryProofSchema>,
): BridgeCompleteJourneyTelemetryEvidence {
	return {
		...proof,
		kind: 'native-pane-reports',
	};
}

async function main(): Promise<void> {
	const { inputPath, outputPath } = parseArguments(process.argv.slice(2));
	const input: unknown = JSON.parse(await readFile(inputPath, 'utf8'));
	const result = reduceBridgeCompleteJourneyNativeInput(input);
	await mkdir(dirname(outputPath), { recursive: true });
	await writeFile(outputPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o600 });
	if (result.reductions?.some((reduction): boolean => !reduction.satisfied) === true) {
		process.exitCode = 1;
	}
}

function parseArguments(arguments_: readonly string[]): {
	readonly inputPath: string;
	readonly outputPath: string;
} {
	let inputPath = '';
	let outputPath = '';
	for (let index = 0; index < arguments_.length; index += 1) {
		const argument = arguments_[index];
		const value = arguments_[index + 1];
		if ((argument === '--input' || argument === '--output') && value !== undefined) {
			if (argument === '--input') inputPath = resolve(value);
			else outputPath = resolve(value);
			index += 1;
			continue;
		}
		throw new Error(`Unknown or incomplete argument: ${argument ?? '<missing>'}`);
	}
	if (inputPath.length === 0 || outputPath.length === 0) {
		throw new Error(
			'Usage: reduce-bridge-complete-journey-native.ts --input <path> --output <path>',
		);
	}
	return { inputPath, outputPath };
}

const invokedPath = process.argv[1];
if (invokedPath !== undefined && import.meta.url === pathToFileURL(resolve(invokedPath)).href) {
	await main();
}
