import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

import {
	bridgeLocalFirstProofApplicabilityByCellId,
	bridgeLocalFirstProofCells,
	bridgeLocalFirstProofManifestRows,
	bridgeLocalFirstProofMinimumMeasuredAttemptCount,
	bridgeLocalFirstProofProcessInstanceId,
	bridgeLocalFirstProofRequiredCellCount,
	bridgeLocalFirstProofRequiredLaunchCount,
	bridgeLocalFirstProofRequiredLifecycleStages,
	bridgeLocalFirstProofRunIdentityFingerprint,
	bridgeLocalFirstProofRunManifestHash,
	parseBridgeLocalFirstProofCohort as parseBridgeLocalFirstProofCohortWithOracle,
	type BridgeLocalFirstProofAttemptInput,
	type BridgeLocalFirstProofCellContract,
	type BridgeLocalFirstProofCohortInput,
	type BridgeLocalFirstProofRunIdentity,
} from './bridge-local-first-proof-contract.ts';
import {
	bridgeLocalFirstProofOracleEntryId,
	bridgeLocalFirstProofProducerForStage,
	bridgeLocalFirstProofRequiredInternalStagesForApplicability,
	parseBridgeLocalFirstProofFixtureOracle,
	type BridgeLocalFirstProofExpectedEndpoint,
	type BridgeLocalFirstProofFailureKind,
	type BridgeLocalFirstProofFixtureOracleInput,
	type BridgeLocalFirstValidatedFixtureOracle,
} from './bridge-local-first-proof-evidence.ts';
import { reduceBridgeLocalFirstProofCohort as reduceBridgeLocalFirstProofCohortWithOracle } from './bridge-local-first-proof-reducer.ts';
import { bridgeLocalFirstProofAggregateManifestFingerprint } from './verify-bridge-local-first-performance.ts';

const expectedManifestRowIds = [
	'review-selection-feedback--fresh-display',
	'review-selection-feedback--worker-cache',
	'review-selection-feedback--cold-miss',
	'review-selected-readable--fresh-display',
	'review-selected-readable--worker-cache',
	'review-selected-readable--cold-miss',
	'review-terminal-availability--cached-terminal',
	'review-terminal-availability--cold-terminal',
	'review-rail-scroll--resident-rows',
	'review-code-view-scroll--resident-window',
	'review-code-view-scroll--continuation-miss',
	'file-selection-feedback--fresh-display',
	'file-selection-feedback--worker-cache',
	'file-selection-feedback--cold-miss',
	'file-selected-readable--fresh-display',
	'file-selected-readable--worker-cache',
	'file-selected-readable--cold-miss',
	'file-terminal-availability--cached-terminal',
	'file-terminal-availability--cold-terminal',
	'file-rail-scroll--resident-rows',
	'file-content-scroll--resident-prefix',
] as const;
const runFacts = {
	runId: 'run-honesty-red',
	headCommitSha: '0123456789abcdef0123456789abcdef01234567',
	dirtyStateHash: 'a'.repeat(64),
	packagedBundleHash: 'b'.repeat(64),
	fixtureId: 'fixture-v1',
	fixtureChecksum: 'c'.repeat(64),
	viewport: { width: 1728, height: 972, deviceScaleFactor: 2 },
	machineProfileHash: 'd'.repeat(64),
	pierreVersion: '@pierre/diffs@test',
	workerMode: 'pane-comm-worker' as const,
};
const runManifestHash = bridgeLocalFirstProofRunManifestHash(runFacts);
const runIdentityFingerprint = bridgeLocalFirstProofRunIdentityFingerprint({
	...runFacts,
	runManifestHash,
});
const runIdentity = { ...runFacts, runManifestHash, runIdentityFingerprint };
const fixtureOracle = parseBridgeLocalFirstProofFixtureOracle({
	expectedFixtureChecksum: runIdentity.fixtureChecksum,
	expectedFixtureId: runIdentity.fixtureId,
	rawOracle: {
		schemaVersion: 1,
		fixtureId: runIdentity.fixtureId,
		fixtureChecksum: runIdentity.fixtureChecksum,
		entries: [],
	},
});

if (expect.getState().testPath === fileURLToPath(import.meta.url)) {
	describe('bridge local-first proof honesty contract', () => {
		test('materializes the closed 21-row, 84-cell, 252-launch, 25,200-attempt floor', () => {
			expect(bridgeLocalFirstProofManifestRows.map((row) => row.manifestRowId)).toEqual(
				expectedManifestRowIds,
			);
			expect(bridgeLocalFirstProofManifestRows).toHaveLength(21);
			expect(bridgeLocalFirstProofCells).toHaveLength(84);
			expect(new Set(bridgeLocalFirstProofCells.map((cell) => cell.cellId)).size).toBe(84);
			expect(bridgeLocalFirstProofRequiredCellCount).toBe(84);
			expect(bridgeLocalFirstProofRequiredLaunchCount).toBe(252);
			expect(bridgeLocalFirstProofMinimumMeasuredAttemptCount).toBe(25_200);
			expect(
				new Set(bridgeLocalFirstProofCells.map((cell) => cell.attemptDeadlineMilliseconds)),
			).toEqual(new Set([1_000]));
		});

		test('closes applicability for all 84 cells without universal Pierre work', () => {
			expect(bridgeLocalFirstProofApplicabilityByCellId.size).toBe(84);
			for (const cell of bridgeLocalFirstProofCells) {
				expect(bridgeLocalFirstProofApplicabilityByCellId.get(cell.cellId)).toMatchObject({
					cellId: cell.cellId,
					endpointKind: expect.any(String),
					lifecycleVariant: cell.sourceCacheState,
					pierreSubmission: expect.stringMatching(/^(required|forbidden)$/u),
				});
			}

			const cachedTerminal = bridgeLocalFirstProofCells.find(
				(cell) =>
					cell.family === 'file-terminal-availability' &&
					cell.sourceCacheState === 'cached-terminal',
			);
			const continuation = bridgeLocalFirstProofCells.find(
				(cell) =>
					cell.family === 'review-code-view-scroll' &&
					cell.sourceCacheState === 'continuation-miss',
			);
			expect(cachedTerminal).toBeDefined();
			expect(continuation).toBeDefined();
			expect(
				bridgeLocalFirstProofApplicabilityByCellId.get(cachedTerminal?.cellId ?? '')
					?.pierreSubmission,
			).toBe('forbidden');
			expect(
				bridgeLocalFirstProofApplicabilityByCellId.get(continuation?.cellId ?? '')
					?.pierreSubmission,
			).toBe('required');
		});

		test('recomputes run and aggregate fingerprints from canonical facts', () => {
			const aggregateFingerprint = bridgeLocalFirstProofAggregateManifestFingerprint({
				components: {
					controlled_dev_chromium: {
						relativePath: 'browser/component.json',
						sha256: 'e'.repeat(64),
					},
					packaged_wkwebview: {
						relativePath: 'native/component.json',
						sha256: 'f'.repeat(64),
					},
				},
				fixtureOracle: {
					relativePath: 'fixtures/endpoint-oracle.json',
					sha256: '1'.repeat(64),
				},
				runIdentityFingerprint,
				schemaVersion: 1,
			});

			expect(runManifestHash).toMatch(/^[a-f0-9]{64}$/u);
			expect(runIdentityFingerprint).toMatch(/^[a-f0-9]{64}$/u);
			expect(aggregateFingerprint).toMatch(/^[a-f0-9]{64}$/u);
		});

		test('rejects a run identity with a tampered manifest hash', () => {
			expect(() =>
				parseBridgeLocalFirstProofCohortWithOracle(
					{
						schemaVersion: 1,
						runIdentity: { ...runIdentity, runManifestHash: '6'.repeat(64) },
						cells: [],
					},
					runIdentity,
					fixtureOracle,
				),
			).toThrow(/manifest hash does not match canonical run facts/u);
		});

		test('rejects direct reducer input that did not pass parser admission', () => {
			expect(() =>
				reduceBridgeLocalFirstProofCohortWithOracle(
					{ schemaVersion: 1, runIdentity, cells: [] },
					runIdentity,
					fixtureOracle,
				),
			).toThrow(/exactly 84 manifest cells/u);
		});

		test('rejects the legacy positive-only browser benchmark artifact', () => {
			expect(() =>
				parseBridgeLocalFirstProofCohortWithOracle(
					{ schemaVersion: 1, runner: 'vitest-browser', metrics: [] },
					runIdentity,
					fixtureOracle,
				),
			).toThrow(/runIdentity|Invalid input/iu);
		});
	});
}

export type BridgeLocalFirstTestDeepMutable<TValue> = TValue extends readonly (infer TItem)[]
	? BridgeLocalFirstTestDeepMutable<TItem>[]
	: TValue extends object
		? { -readonly [TKey in keyof TValue]: BridgeLocalFirstTestDeepMutable<TValue[TKey]> }
		: TValue;

export interface BridgeLocalFirstTestAttemptFactoryProps {
	readonly attemptIndex: number;
	readonly defaultAttempt: BridgeLocalFirstTestDeepMutable<BridgeLocalFirstProofAttemptInput>;
	readonly launchIndex: number;
}

export interface BridgeLocalFirstTestProofFixtureOptions {
	readonly executableSha256: string;
	readonly launchCount?: number;
	readonly makeAttempt?: (
		props: BridgeLocalFirstTestAttemptFactoryProps,
	) => BridgeLocalFirstTestDeepMutable<BridgeLocalFirstProofAttemptInput>;
	readonly measuredAttemptCount?: number;
	readonly runIdentity: BridgeLocalFirstProofRunIdentity;
	readonly stimulusBaseMilliseconds?: number;
	readonly stimulusStrideMilliseconds?: number;
	readonly successfulDurationMilliseconds?: (props: {
		readonly attemptIndex: number;
		readonly launchIndex: number;
	}) => number;
}

export interface BridgeLocalFirstTestProofFixture {
	readonly cohort: BridgeLocalFirstTestDeepMutable<BridgeLocalFirstProofCohortInput>;
	readonly fixtureOracle: BridgeLocalFirstValidatedFixtureOracle;
	readonly rawFixtureOracle: BridgeLocalFirstTestDeepMutable<BridgeLocalFirstProofFixtureOracleInput>;
}

export function makeBridgeLocalFirstTestProofFixture(
	options: BridgeLocalFirstTestProofFixtureOptions,
): BridgeLocalFirstTestProofFixture {
	const measuredAttemptCount = options.measuredAttemptCount ?? 100;
	const rawFixtureOracle = makeBridgeLocalFirstTestFixtureOracle(
		options.runIdentity,
		measuredAttemptCount,
	);
	return {
		cohort: {
			schemaVersion: 1,
			runIdentity: structuredClone(options.runIdentity),
			cells: bridgeLocalFirstProofCells.map((cell, cellIndex) => ({
				identity: {
					runId: options.runIdentity.runId,
					cellId: cell.cellId,
					manifestRowId: cell.manifestRowId,
					family: cell.family,
					sourceCacheState: cell.sourceCacheState,
					runtime: cell.runtime,
					telemetryState: cell.telemetryState,
				},
				launches: Array.from({ length: options.launchCount ?? 3 }, (_value, launchIndex) =>
					makeTestLaunch({ cell, cellIndex, launchIndex, measuredAttemptCount, options }),
				),
			})),
		},
		fixtureOracle: parseBridgeLocalFirstProofFixtureOracle({
			expectedFixtureChecksum: options.runIdentity.fixtureChecksum,
			expectedFixtureId: options.runIdentity.fixtureId,
			rawOracle: rawFixtureOracle,
		}),
		rawFixtureOracle,
	};
}

export function makeBridgeLocalFirstTestFixtureOracle(
	runIdentityInput: BridgeLocalFirstProofRunIdentity,
	measuredAttemptCount: number,
): BridgeLocalFirstTestDeepMutable<BridgeLocalFirstProofFixtureOracleInput> {
	const actionIndexes = [
		'warmup',
		...Array.from({ length: measuredAttemptCount }, (_value, actionIndex) => actionIndex),
	] as const;
	return {
		schemaVersion: 1,
		fixtureId: runIdentityInput.fixtureId,
		fixtureChecksum: runIdentityInput.fixtureChecksum,
		entries: [...new Set(bridgeLocalFirstProofCells.map((cell) => cell.manifestRowId))].flatMap(
			(manifestRowId) =>
				actionIndexes.map((actionIndex) => {
					const actionDescriptor = { actionIndex, manifestRowId } as const;
					const cell = testRequiredValue(
						bridgeLocalFirstProofCells.find(
							(candidate) => candidate.manifestRowId === manifestRowId,
						),
					);
					return {
						actionDescriptor,
						oracleEntryId: bridgeLocalFirstProofOracleEntryId({
							actionDescriptor,
							fixtureChecksum: runIdentityInput.fixtureChecksum,
						}),
						expectedEndpoint: testExpectedEndpoint(cell, actionIndex),
					};
				}),
		),
	};
}

interface MakeTestLaunchProps {
	readonly cell: BridgeLocalFirstProofCellContract;
	readonly cellIndex: number;
	readonly launchIndex: number;
	readonly measuredAttemptCount: number;
	readonly options: BridgeLocalFirstTestProofFixtureOptions;
}

function makeTestLaunch(
	props: MakeTestLaunchProps,
): BridgeLocalFirstTestDeepMutable<
	BridgeLocalFirstProofCohortInput['cells'][number]['launches'][number]
> {
	const { cell, launchIndex, options } = props;
	const launchId = `${cell.cellId}--launch-${launchIndex}`;
	const processId = 10_000 + props.cellIndex * (options.launchCount ?? 3) + launchIndex;
	const processStartToken = `${launchId}--start-token`;
	const attempts = Array.from({ length: props.measuredAttemptCount }, (_value, attemptIndex) => {
		const defaultAttempt: BridgeLocalFirstTestDeepMutable<BridgeLocalFirstProofAttemptInput> = {
			identity: {
				runId: options.runIdentity.runId,
				cellId: cell.cellId,
				launchId,
				attemptId: `${launchId}--attempt-${attemptIndex}`,
				attemptIndex,
				interactionId: `${launchId}--interaction-${attemptIndex}`,
				oracleEntryId: testOracleEntryId(options.runIdentity, cell, attemptIndex),
			},
			outcome: 'succeeded',
			durationMilliseconds:
				options.successfulDurationMilliseconds?.({ attemptIndex, launchIndex }) ?? 7,
			deadlineDurationMilliseconds: cell.attemptDeadlineMilliseconds,
		};
		return options.makeAttempt?.({ attemptIndex, defaultAttempt, launchIndex }) ?? defaultAttempt;
	});
	const interactionEvidence = attempts.map((attempt, attemptIndex) =>
		makeBridgeLocalFirstTestInteractionEvidence({ attempt, attemptIndex, cell, options }),
	);
	const measuredActionsCompletedAt =
		Math.max(
			...interactionEvidence.map(
				(evidence) => evidence.external.runtimeTiming.endpointObservedAtMonotonicMilliseconds,
			),
		) + 1;
	const lifecycleBoundaries = [
		0,
		1,
		2,
		3,
		measuredActionsCompletedAt,
		measuredActionsCompletedAt + 1,
		measuredActionsCompletedAt + 2,
	];
	return {
		identity: {
			runId: options.runIdentity.runId,
			runIdentityFingerprint: options.runIdentity.runIdentityFingerprint,
			runManifestHash: options.runIdentity.runManifestHash,
			cellId: cell.cellId,
			launchId,
			launchIndex,
			processId,
			processStartToken,
			executableSha256: options.executableSha256,
			processInstanceId: bridgeLocalFirstProofProcessInstanceId({
				executableSha256: options.executableSha256,
				processId,
				processStartToken,
			}),
			runtimeProcessIdentity:
				cell.runtime === 'controlled_dev_chromium'
					? {
							runtime: 'controlled_dev_chromium',
							browserProcessId: processId,
							browserContextId: `${launchId}--context`,
							devServerOrigin: 'http://127.0.0.1:4173',
						}
					: {
							runtime: 'packaged_wkwebview',
							appProcessId: processId,
							bundleIdentifier: 'com.agentstudio.debug.test',
							bundleHash: options.runIdentity.packagedBundleHash,
						},
		},
		warmup: {
			interactionId: `${launchId}--warmup`,
			oracleEntryId: testOracleEntryId(options.runIdentity, cell, 'warmup'),
			outcome: 'succeeded',
			durationMilliseconds: 1,
			deadlineDurationMilliseconds: 1_000,
			externalEvidence: makeTestExternalEvidence({
				actionIndex: 'warmup',
				cell,
				durationMilliseconds: 1,
				interactionId: `${launchId}--warmup`,
				stimulusAtMonotonicMilliseconds: 2,
			}),
		},
		lifecycleStages: bridgeLocalFirstProofRequiredLifecycleStages.map((stage, stageIndex) => ({
			stage,
			completion: 'completed',
			startedAtMonotonicMilliseconds: testRequiredValue(lifecycleBoundaries[stageIndex]),
			completedAtMonotonicMilliseconds: testRequiredValue(lifecycleBoundaries[stageIndex + 1]),
		})),
		attemptedActionCount: props.measuredAttemptCount,
		attempts,
		interactionEvidence,
		telemetryProof:
			cell.telemetryState === 'off' ? { mode: 'off' } : makeTestTelemetryProof(interactionEvidence),
	};
}

type MutableTestInteractionEvidence = BridgeLocalFirstTestDeepMutable<
	BridgeLocalFirstProofCohortInput['cells'][number]['launches'][number]['interactionEvidence'][number]
>;

export function makeBridgeLocalFirstTestInteractionEvidence(props: {
	readonly attempt: BridgeLocalFirstTestDeepMutable<BridgeLocalFirstProofAttemptInput>;
	readonly attemptIndex: number;
	readonly cell: BridgeLocalFirstProofCellContract;
	readonly options: BridgeLocalFirstTestProofFixtureOptions;
}): MutableTestInteractionEvidence {
	const interactionId = props.attempt.identity.interactionId;
	const stimulusAtMonotonicMilliseconds =
		(props.options.stimulusBaseMilliseconds ?? 10_000) +
		props.attemptIndex * (props.options.stimulusStrideMilliseconds ?? 20);
	const durationMilliseconds =
		props.attempt.outcome === 'succeeded' ? props.attempt.durationMilliseconds : 7;
	return {
		interactionId,
		external: makeTestExternalEvidence({
			actionIndex: props.attemptIndex,
			cell: props.cell,
			durationMilliseconds,
			...(props.attempt.outcome === 'failed' ? { failureKind: props.attempt.failureKind } : {}),
			interactionId,
			stimulusAtMonotonicMilliseconds,
		}),
		internal: makeTestInternalEvidence({
			attemptIndex: props.attemptIndex,
			cell: props.cell,
			durationMilliseconds,
			interactionId,
			stimulusAtMonotonicMilliseconds,
		}),
	};
}

function makeTestExternalEvidence(props: {
	readonly actionIndex: 'warmup' | number;
	readonly cell: BridgeLocalFirstProofCellContract;
	readonly durationMilliseconds: number;
	readonly failureKind?: BridgeLocalFirstProofFailureKind;
	readonly interactionId: string;
	readonly stimulusAtMonotonicMilliseconds: number;
}): MutableTestInteractionEvidence['external'] {
	const endpointObservedAtMonotonicMilliseconds =
		props.stimulusAtMonotonicMilliseconds + props.durationMilliseconds;
	const observationCompletedAtMonotonicMilliseconds = endpointObservedAtMonotonicMilliseconds + 1;
	const observerCoverage = {
		installReceiptId: `${props.interactionId}--event-loop-installed`,
		drainReceiptId: `${props.interactionId}--event-loop-drained`,
		callbackTimestamps: testCadenceTimestamps(
			props.stimulusAtMonotonicMilliseconds,
			observationCompletedAtMonotonicMilliseconds,
			8,
		),
		animationFrameTimestamps: testCadenceTimestamps(
			props.stimulusAtMonotonicMilliseconds,
			observationCompletedAtMonotonicMilliseconds,
			16,
		),
	};
	return {
		interactionId: props.interactionId,
		runtimeTiming:
			props.cell.runtime === 'controlled_dev_chromium'
				? {
						runtime: 'controlled_dev_chromium',
						interactionId: props.interactionId,
						clockDomain: 'browser_performance',
						eventIsTrusted: true,
						actionable: true,
						stimulusAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds,
						handlerStartedAtMonotonicMilliseconds:
							props.stimulusAtMonotonicMilliseconds + Math.min(0.25, props.durationMilliseconds),
						endpointObservedAtMonotonicMilliseconds,
					}
				: {
						runtime: 'packaged_wkwebview',
						interactionId: props.interactionId,
						clockDomain: 'controller_monotonic',
						semanticCommandId: `${props.interactionId}--command`,
						correlatedHandlerReceiptId: `${props.interactionId}--handler-receipt`,
						actionable: true,
						stimulusAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds,
						endpointObservedAtMonotonicMilliseconds,
					},
		endpoint:
			props.failureKind === undefined
				? testObservedEndpoint(props.cell, props.actionIndex)
				: { kind: 'failure', failureKind: props.failureKind },
		eventLoop:
			props.cell.runtime === 'controlled_dev_chromium'
				? {
						runtime: 'controlled_dev_chromium',
						interactionId: props.interactionId,
						observerReady: true,
						observationStartedAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds,
						observationCompletedAtMonotonicMilliseconds,
						observerCoverage,
						longTasks: [],
						rafGaps: [],
					}
				: {
						runtime: 'packaged_wkwebview',
						interactionId: props.interactionId,
						sentinelReady: true,
						nominalCadenceMilliseconds: 8,
						observationStartedAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds,
						observationCompletedAtMonotonicMilliseconds,
						observerCoverage,
						callbackGaps: [],
						rafGaps: [],
					},
	};
}

function testObservedEndpoint(
	cell: BridgeLocalFirstProofCellContract,
	actionIndex: 'warmup' | number,
): MutableTestInteractionEvidence['external']['endpoint'] {
	const expected = testExpectedEndpoint(cell, actionIndex);
	switch (expected.kind) {
		case 'selection_feedback':
			return {
				kind: expected.kind,
				observedSelectionIdentity: expected.selectionIdentity,
				observedPresentation: expected.presentation,
			};
		case 'selected_readable':
			return {
				kind: expected.kind,
				observedSemanticIdentity: expected.semanticIdentity,
				observedWindowIdentity: expected.windowIdentity,
				observedRenderIdentity: expected.renderIdentity,
				observedChecksum: expected.checksum,
				validationLeaseCurrent: true,
			};
		case 'terminal_availability':
			return {
				kind: expected.kind,
				observedSemanticIdentity: expected.semanticIdentity,
				observedAvailability: expected.availability,
			};
		case 'rail_scroll':
			return { kind: expected.kind, observedRowsChecksum: expected.rowsChecksum, motionPixels: 1 };
		case 'content_scroll':
			return {
				kind: expected.kind,
				observedWindowIdentity: expected.windowIdentity,
				observedChecksum: expected.checksum,
				motionPixels: 1,
			};
	}
	throw new Error('test endpoint fixture kind is not closed');
}

function testExpectedEndpoint(
	cell: BridgeLocalFirstProofCellContract,
	actionIndex: 'warmup' | number,
): BridgeLocalFirstProofExpectedEndpoint {
	const identityPrefix = `fixture:${cell.manifestRowId}:${actionIndex}`;
	const endpointKind = testRequiredValue(
		bridgeLocalFirstProofApplicabilityByCellId.get(cell.cellId),
	).endpointKind;
	switch (endpointKind) {
		case 'selection_feedback':
			return {
				kind: endpointKind,
				selectionIdentity: `${identityPrefix}:selection`,
				presentation: 'readable',
			};
		case 'selected_readable':
			return {
				kind: endpointKind,
				semanticIdentity: `${identityPrefix}:semantic`,
				windowIdentity: `${identityPrefix}:window`,
				renderIdentity: `${identityPrefix}:render`,
				checksum: `${identityPrefix}:checksum`,
			};
		case 'terminal_availability':
			return {
				kind: endpointKind,
				semanticIdentity: `${identityPrefix}:semantic`,
				availability: 'unavailable',
			};
		case 'rail_scroll':
			return { kind: endpointKind, rowsChecksum: `${identityPrefix}:rows` };
		case 'content_scroll':
			return {
				kind: endpointKind,
				windowIdentity: `${identityPrefix}:window`,
				checksum: `${identityPrefix}:checksum`,
			};
	}
	throw new Error('test expected endpoint kind is not closed');
}

function makeTestInternalEvidence(props: {
	readonly attemptIndex: number;
	readonly cell: BridgeLocalFirstProofCellContract;
	readonly durationMilliseconds: number;
	readonly interactionId: string;
	readonly stimulusAtMonotonicMilliseconds: number;
}): MutableTestInteractionEvidence['internal'] {
	if (props.cell.telemetryState === 'off') return { mode: 'off' };
	const applicability = testRequiredValue(
		bridgeLocalFirstProofApplicabilityByCellId.get(props.cell.cellId),
	);
	const stages = bridgeLocalFirstProofRequiredInternalStagesForApplicability(applicability);
	const stageCount = {
		comm: stages.filter((stage) => bridgeLocalFirstProofProducerForStage(stage) === 'comm').length,
		main: stages.filter((stage) => bridgeLocalFirstProofProducerForStage(stage) === 'main').length,
	};
	const ordinal = { comm: 0, main: 0 };
	const spans: Extract<MutableTestInteractionEvidence['internal'], { mode: 'on' }>['spans'] = [];
	if (applicability.selectedCommQueue === 'required') {
		spans.push(testSpan(props, 'selected_comm_queue'));
	}
	if (applicability.pierreSubmission === 'required') {
		spans.push(testSpan(props, 'main_to_pierre'));
	}
	return {
		mode: 'on',
		events: stages.map((stage, stageIndex) => {
			const producer = bridgeLocalFirstProofProducerForStage(stage);
			ordinal[producer] += 1;
			return {
				interactionId: props.interactionId,
				producer,
				producerSequence: props.attemptIndex * stageCount[producer] + ordinal[producer],
				interactionSequence: stageIndex + 1,
				stage,
				observedAtMonotonicMilliseconds:
					props.stimulusAtMonotonicMilliseconds +
					(props.durationMilliseconds * (stageIndex + 1)) / (stages.length + 1),
			};
		}),
		spans,
		synchronousSlices: [...new Set(stages.map(bridgeLocalFirstProofProducerForStage))].map(
			(owner) => testSynchronousSlice(props, owner),
		),
	};
}

function testSpan(
	props: { readonly interactionId: string; readonly stimulusAtMonotonicMilliseconds: number },
	kind: 'main_to_pierre' | 'selected_comm_queue',
): {
	readonly interactionId: string;
	readonly startedAtMonotonicMilliseconds: number;
	readonly completedAtMonotonicMilliseconds: number;
	readonly kind: 'main_to_pierre' | 'selected_comm_queue';
} {
	return { ...testTimeRange(props), kind };
}

function testTimeRange(props: {
	readonly interactionId: string;
	readonly stimulusAtMonotonicMilliseconds: number;
}): {
	readonly interactionId: string;
	readonly startedAtMonotonicMilliseconds: number;
	readonly completedAtMonotonicMilliseconds: number;
} {
	return {
		interactionId: props.interactionId,
		startedAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds,
		completedAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds + 1,
	};
}

function testSynchronousSlice(
	props: { readonly interactionId: string; readonly stimulusAtMonotonicMilliseconds: number },
	owner: 'comm' | 'main',
): {
	readonly interactionId: string;
	readonly owner: 'comm' | 'main';
	readonly startedAtMonotonicMilliseconds: number;
	readonly completedAtMonotonicMilliseconds: number;
} {
	return {
		interactionId: props.interactionId,
		owner,
		startedAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds,
		completedAtMonotonicMilliseconds: props.stimulusAtMonotonicMilliseconds + 1,
	};
}

function makeTestTelemetryProof(
	interactionEvidence: readonly MutableTestInteractionEvidence[],
): BridgeLocalFirstTestDeepMutable<
	BridgeLocalFirstProofCohortInput['cells'][number]['launches'][number]['telemetryProof']
> {
	const events = interactionEvidence.flatMap((evidence) =>
		evidence.internal.mode === 'on' ? evidence.internal.events : [],
	);
	const drainedAtMonotonicMilliseconds =
		Math.max(
			...interactionEvidence.map(
				(evidence) => evidence.external.runtimeTiming.endpointObservedAtMonotonicMilliseconds,
			),
		) + 1;
	return {
		mode: 'on',
		lossRanges: [],
		drainReceipts: (['main', 'comm'] as const).map((producer) => ({
			producer,
			acknowledgedProducerSequence: events.filter((event) => event.producer === producer).length,
			drainedAtMonotonicMilliseconds,
		})),
	};
}

function testOracleEntryId(
	runIdentityInput: BridgeLocalFirstProofRunIdentity,
	cell: BridgeLocalFirstProofCellContract,
	actionIndex: 'warmup' | number,
): string {
	return bridgeLocalFirstProofOracleEntryId({
		actionDescriptor: { actionIndex, manifestRowId: cell.manifestRowId },
		fixtureChecksum: runIdentityInput.fixtureChecksum,
	});
}

function testCadenceTimestamps(start: number, end: number, cadence: number): number[] {
	const timestamps = [start];
	for (let timestamp = start + cadence; timestamp < end; timestamp += cadence) {
		timestamps.push(timestamp);
	}
	timestamps.push(end);
	return timestamps;
}

function testRequiredValue<TValue>(value: TValue | undefined): TValue {
	if (value === undefined) throw new Error('unit-test fixture expected value');
	return value;
}
