import { z } from 'zod';

import {
	bridgeLocalFirstProofExternalEvidenceSchema,
	bridgeLocalFirstProofFailureKinds,
	bridgeLocalFirstProofInteractionEvidenceSchema,
	bridgeLocalFirstProofTelemetryProofSchema,
	validateBridgeLocalFirstProofExternalEvidence,
	validateBridgeLocalFirstProofInternalEvidence,
	type BridgeLocalFirstProofExpectedEndpoint,
	type BridgeLocalFirstValidatedFixtureOracle,
} from './bridge-local-first-proof-evidence.ts';
import {
	bridgeLocalFirstProofApplicabilityByCellId,
	bridgeLocalFirstProofCells,
	bridgeLocalFirstProofFamilies,
	bridgeLocalFirstProofMinimumMeasuredAttemptCount,
	bridgeLocalFirstProofMinimumMeasuredAttemptsPerLaunch,
	bridgeLocalFirstProofRequiredCellCount,
	bridgeLocalFirstProofRequiredLaunchCount,
	bridgeLocalFirstProofRequiredLaunchesPerCell,
	bridgeLocalFirstProofRuntimes,
	bridgeLocalFirstProofSourceCacheStates,
	bridgeLocalFirstProofTelemetryStates,
	type BridgeLocalFirstProofCellContract,
	type BridgeLocalFirstProofCellApplicability,
	type BridgeLocalFirstProofRuntime,
	type BridgeLocalFirstProofTelemetryState,
} from './bridge-local-first-proof-manifest.ts';
import {
	bridgeLocalFirstProofProcessInstanceId,
	bridgeLocalFirstProofRunIdentitySchema,
	bridgeLocalFirstProofSha256Schema,
	validateBridgeLocalFirstProofRunIdentitySelfConsistency,
	type BridgeLocalFirstProofRunIdentity,
} from './bridge-local-first-proof-provenance.ts';

export {
	bridgeLocalFirstProofApplicabilityByCellId,
	bridgeLocalFirstProofAttemptDeadlineMilliseconds,
	bridgeLocalFirstProofCellId,
	bridgeLocalFirstProofCells,
	bridgeLocalFirstProofInternalSlo,
	bridgeLocalFirstProofManifestRows,
	bridgeLocalFirstProofMinimumMeasuredAttemptCount,
	bridgeLocalFirstProofMinimumMeasuredAttemptsPerLaunch,
	bridgeLocalFirstProofP99BudgetMilliseconds,
	bridgeLocalFirstProofRequiredCellCount,
	bridgeLocalFirstProofRequiredLaunchCount,
	bridgeLocalFirstProofRequiredLaunchesPerCell,
	bridgeLocalFirstProofRuntimes,
	bridgeLocalFirstProofTelemetryStates,
	type BridgeLocalFirstProofCellApplicability,
	type BridgeLocalFirstProofCachePreparationRequirement,
	type BridgeLocalFirstProofCellContract,
	type BridgeLocalFirstProofEndpointKind,
	type BridgeLocalFirstProofFamily,
	type BridgeLocalFirstProofManifestRow,
	type BridgeLocalFirstProofRuntime,
	type BridgeLocalFirstProofSourceCacheState,
	type BridgeLocalFirstProofTelemetryState,
} from './bridge-local-first-proof-manifest.ts';
export {
	bridgeLocalFirstProofProcessInstanceId,
	bridgeLocalFirstProofRunFactsSchema,
	bridgeLocalFirstProofRunIdentityFingerprint,
	bridgeLocalFirstProofRunIdentitySchema,
	bridgeLocalFirstProofRunManifestHash,
	type BridgeLocalFirstProofRunFacts,
	type BridgeLocalFirstProofRunIdentity,
} from './bridge-local-first-proof-provenance.ts';

export const bridgeLocalFirstProofRequiredLifecycleStages = [
	'process_started',
	'runtime_ready',
	'warmup_completed',
	'measured_actions_completed',
	'telemetry_settled',
	'process_exited',
] as const;

export const bridgeLocalFirstProofLifecycleDeadlineMilliseconds = Object.freeze({
	process_started: 10_000,
	runtime_ready: 10_000,
	warmup_completed: 1_000,
	measured_actions_completed: 120_000,
	telemetry_settled: 10_000,
	process_exited: 10_000,
} satisfies Record<(typeof bridgeLocalFirstProofRequiredLifecycleStages)[number], number>);

const nonemptyIdentitySchema = z.string().min(1);
const finiteNonnegativeDurationSchema = z.number().finite().nonnegative();
const bridgeLocalFirstProofFamilySchema = z.enum(bridgeLocalFirstProofFamilies);
const bridgeLocalFirstProofSourceCacheStateSchema = z.enum(bridgeLocalFirstProofSourceCacheStates);
const bridgeLocalFirstProofRuntimeSchema = z.enum(bridgeLocalFirstProofRuntimes);
const bridgeLocalFirstProofTelemetryStateSchema = z.enum(bridgeLocalFirstProofTelemetryStates);
const bridgeLocalFirstProofLifecycleStageSchema = z.enum(
	bridgeLocalFirstProofRequiredLifecycleStages,
);

const bridgeLocalFirstProofCellIdentitySchema = z
	.object({
		runId: nonemptyIdentitySchema,
		cellId: nonemptyIdentitySchema,
		manifestRowId: nonemptyIdentitySchema,
		family: bridgeLocalFirstProofFamilySchema,
		sourceCacheState: bridgeLocalFirstProofSourceCacheStateSchema,
		runtime: bridgeLocalFirstProofRuntimeSchema,
		telemetryState: bridgeLocalFirstProofTelemetryStateSchema,
	})
	.strict()
	.readonly();

const bridgeLocalFirstProofRuntimeProcessIdentitySchema = z.discriminatedUnion('runtime', [
	z
		.object({
			runtime: z.literal('controlled_dev_chromium'),
			browserProcessId: z.number().int().positive(),
			browserContextId: nonemptyIdentitySchema,
			devServerOrigin: z.url(),
		})
		.strict()
		.readonly(),
	z
		.object({
			runtime: z.literal('packaged_wkwebview'),
			appProcessId: z.number().int().positive(),
			bundleIdentifier: nonemptyIdentitySchema,
			bundleHash: bridgeLocalFirstProofSha256Schema,
		})
		.strict()
		.readonly(),
]);

const bridgeLocalFirstProofLaunchIdentitySchema = z
	.object({
		runId: nonemptyIdentitySchema,
		runIdentityFingerprint: bridgeLocalFirstProofSha256Schema,
		runManifestHash: bridgeLocalFirstProofSha256Schema,
		cellId: nonemptyIdentitySchema,
		launchId: nonemptyIdentitySchema,
		launchIndex: z.number().int().nonnegative(),
		processId: z.number().int().positive(),
		processStartToken: z.string().trim().min(1),
		executableSha256: bridgeLocalFirstProofSha256Schema,
		processInstanceId: nonemptyIdentitySchema,
		runtimeProcessIdentity: bridgeLocalFirstProofRuntimeProcessIdentitySchema,
	})
	.strict()
	.readonly();

const bridgeLocalFirstProofAttemptIdentitySchema = z
	.object({
		runId: nonemptyIdentitySchema,
		cellId: nonemptyIdentitySchema,
		launchId: nonemptyIdentitySchema,
		attemptId: nonemptyIdentitySchema,
		attemptIndex: z.number().int().nonnegative(),
		interactionId: nonemptyIdentitySchema,
		oracleEntryId: nonemptyIdentitySchema,
	})
	.strict()
	.readonly();

const bridgeLocalFirstProofSucceededAttemptSchema = z
	.object({
		identity: bridgeLocalFirstProofAttemptIdentitySchema,
		outcome: z.literal('succeeded'),
		durationMilliseconds: finiteNonnegativeDurationSchema,
		deadlineDurationMilliseconds: z.number().finite().positive(),
	})
	.strict();

const bridgeLocalFirstProofFailedAttemptSchema = z
	.object({
		identity: bridgeLocalFirstProofAttemptIdentitySchema,
		outcome: z.literal('failed'),
		failureKind: z.enum(bridgeLocalFirstProofFailureKinds),
		deadlineDurationMilliseconds: z.number().finite().positive(),
	})
	.strict();

export const bridgeLocalFirstProofAttemptSchema = z
	.discriminatedUnion('outcome', [
		bridgeLocalFirstProofSucceededAttemptSchema,
		bridgeLocalFirstProofFailedAttemptSchema,
	])
	.readonly();

const bridgeLocalFirstProofLifecycleStageRecordSchema = z
	.object({
		stage: bridgeLocalFirstProofLifecycleStageSchema,
		completion: z.literal('completed'),
		startedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		completedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
	})
	.strict()
	.readonly();

const bridgeLocalFirstProofWarmupSchema = z
	.discriminatedUnion('outcome', [
		z
			.object({
				interactionId: nonemptyIdentitySchema,
				oracleEntryId: nonemptyIdentitySchema,
				outcome: z.literal('succeeded'),
				durationMilliseconds: finiteNonnegativeDurationSchema,
				deadlineDurationMilliseconds: z.number().finite().positive(),
				externalEvidence: bridgeLocalFirstProofExternalEvidenceSchema,
			})
			.strict(),
		z
			.object({
				interactionId: nonemptyIdentitySchema,
				oracleEntryId: nonemptyIdentitySchema,
				outcome: z.literal('failed'),
				failureKind: z.enum(bridgeLocalFirstProofFailureKinds),
				deadlineDurationMilliseconds: z.number().finite().positive(),
				externalEvidence: bridgeLocalFirstProofExternalEvidenceSchema,
			})
			.strict(),
	])
	.readonly();

const bridgeLocalFirstProofLaunchSchema = z
	.object({
		identity: bridgeLocalFirstProofLaunchIdentitySchema,
		warmup: bridgeLocalFirstProofWarmupSchema,
		lifecycleStages: z.array(bridgeLocalFirstProofLifecycleStageRecordSchema).readonly(),
		attemptedActionCount: z.number().int().nonnegative(),
		attempts: z.array(bridgeLocalFirstProofAttemptSchema).readonly(),
		interactionEvidence: z.array(bridgeLocalFirstProofInteractionEvidenceSchema).readonly(),
		telemetryProof: bridgeLocalFirstProofTelemetryProofSchema,
	})
	.strict()
	.readonly();

const bridgeLocalFirstProofCellSchema = z
	.object({
		identity: bridgeLocalFirstProofCellIdentitySchema,
		launches: z.array(bridgeLocalFirstProofLaunchSchema).readonly(),
	})
	.strict()
	.readonly();

export const bridgeLocalFirstProofCohortSchema = z
	.object({
		schemaVersion: z.literal(1),
		runIdentity: bridgeLocalFirstProofRunIdentitySchema,
		cells: z.array(bridgeLocalFirstProofCellSchema).readonly(),
	})
	.strict()
	.readonly();

export type BridgeLocalFirstProofAttemptInput = z.input<typeof bridgeLocalFirstProofAttemptSchema>;
export type BridgeLocalFirstProofCohortInput = z.input<typeof bridgeLocalFirstProofCohortSchema>;

type BridgeLocalFirstParsedProofCohort = z.output<typeof bridgeLocalFirstProofCohortSchema>;
type BridgeLocalFirstParsedLaunch =
	BridgeLocalFirstParsedProofCohort['cells'][number]['launches'][number];
const bridgeLocalFirstValidatedProofCohortBrand = Symbol('BridgeLocalFirstValidatedProofCohort');
export type BridgeLocalFirstValidatedProofCohort = BridgeLocalFirstParsedProofCohort & {
	readonly [bridgeLocalFirstValidatedProofCohortBrand]: true;
};

const expectedCellById: ReadonlyMap<string, BridgeLocalFirstProofCellContract> = new Map(
	bridgeLocalFirstProofCells.map((cell) => [cell.cellId, cell]),
);

const runIdentityScalarFields = [
	'runId',
	'headCommitSha',
	'dirtyStateHash',
	'packagedBundleHash',
	'fixtureId',
	'fixtureChecksum',
	'machineProfileHash',
	'pierreVersion',
	'workerMode',
	'runManifestHash',
	'runIdentityFingerprint',
] as const;

export function parseBridgeLocalFirstProofCohort(
	rawCohort: unknown,
	expectedRunIdentityInput: BridgeLocalFirstProofRunIdentity,
	fixtureOracle: BridgeLocalFirstValidatedFixtureOracle,
): BridgeLocalFirstValidatedProofCohort {
	const expectedRunIdentity =
		bridgeLocalFirstProofRunIdentitySchema.parse(expectedRunIdentityInput);
	const cohort = bridgeLocalFirstProofCohortSchema.parse(rawCohort);
	validateBridgeLocalFirstProofRunIdentitySelfConsistency(expectedRunIdentity);
	validateBridgeLocalFirstProofRunIdentitySelfConsistency(cohort.runIdentity);
	if (
		fixtureOracle.fixtureId !== expectedRunIdentity.fixtureId ||
		fixtureOracle.fixtureChecksum !== expectedRunIdentity.fixtureChecksum
	) {
		throw new Error('fixture oracle identity does not match immutable run identity');
	}
	validateRunIdentityFreshness(cohort.runIdentity, expectedRunIdentity);
	validateClosedCohort(cohort, fixtureOracle);
	return Object.freeze({
		...cohort,
		[bridgeLocalFirstValidatedProofCohortBrand]: true as const,
	});
}

function validateRunIdentityFreshness(
	actual: z.output<typeof bridgeLocalFirstProofRunIdentitySchema>,
	expected: z.output<typeof bridgeLocalFirstProofRunIdentitySchema>,
): void {
	for (const field of runIdentityScalarFields) {
		if (actual[field] !== expected[field]) {
			throw new Error(`stale run identity: ${field}`);
		}
	}
	for (const field of ['width', 'height', 'deviceScaleFactor'] as const) {
		if (actual.viewport[field] !== expected.viewport[field]) {
			throw new Error(`stale run identity: viewport.${field}`);
		}
	}
}

function validateClosedCohort(
	cohort: BridgeLocalFirstParsedProofCohort,
	fixtureOracle: BridgeLocalFirstValidatedFixtureOracle,
): void {
	if (cohort.cells.length !== bridgeLocalFirstProofRequiredCellCount) {
		throw new Error(
			`proof cohort must contain exactly ${bridgeLocalFirstProofRequiredCellCount} manifest cells, got ${cohort.cells.length}`,
		);
	}

	const seenCellIds = new Set<string>();
	const seenLaunchIds = new Set<string>();
	const seenProcessInstanceIds = new Set<string>();
	const seenAttemptIds = new Set<string>();
	const seenInteractionIds = new Set<string>();
	let launchCount = 0;
	let measuredAttemptCount = 0;

	for (const cell of cohort.cells) {
		const expectedCell = expectedCellById.get(cell.identity.cellId);
		if (seenCellIds.has(cell.identity.cellId)) {
			throw new Error(`duplicate cell identity: ${cell.identity.cellId}`);
		}
		seenCellIds.add(cell.identity.cellId);
		if (expectedCell === undefined) {
			throw new Error(`cell is outside closed manifest: ${cell.identity.cellId}`);
		}
		validateCellIdentity({ cell, expectedCell, runId: cohort.runIdentity.runId });
		validateCellLaunches({
			cell,
			expectedCell,
			fixtureOracle,
			runIdentity: cohort.runIdentity,
			seenAttemptIds,
			seenInteractionIds,
			seenLaunchIds,
			seenProcessInstanceIds,
		});
		launchCount += cell.launches.length;
		measuredAttemptCount += cell.launches.reduce(
			(count, launch) => count + launch.attempts.length,
			0,
		);
	}

	for (const expectedCell of bridgeLocalFirstProofCells) {
		if (!seenCellIds.has(expectedCell.cellId)) {
			throw new Error(`missing closed manifest cell: ${expectedCell.cellId}`);
		}
	}
	if (launchCount !== bridgeLocalFirstProofRequiredLaunchCount) {
		throw new Error(
			`proof cohort must contain exactly ${bridgeLocalFirstProofRequiredLaunchCount} fresh launches, got ${launchCount}`,
		);
	}
	if (measuredAttemptCount < bridgeLocalFirstProofMinimumMeasuredAttemptCount) {
		throw new Error(
			`proof cohort requires at least ${bridgeLocalFirstProofMinimumMeasuredAttemptCount} measured attempts, got ${measuredAttemptCount}`,
		);
	}
}

function validateCellIdentity(props: {
	readonly cell: BridgeLocalFirstParsedProofCohort['cells'][number];
	readonly expectedCell: BridgeLocalFirstProofCellContract;
	readonly runId: string;
}): void {
	const identity = props.cell.identity;
	if (identity.runId !== props.runId) {
		throw new Error(`cell identity does not match parent run: ${identity.cellId}`);
	}
	if (
		identity.manifestRowId !== props.expectedCell.manifestRowId ||
		identity.family !== props.expectedCell.family ||
		identity.sourceCacheState !== props.expectedCell.sourceCacheState ||
		identity.runtime !== props.expectedCell.runtime ||
		identity.telemetryState !== props.expectedCell.telemetryState
	) {
		throw new Error(`cell identity does not match closed manifest: ${identity.cellId}`);
	}
}

function validateCellLaunches(props: {
	readonly cell: BridgeLocalFirstParsedProofCohort['cells'][number];
	readonly expectedCell: BridgeLocalFirstProofCellContract;
	readonly fixtureOracle: BridgeLocalFirstValidatedFixtureOracle;
	readonly runIdentity: BridgeLocalFirstParsedProofCohort['runIdentity'];
	readonly seenAttemptIds: Set<string>;
	readonly seenInteractionIds: Set<string>;
	readonly seenLaunchIds: Set<string>;
	readonly seenProcessInstanceIds: Set<string>;
}): void {
	if (props.cell.launches.length !== bridgeLocalFirstProofRequiredLaunchesPerCell) {
		throw new Error(
			`${props.cell.identity.cellId}: expected exactly ${bridgeLocalFirstProofRequiredLaunchesPerCell} fresh launches, got ${props.cell.launches.length}`,
		);
	}
	const applicability = bridgeLocalFirstProofApplicabilityByCellId.get(props.cell.identity.cellId);
	if (applicability === undefined) {
		throw new Error(`${props.cell.identity.cellId}: missing closed applicability contract`);
	}
	const seenLaunchIndexes = new Set<number>();
	for (const launch of props.cell.launches) {
		validateLaunchIdentity({
			cellId: props.cell.identity.cellId,
			launch,
			runIdentity: props.runIdentity,
			runtime: props.cell.identity.runtime,
			seenLaunchIds: props.seenLaunchIds,
			seenProcessInstanceIds: props.seenProcessInstanceIds,
		});
		if (
			launch.identity.launchIndex >= bridgeLocalFirstProofRequiredLaunchesPerCell ||
			seenLaunchIndexes.has(launch.identity.launchIndex)
		) {
			throw new Error(
				`${props.cell.identity.cellId}: invalid or duplicate launch index ${launch.identity.launchIndex}`,
			);
		}
		seenLaunchIndexes.add(launch.identity.launchIndex);
		validateLifecycleStages(launch);
		validateWarmup({
			applicability,
			fixtureChecksum: props.runIdentity.fixtureChecksum,
			fixtureOracle: props.fixtureOracle,
			launch,
			manifestRowId: props.expectedCell.manifestRowId,
			runtime: props.cell.identity.runtime,
			seenInteractionIds: props.seenInteractionIds,
		});
		validateAttemptLedger({
			applicability,
			cellId: props.cell.identity.cellId,
			expectedAttemptDeadlineMilliseconds: props.expectedCell.attemptDeadlineMilliseconds,
			fixtureChecksum: props.runIdentity.fixtureChecksum,
			fixtureOracle: props.fixtureOracle,
			launch,
			manifestRowId: props.expectedCell.manifestRowId,
			runId: props.runIdentity.runId,
			seenAttemptIds: props.seenAttemptIds,
			seenInteractionIds: props.seenInteractionIds,
			runtime: props.cell.identity.runtime,
			telemetryState: props.cell.identity.telemetryState,
		});
		validateTelemetryProof(launch, props.cell.identity.telemetryState);
	}
}

function validateLaunchIdentity(props: {
	readonly cellId: string;
	readonly launch: BridgeLocalFirstParsedProofCohort['cells'][number]['launches'][number];
	readonly runIdentity: BridgeLocalFirstParsedProofCohort['runIdentity'];
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly seenLaunchIds: Set<string>;
	readonly seenProcessInstanceIds: Set<string>;
}): void {
	const identity = props.launch.identity;
	if (
		identity.runId !== props.runIdentity.runId ||
		identity.runIdentityFingerprint !== props.runIdentity.runIdentityFingerprint ||
		identity.runManifestHash !== props.runIdentity.runManifestHash ||
		identity.cellId !== props.cellId
	) {
		throw new Error(`launch identity does not match parent cell: ${identity.launchId}`);
	}
	if (identity.runtimeProcessIdentity.runtime !== props.runtime) {
		throw new Error(`launch runtime identity does not match parent cell: ${identity.launchId}`);
	}
	if (
		identity.runtimeProcessIdentity.runtime === 'controlled_dev_chromium' &&
		identity.runtimeProcessIdentity.browserProcessId !== identity.processId
	) {
		throw new Error(`launch browser process identity mismatch: ${identity.launchId}`);
	}
	if (
		identity.runtimeProcessIdentity.runtime === 'packaged_wkwebview' &&
		(identity.runtimeProcessIdentity.appProcessId !== identity.processId ||
			identity.runtimeProcessIdentity.bundleHash !== props.runIdentity.packagedBundleHash)
	) {
		throw new Error(`launch packaged app identity mismatch: ${identity.launchId}`);
	}
	if (
		identity.processInstanceId !==
		bridgeLocalFirstProofProcessInstanceId({
			executableSha256: identity.executableSha256,
			processId: identity.processId,
			processStartToken: identity.processStartToken,
		})
	) {
		throw new Error(
			`${identity.launchId}: process instance identity does not match concrete launch evidence`,
		);
	}
	if (props.seenLaunchIds.has(identity.launchId)) {
		throw new Error(`duplicate launch identity: ${identity.launchId}`);
	}
	props.seenLaunchIds.add(identity.launchId);
	if (props.seenProcessInstanceIds.has(identity.processInstanceId)) {
		throw new Error(`duplicate process instance identity: ${identity.processInstanceId}`);
	}
	props.seenProcessInstanceIds.add(identity.processInstanceId);
}

function validateLifecycleStages(
	launch: BridgeLocalFirstParsedProofCohort['cells'][number]['launches'][number],
): void {
	if (launch.lifecycleStages.length !== bridgeLocalFirstProofRequiredLifecycleStages.length) {
		throw new Error(`${launch.identity.launchId}: missing required lifecycle stage`);
	}
	let previousCompletionTime = Number.NEGATIVE_INFINITY;
	for (const [
		stageIndex,
		expectedStage,
	] of bridgeLocalFirstProofRequiredLifecycleStages.entries()) {
		const actualStage = launch.lifecycleStages[stageIndex];
		if (actualStage?.stage !== expectedStage) {
			throw new Error(
				`${launch.identity.launchId}: missing required lifecycle stage ${expectedStage}`,
			);
		}
		if (stageIndex > 0 && actualStage.startedAtMonotonicMilliseconds !== previousCompletionTime) {
			throw new Error(
				`${launch.identity.launchId}: lifecycle stage does not chain to previous evidence`,
			);
		}
		if (actualStage.startedAtMonotonicMilliseconds < previousCompletionTime) {
			throw new Error(`${launch.identity.launchId}: lifecycle stages are not monotonic`);
		}
		const elapsedDurationMilliseconds =
			actualStage.completedAtMonotonicMilliseconds - actualStage.startedAtMonotonicMilliseconds;
		if (elapsedDurationMilliseconds < 0) {
			throw new Error(`${launch.identity.launchId}: lifecycle stage completed before it started`);
		}
		const stageDeadlineMilliseconds =
			bridgeLocalFirstProofLifecycleDeadlineMilliseconds[expectedStage];
		if (elapsedDurationMilliseconds > stageDeadlineMilliseconds) {
			throw new Error(
				`${launch.identity.launchId}: ${expectedStage} exceeded its ${stageDeadlineMilliseconds} ms lifecycle deadline`,
			);
		}
		previousCompletionTime = actualStage.completedAtMonotonicMilliseconds;
	}
}

function validateWarmup(props: {
	readonly applicability: BridgeLocalFirstProofCellApplicability;
	readonly fixtureChecksum: string;
	readonly fixtureOracle: BridgeLocalFirstValidatedFixtureOracle;
	readonly launch: BridgeLocalFirstParsedLaunch;
	readonly manifestRowId: string;
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly seenInteractionIds: Set<string>;
}): void {
	const warmup = props.launch.warmup;
	if (props.seenInteractionIds.has(warmup.interactionId)) {
		throw new Error(
			`${props.launch.identity.launchId}: globally reused warmup interaction identity`,
		);
	}
	props.seenInteractionIds.add(warmup.interactionId);
	if (
		warmup.deadlineDurationMilliseconds !==
		bridgeLocalFirstProofLifecycleDeadlineMilliseconds.warmup_completed
	) {
		throw new Error(`${props.launch.identity.launchId}: warmup deadline mismatch`);
	}
	const expectedEndpoint = expectedEndpointForAction({
		actionIndex: 'warmup',
		fixtureOracle: props.fixtureOracle,
		manifestRowId: props.manifestRowId,
		oracleEntryId: warmup.oracleEntryId,
	});
	validateBridgeLocalFirstProofExternalEvidence({
		applicability: props.applicability,
		attempt: warmup,
		evidence: warmup.externalEvidence,
		expectedEndpoint,
		interactionId: warmup.interactionId,
		runtime: props.runtime,
	});
	if (warmup.outcome !== 'succeeded') {
		throw new Error(`${props.launch.identity.launchId}: warmup correctness failed`);
	}
	const warmupStage = props.launch.lifecycleStages[2];
	if (
		warmupStage?.stage !== 'warmup_completed' ||
		warmup.externalEvidence.runtimeTiming.stimulusAtMonotonicMilliseconds <
			warmupStage.startedAtMonotonicMilliseconds ||
		warmup.externalEvidence.runtimeTiming.endpointObservedAtMonotonicMilliseconds >
			warmupStage.completedAtMonotonicMilliseconds
	) {
		throw new Error(
			`${props.launch.identity.launchId}: warmup evidence is outside lifecycle window`,
		);
	}
}

function validateAttemptLedger(props: {
	readonly applicability: BridgeLocalFirstProofCellApplicability;
	readonly cellId: string;
	readonly expectedAttemptDeadlineMilliseconds: number;
	readonly fixtureChecksum: string;
	readonly fixtureOracle: BridgeLocalFirstValidatedFixtureOracle;
	readonly launch: BridgeLocalFirstParsedProofCohort['cells'][number]['launches'][number];
	readonly manifestRowId: string;
	readonly runId: string;
	readonly seenAttemptIds: Set<string>;
	readonly seenInteractionIds: Set<string>;
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly telemetryState: BridgeLocalFirstProofTelemetryState;
}): void {
	const launch = props.launch;
	if (launch.attemptedActionCount < bridgeLocalFirstProofMinimumMeasuredAttemptsPerLaunch) {
		throw new Error(
			`${launch.identity.launchId}: requires at least ${bridgeLocalFirstProofMinimumMeasuredAttemptsPerLaunch} measured attempts`,
		);
	}
	if (launch.attempts.length !== launch.attemptedActionCount) {
		throw new Error(
			`${launch.identity.launchId}: attempt ledger expected ${launch.attemptedActionCount} terminal attempts, got ${launch.attempts.length}`,
		);
	}
	for (const [attemptIndex, attempt] of launch.attempts.entries()) {
		const identity = attempt.identity;
		if (
			identity.runId !== props.runId ||
			identity.cellId !== props.cellId ||
			identity.launchId !== launch.identity.launchId ||
			identity.attemptIndex !== attemptIndex
		) {
			throw new Error(`attempt identity does not match parent launch: ${identity.attemptId}`);
		}
		if (props.seenAttemptIds.has(identity.attemptId)) {
			throw new Error(`duplicate attempt identity: ${identity.attemptId}`);
		}
		props.seenAttemptIds.add(identity.attemptId);
		if (props.seenInteractionIds.has(identity.interactionId)) {
			throw new Error(
				`${launch.identity.launchId}: globally reused interaction identity ${identity.interactionId}`,
			);
		}
		props.seenInteractionIds.add(identity.interactionId);
		if (attempt.deadlineDurationMilliseconds !== props.expectedAttemptDeadlineMilliseconds) {
			throw new Error(
				`${launch.identity.launchId}: attempt deadline must equal ${props.expectedAttemptDeadlineMilliseconds} ms`,
			);
		}
	}
	validateInteractionEvidence({
		applicability: props.applicability,
		fixtureChecksum: props.fixtureChecksum,
		fixtureOracle: props.fixtureOracle,
		launch,
		manifestRowId: props.manifestRowId,
		runtime: props.runtime,
		telemetryState: props.telemetryState,
	});
}

function validateInteractionEvidence(props: {
	readonly applicability: BridgeLocalFirstProofCellApplicability;
	readonly fixtureChecksum: string;
	readonly fixtureOracle: BridgeLocalFirstValidatedFixtureOracle;
	readonly launch: BridgeLocalFirstParsedLaunch;
	readonly manifestRowId: string;
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly telemetryState: BridgeLocalFirstProofTelemetryState;
}): void {
	const { launch } = props;
	if (launch.interactionEvidence.length !== launch.attempts.length) {
		throw new Error(`${launch.identity.launchId}: interaction evidence count mismatch`);
	}
	const measuredActionsStage = launch.lifecycleStages[3];
	if (measuredActionsStage?.stage !== 'measured_actions_completed') {
		throw new Error(`${launch.identity.launchId}: missing measured action lifecycle window`);
	}
	for (const [attemptIndex, attempt] of launch.attempts.entries()) {
		const evidence = launch.interactionEvidence[attemptIndex];
		if (evidence === undefined || evidence.interactionId !== attempt.identity.interactionId) {
			throw new Error(`${launch.identity.launchId}: interaction evidence identity mismatch`);
		}
		const expectedEndpoint = expectedEndpointForAction({
			actionIndex: attemptIndex,
			fixtureOracle: props.fixtureOracle,
			manifestRowId: props.manifestRowId,
			oracleEntryId: attempt.identity.oracleEntryId,
		});
		validateBridgeLocalFirstProofExternalEvidence({
			applicability: props.applicability,
			attempt,
			evidence: evidence.external,
			expectedEndpoint,
			interactionId: attempt.identity.interactionId,
			runtime: props.runtime,
		});
		if (
			evidence.external.runtimeTiming.stimulusAtMonotonicMilliseconds <
				measuredActionsStage.startedAtMonotonicMilliseconds ||
			evidence.external.runtimeTiming.endpointObservedAtMonotonicMilliseconds >
				measuredActionsStage.completedAtMonotonicMilliseconds
		) {
			throw new Error(`${attempt.identity.attemptId}: action is outside measured lifecycle window`);
		}
		validateBridgeLocalFirstProofInternalEvidence({
			applicability: props.applicability,
			evidence: evidence.internal,
			interactionCompletedAtMonotonicMilliseconds:
				evidence.external.runtimeTiming.endpointObservedAtMonotonicMilliseconds,
			interactionId: attempt.identity.interactionId,
			interactionStartedAtMonotonicMilliseconds:
				evidence.external.runtimeTiming.stimulusAtMonotonicMilliseconds,
			telemetryState: props.telemetryState,
		});
	}
}

function expectedEndpointForAction(props: {
	readonly actionIndex: 'warmup' | number;
	readonly fixtureOracle: BridgeLocalFirstValidatedFixtureOracle;
	readonly manifestRowId: string;
	readonly oracleEntryId: string;
}): BridgeLocalFirstProofExpectedEndpoint {
	const expectedOracleEntryId = props.fixtureOracle.oracleEntryIdFor({
		actionIndex: props.actionIndex,
		manifestRowId: props.manifestRowId,
	});
	if (props.oracleEntryId !== expectedOracleEntryId) {
		throw new Error(`${props.oracleEntryId}: fixture oracle action identity mismatch`);
	}
	return props.fixtureOracle.expectedEndpointFor(props.oracleEntryId);
}

function validateTelemetryProof(
	launch: BridgeLocalFirstParsedProofCohort['cells'][number]['launches'][number],
	telemetryState: BridgeLocalFirstProofTelemetryState,
): void {
	const telemetryProof = launch.telemetryProof;
	if (telemetryState === 'off') {
		if (telemetryProof.mode !== 'off') {
			throw new Error(`${launch.identity.launchId}: telemetry-off launch constructed telemetry`);
		}
		return;
	}
	if (telemetryProof.mode !== 'on') {
		throw new Error(`${launch.identity.launchId}: telemetry-on launch has no drain proof`);
	}
	for (const lossRange of telemetryProof.lossRanges) {
		if (lossRange.lastMissingSequence < lossRange.firstMissingSequence) {
			throw new Error(`${launch.identity.launchId}: telemetry loss range is reversed`);
		}
		if (lossRange.required) {
			throw new Error(`${launch.identity.launchId}: required telemetry loss`);
		}
	}
	const events = launch.interactionEvidence.flatMap((evidence) =>
		evidence.internal.mode === 'on' ? evidence.internal.events : [],
	);
	const expectedHighWatermarks = new Map<'comm' | 'main', number>();
	const finalProducerTimestamps = new Map<'comm' | 'main', number>();
	for (const producer of ['main', 'comm'] as const) {
		const producerEvents = events
			.filter((event) => event.producer === producer)
			.toSorted((left, right) => left.producerSequence - right.producerSequence);
		for (const [eventIndex, event] of producerEvents.entries()) {
			if (event.producerSequence !== eventIndex + 1) {
				throw new Error(`${launch.identity.launchId}: ${producer} telemetry sequence gap`);
			}
		}
		expectedHighWatermarks.set(producer, producerEvents.length);
		finalProducerTimestamps.set(
			producer,
			producerEvents.at(-1)?.observedAtMonotonicMilliseconds ?? 0,
		);
	}
	const telemetryStage = launch.lifecycleStages[4];
	if (telemetryStage?.stage !== 'telemetry_settled') {
		throw new Error(`${launch.identity.launchId}: missing telemetry settlement lifecycle`);
	}
	const seenDrainProducers = new Set<string>();
	for (const drainReceipt of telemetryProof.drainReceipts) {
		if (seenDrainProducers.has(drainReceipt.producer)) {
			throw new Error(`${launch.identity.launchId}: duplicate telemetry drain receipt`);
		}
		seenDrainProducers.add(drainReceipt.producer);
		if (
			drainReceipt.acknowledgedProducerSequence !==
			expectedHighWatermarks.get(drainReceipt.producer)
		) {
			throw new Error(`${launch.identity.launchId}: telemetry drain high-watermark mismatch`);
		}
		if (
			drainReceipt.drainedAtMonotonicMilliseconds <
				(finalProducerTimestamps.get(drainReceipt.producer) ?? 0) ||
			drainReceipt.drainedAtMonotonicMilliseconds < telemetryStage.startedAtMonotonicMilliseconds ||
			drainReceipt.drainedAtMonotonicMilliseconds > telemetryStage.completedAtMonotonicMilliseconds
		) {
			throw new Error(`${launch.identity.launchId}: telemetry drain is outside settlement window`);
		}
	}
	if (seenDrainProducers.size !== 2) {
		throw new Error(
			`${launch.identity.launchId}: telemetry-on launch requires both drain receipts`,
		);
	}
}
