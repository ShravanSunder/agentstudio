import { createHash } from 'node:crypto';
import { resolve } from 'node:path';

import { afterEach, describe, expect, test } from 'vitest';

import {
	bridgeLocalFirstProofApplicabilityByCellId,
	bridgeLocalFirstProofRunIdentityFingerprint,
	bridgeLocalFirstProofRunManifestHash,
	parseBridgeLocalFirstProofCohort,
	type BridgeLocalFirstProofCohortInput,
	type BridgeLocalFirstProofRunIdentity,
	type BridgeLocalFirstProofRuntime,
	type BridgeLocalFirstValidatedProofCohort,
} from './bridge-local-first-proof-contract.ts';
import { parseBridgeLocalFirstProofFixtureOracle } from './bridge-local-first-proof-evidence.ts';
import {
	makeBridgeLocalFirstTestProofFixture,
	type BridgeLocalFirstTestDeepMutable,
	type BridgeLocalFirstTestProofFixtureOptions,
} from './bridge-local-first-proof-honesty.unit.test.ts';
import type {
	BridgeLocalFirstLaunchProvenanceObservation,
	BridgeLocalFirstVerifiedLaunchProvenance,
} from './bridge-local-first-proof-provenance.ts';
import {
	reduceBridgeLocalFirstValidatedProofCohort,
	validateBridgeLocalFirstInternalSloCellBudgets,
} from './bridge-local-first-proof-reducer.ts';
import {
	bridgeLocalFirstProofAggregateManifestFingerprint,
	parseBridgeLocalFirstPerformanceArguments,
	validateBridgeLocalFirstProcessObservation,
	validateBridgeLocalFirstReductionBudgets,
	validateBridgeLocalFirstPerformance,
	type BridgeLocalFirstPerformanceValidationPorts,
	type BridgeLocalFirstProcessIdentityObservation,
	type BridgeLocalFirstProcessInstanceEvidence,
} from './verify-bridge-local-first-performance.ts';

const manifestPath = '/proof/latest.json';
const browserComponentPath = '/proof/browser/component.json';
const nativeComponentPath = '/proof/native/component.json';
const fixtureOraclePath = '/proof/fixtures/endpoint-oracle.json';
const executableSha256 = 'a'.repeat(64);
const runFacts = {
	runId: 'aggregate-run',
	headCommitSha: '0123456789abcdef0123456789abcdef01234567',
	dirtyStateHash: '1'.repeat(64),
	packagedBundleHash: '2'.repeat(64),
	fixtureId: 'large-review-and-file-fixture',
	fixtureChecksum: '3'.repeat(64),
	viewport: { width: 1_728, height: 972, deviceScaleFactor: 2 },
	machineProfileHash: '4'.repeat(64),
	pierreVersion: '@pierre/diffs@test',
	workerMode: 'pane-comm-worker',
} as const;
const runManifestHash = bridgeLocalFirstProofRunManifestHash(runFacts);
const runIdentity: BridgeLocalFirstProofRunIdentity = Object.freeze({
	...runFacts,
	runManifestHash,
	runIdentityFingerprint: bridgeLocalFirstProofRunIdentityFingerprint({
		...runFacts,
		runManifestHash,
	}),
});
const aggregateTestFixtureOptions = {
	runIdentity,
	executableSha256,
	successfulDurationMilliseconds: (): number => 7,
	stimulusBaseMilliseconds: 10_000,
	stimulusStrideMilliseconds: 20,
} satisfies BridgeLocalFirstTestProofFixtureOptions;
const aggregateProofFixture = makeBridgeLocalFirstTestProofFixture(aggregateTestFixtureOptions);
const baseFixtureOracle = aggregateProofFixture.rawFixtureOracle;
const completeCohort = aggregateProofFixture.cohort;
const validatedCompleteCohort = parseBridgeLocalFirstProofCohort(
	completeCohort,
	runIdentity,
	parseBridgeLocalFirstProofFixtureOracle({
		expectedFixtureChecksum: runIdentity.fixtureChecksum,
		expectedFixtureId: runIdentity.fixtureId,
		rawOracle: baseFixtureOracle,
	}),
);
const validatedCompleteReduction =
	reduceBridgeLocalFirstValidatedProofCohort(validatedCompleteCohort);
const validatedProcessEvidence = requiredValue(
	requiredValue(validatedCompleteCohort.cells[0]).launches[0],
).identity;
const baseBrowserComponent = componentForRuntime('controlled_dev_chromium');
const baseNativeComponent = componentForRuntime('packaged_wkwebview');
const canonicalBrowserComponentBytes = encodeJson(JSON.stringify(baseBrowserComponent));
const canonicalNativeComponentBytes = encodeJson(JSON.stringify(baseNativeComponent));
const canonicalFixtureOracleBytes = encodeJson(JSON.stringify(baseFixtureOracle));
const canonicalBrowserComponentSha256 = sha256(canonicalBrowserComponentBytes);
const canonicalNativeComponentSha256 = sha256(canonicalNativeComponentBytes);
const canonicalFixtureOracleSha256 = sha256(canonicalFixtureOracleBytes);
const invalidArgumentCases: readonly { readonly argumentsToParse: readonly string[] }[] = [
	{ argumentsToParse: [] },
	{ argumentsToParse: ['--manifest', manifestPath] },
	{ argumentsToParse: ['--validate-only', 'position'] },
	{ argumentsToParse: ['--validate-only', '--run'] },
	{ argumentsToParse: ['--validate-only', '--launch'] },
	{ argumentsToParse: ['--validate-only', '--validate-only'] },
	{
		argumentsToParse: ['--validate-only', '--manifest', manifestPath, '--manifest', manifestPath],
	},
	{ argumentsToParse: ['--validate-only', '--manifest='] },
];
const staleLiveIdentityCases: readonly {
	readonly field: string;
	readonly mutate: (identity: DeepMutable<BridgeLocalFirstProofRunIdentity>) => void;
}[] = [
	{ field: 'runId', mutate: (identity) => (identity.runId = 'run:live-other') },
	{
		field: 'headCommitSha',
		mutate: (identity) => (identity.headCommitSha = 'fedcba9876543210fedcba9876543210fedcba98'),
	},
	{ field: 'dirtyStateHash', mutate: (identity) => (identity.dirtyStateHash = '5'.repeat(64)) },
	{
		field: 'packagedBundleHash',
		mutate: (identity) => (identity.packagedBundleHash = '6'.repeat(64)),
	},
	{ field: 'fixtureId', mutate: (identity) => (identity.fixtureId = 'fixture:live-other') },
	{
		field: 'fixtureChecksum',
		mutate: (identity) => (identity.fixtureChecksum = '7'.repeat(64)),
	},
	{ field: 'viewport', mutate: (identity) => (identity.viewport.width += 1) },
	{
		field: 'machineProfileHash',
		mutate: (identity) => (identity.machineProfileHash = '8'.repeat(64)),
	},
	{ field: 'pierreVersion', mutate: (identity) => (identity.pierreVersion = 'pierre:live-other') },
];

afterEach(async (): Promise<void> => {
	await yieldToVitestWorkerRpc();
});

describe('Bridge local-first validate-only aggregate', () => {
	test('admits two hashed runtime partitions without launching or signalling anything', async () => {
		const fixture = makeFixture();

		const result = await validateBridgeLocalFirstPerformance({
			manifestPath,
			ports: fixture.ports,
		});

		expect(result.reduction.totals).toEqual({
			cellCount: 84,
			launchCount: 252,
			measuredAttemptCount: 25_200,
			failureCount: 0,
		});
		expect(fixture.fileReadPaths).toEqual([
			manifestPath,
			fixtureOraclePath,
			browserComponentPath,
			nativeComponentPath,
		]);
		expect(fixture.inspectedProcessCount()).toBe(252);
		expect(fixture.liveIdentityReadCount()).toBe(2);
	});

	test('fails closed when independent launch provenance is unavailable', async () => {
		const fixture = makeFixture();
		const ports = {
			...fixture.ports,
			provenance: {
				readCurrentRunIdentity: async () => ({ state: 'verified' as const, identity: runIdentity }),
				inspectLaunchProvenance: async () => ({
					state: 'unverified' as const,
					reason: 'launch journal missing',
				}),
			},
		};

		await expect(validateBridgeLocalFirstPerformance({ manifestPath, ports })).rejects.toThrow(
			/launch provenance is unverified/u,
		);
	});

	test('rejects a mismatched independent launch receipt', async () => {
		const mismatched = makeFixture({
			launchProvenance: (launchId) => {
				const provenance = verifiedLaunchProvenance(launchId);
				return {
					...provenance,
					runningReceipt: {
						...provenance.runningReceipt,
						processId: provenance.runningReceipt.processId + 1,
					},
				};
			},
		});

		await expectValidationFailure(mismatched, /independent process provenance mismatch/u);
	});

	test('rejects a reused independent launch receipt', async () => {
		const reused = makeFixture({
			launchProvenance: (launchId) => ({
				...verifiedLaunchProvenance(launchId),
				runtimeReadyReceipt: { eventId: 'reused-ready-receipt' },
			}),
		});

		await expectValidationFailure(reused, /reused independent provenance receipt/u);
	});

	test.each(staleLiveIdentityCases)(
		'rejects mutually stale component identity field $field against live facts',
		async ({ field, mutate }) => {
			const staleLiveIdentity: DeepMutable<BridgeLocalFirstProofRunIdentity> =
				structuredClone(runIdentity);
			mutate(staleLiveIdentity);
			refreshRunIdentityHashes(staleLiveIdentity);

			await expectValidationFailure(
				makeFixture({ liveIdentities: [staleLiveIdentity, staleLiveIdentity] }),
				field === 'fixtureId' || field === 'fixtureChecksum'
					? /fixture oracle identity/u
					: /stale run identity/u,
			);
		},
	);

	test('rejects a live identity with a non-canonical worker mode', async () => {
		const invalidIdentity = structuredClone(runIdentity);
		Reflect.set(invalidIdentity, 'workerMode', 'main-thread-transport');

		await expectValidationFailure(
			makeFixture({ liveIdentities: [invalidIdentity] }),
			/Invalid input/u,
		);
	});

	test('re-reads live identity after process validation and rejects TOCTOU drift', async () => {
		const changedIdentity: DeepMutable<BridgeLocalFirstProofRunIdentity> =
			structuredClone(runIdentity);
		changedIdentity.dirtyStateHash = '9'.repeat(64);
		refreshRunIdentityHashes(changedIdentity);

		await expectValidationFailure(
			makeFixture({ liveIdentities: [runIdentity, changedIdentity] }),
			/live run identity changed during validation/u,
		);
	});

	test.each(invalidArgumentCases)(
		'rejects non-validate-only or ambiguous CLI arguments: %j',
		({ argumentsToParse }) => {
			expect(() => parseBridgeLocalFirstPerformanceArguments(argumentsToParse)).toThrow();
		},
	);

	test('admits the strict CLI with an optional manifest', () => {
		expect(
			parseBridgeLocalFirstPerformanceArguments(['--validate-only', '--manifest', manifestPath]),
		).toEqual({ manifestPath, validateOnly: true });
	});

	test('rejects an aggregate with a third component descriptor', async () => {
		const fixture = makeFixture({
			mutateManifest: (manifest) => {
				Reflect.set(manifest.components, 'unexpected_runtime', {
					...manifest.components.controlled_dev_chromium,
				});
			},
		});

		await expectValidationFailure(fixture, /unrecognized|unexpected_runtime/iu);
	});

	test('rejects a component hash mismatch', async () => {
		const fixture = makeFixture({
			mutateManifest: (manifest) => {
				manifest.components.controlled_dev_chromium.sha256 = '0'.repeat(64);
			},
		});

		await expectValidationFailure(fixture, /SHA-256 mismatch/u);
	});

	test('rejects a fixture oracle hash mismatch or independently wrong expected endpoint', async () => {
		const hashMismatch = makeFixture({
			mutateManifest: (manifest) => {
				manifest.fixtureOracle.sha256 = '0'.repeat(64);
			},
		});
		const wrongOracle = structuredClone(baseFixtureOracle);
		const firstEntry = requiredValue(wrongOracle.entries[0]);
		if (firstEntry.expectedEndpoint.kind !== 'selection_feedback') {
			throw new Error('test fixture expected selection oracle');
		}
		firstEntry.expectedEndpoint.selectionIdentity = 'fixture:forged-selection';

		await expectValidationFailure(hashMismatch, /fixture oracle SHA-256 mismatch/u);
		await expectValidationFailure(
			makeFixture({ fixtureOracleBytes: encodeJson(JSON.stringify(wrongOracle)) }),
			/endpoint oracle derived stale/u,
		);
	});

	test('rejects an aggregate fingerprint that does not bind its component descriptors', async () => {
		await expectValidationFailure(
			makeFixture({ tamperAggregateFingerprint: true }),
			/aggregate manifest fingerprint does not match artifact descriptors/u,
		);
	});

	test('rejects lexical and canonical component escapes', async () => {
		const lexicalEscape = makeFixture({
			mutateManifest: (manifest) => {
				manifest.components.controlled_dev_chromium.relativePath = '../outside.json';
			},
		});
		const canonicalEscape = makeFixture({
			canonicalPathOverrides: new Map([[browserComponentPath, '/outside/component.json']]),
		});

		await expectValidationFailure(lexicalEscape, /escapes proof root/u);
		await expectValidationFailure(canonicalEscape, /canonical path escapes proof root/u);
	});

	test('rejects malformed component JSON even when its hash matches', async () => {
		const fixture = makeFixture({ browserComponentBytes: encodeJson('{not-json') });

		await expectValidationFailure(fixture, /invalid JSON artifact/u);
	});

	test('rejects a missing or cross-runtime cell in either 42-cell partition', async () => {
		const missingCellComponent = cloneBrowserComponent();
		missingCellComponent.cells.pop();
		const crossRuntimeComponent = cloneNativeComponent();
		requiredValue(crossRuntimeComponent.cells[0]).identity.runtime = 'controlled_dev_chromium';

		await expectValidationFailure(
			makeFixture({ browserComponent: missingCellComponent }),
			/exactly 42 runtime cells/u,
		);
		await expectValidationFailure(
			makeFixture({ nativeComponent: crossRuntimeComponent }),
			/contains controlled_dev_chromium cell/u,
		);
	});

	test('rejects components from different run identities', async () => {
		const nativeComponent = cloneNativeComponent();
		nativeComponent.runIdentity.runIdentityFingerprint = 'a'.repeat(64);
		const staleFixtureComponent = cloneNativeComponent();
		staleFixtureComponent.runIdentity.fixtureChecksum = 'b'.repeat(64);

		await expectValidationFailure(
			makeFixture({ nativeComponent }),
			/different run identity fingerprints/u,
		);
		await expectValidationFailure(
			makeFixture({ nativeComponent: staleFixtureComponent }),
			/different run identities/u,
		);
	});

	test('rejects every nonzero correctness failure count', () => {
		const reduction = {
			...validatedCompleteReduction,
			totals: { ...validatedCompleteReduction.totals, failureCount: 1 },
		};

		expect(() => validateBridgeLocalFirstReductionBudgets(reduction)).toThrow(
			/1 correctness failures/u,
		);
	});

	test.each([
		{ percentile: 'p95', scope: 'launch' },
		{ percentile: 'p95', scope: 'pooled' },
		{ percentile: 'p95', scope: 'worst-launch' },
		{ percentile: 'p99', scope: 'launch' },
		{ percentile: 'p99', scope: 'pooled' },
		{ percentile: 'p99', scope: 'worst-launch' },
	] as const)('rejects the strict $percentile boundary for $scope', ({ percentile, scope }) => {
		const durationField =
			percentile === 'p95' ? 'p95DurationMilliseconds' : 'p99DurationMilliseconds';
		const reduction = reductionWithBoundaryDuration(scope, durationField, 32);

		expect(() => validateBridgeLocalFirstReductionBudgets(reduction)).toThrow(
			new RegExp(`${scope === 'launch' ? 'launch' : scope}.*${percentile} 32 ms`, 'u'),
		);
	});

	test('derives the strict comm queue p95 stop line from raw timestamps', () => {
		const p95Cell = internalSloBoundaryCell('commQueue', 16, 'all');

		expect(() => validateBridgeLocalFirstInternalSloCellBudgets(p95Cell)).toThrow(
			/comm queue p95 16 ms/u,
		);
	});

	test('derives the strict comm queue p99 stop line from raw timestamps', () => {
		const p99Cell = internalSloBoundaryCell('commQueue', 32, 'last-two');

		expect(() => validateBridgeLocalFirstInternalSloCellBudgets(p99Cell)).toThrow(
			/comm queue p99 32 ms/u,
		);
	});

	test('derives the strict main-to-Pierre p95 stop line from raw timestamps', () => {
		const p95Cell = internalSloBoundaryCell('mainToPierre', 4, 'all');

		expect(() => validateBridgeLocalFirstInternalSloCellBudgets(p95Cell)).toThrow(
			/main-to-Pierre p95 4 ms/u,
		);
	});

	test('derives the strict main-to-Pierre p99 stop line from raw timestamps', () => {
		const p99Cell = internalSloBoundaryCell('mainToPierre', 8, 'last-two');

		expect(() => validateBridgeLocalFirstInternalSloCellBudgets(p99Cell)).toThrow(
			/main-to-Pierre p99 8 ms/u,
		);
	});

	test('rejects mutable process evidence outside the hashed runtime component', async () => {
		const fixture = makeFixture({
			mutateManifest: (manifest) => {
				Reflect.set(manifest.components.controlled_dev_chromium, 'processInstances', []);
			},
		});

		await expectValidationFailure(fixture, /unrecognized|processInstances/iu);
	});

	test('rejects a hashed launch whose process token no longer derives its instance identity', async () => {
		const browserComponent = cloneBrowserComponent();
		const launch = requiredValue(requiredValue(browserComponent.cells[0]).launches[0]);
		launch.identity.processStartToken = `${launch.identity.processStartToken}:tampered`;

		await expectValidationFailure(
			makeFixture({ browserComponent }),
			/process instance identity does not match concrete launch evidence/u,
		);
	});

	test('rejects a live matching process instance as an orphan', () => {
		expect(() =>
			validateBridgeLocalFirstProcessObservation(validatedProcessEvidence, {
				state: 'running',
				processStartToken: validatedProcessEvidence.processStartToken,
				executableSha256: validatedProcessEvidence.executableSha256,
			}),
		).toThrow(/owned process instance is still live/u);
	});

	test('allows an exited process', () => {
		expect(() =>
			validateBridgeLocalFirstProcessObservation(validatedProcessEvidence, { state: 'exited' }),
		).not.toThrow();
	});

	test('allows a reused live PID with a different start token', () => {
		expect(() =>
			validateBridgeLocalFirstProcessObservation(validatedProcessEvidence, {
				state: 'running',
				processStartToken: `${validatedProcessEvidence.processStartToken}:reused`,
				executableSha256: validatedProcessEvidence.executableSha256,
			}),
		).not.toThrow();
	});

	test('rejects indeterminate live process identity', () => {
		expect(() =>
			validateBridgeLocalFirstProcessObservation(validatedProcessEvidence, {
				state: 'indeterminate',
				reason: 'permission denied',
			}),
		).toThrow(/process identity is indeterminate/u);
	});

	test('rejects same-start executable drift', () => {
		expect(() =>
			validateBridgeLocalFirstProcessObservation(validatedProcessEvidence, {
				state: 'running',
				processStartToken: validatedProcessEvidence.processStartToken,
				executableSha256: 'b'.repeat(64),
			}),
		).toThrow(/indeterminate executable identity/u);
	});
});

interface TestComponentDescriptor {
	relativePath: string;
	sha256: string;
}

interface TestAggregateManifest {
	schemaVersion: 1;
	runIdentityFingerprint: string;
	components: Record<BridgeLocalFirstProofRuntime, TestComponentDescriptor>;
	fixtureOracle: TestComponentDescriptor;
	aggregateManifestFingerprint: string;
}

interface MakeFixtureProps {
	readonly browserComponent?: DeepMutable<BridgeLocalFirstProofCohortInput>;
	readonly nativeComponent?: DeepMutable<BridgeLocalFirstProofCohortInput>;
	readonly browserComponentBytes?: Uint8Array;
	readonly fixtureOracleBytes?: Uint8Array;
	readonly canonicalPathOverrides?: ReadonlyMap<string, string>;
	readonly mutateManifest?: (manifest: TestAggregateManifest) => void;
	readonly tamperAggregateFingerprint?: boolean;
	readonly liveIdentities?: readonly BridgeLocalFirstProofRunIdentity[];
	readonly launchProvenance?: (launchId: string) => BridgeLocalFirstLaunchProvenanceObservation;
	readonly processObservation?: (
		evidence: BridgeLocalFirstProcessInstanceEvidence,
	) => Promise<BridgeLocalFirstProcessIdentityObservation>;
}

interface TestFixture {
	readonly fileReadPaths: string[];
	readonly inspectedProcessCount: () => number;
	readonly liveIdentityReadCount: () => number;
	readonly ports: BridgeLocalFirstPerformanceValidationPorts;
}

function makeFixture(props: MakeFixtureProps = {}): TestFixture {
	const browserBytes =
		props.browserComponentBytes ??
		(props.browserComponent === undefined
			? canonicalBrowserComponentBytes
			: encodeJson(JSON.stringify(props.browserComponent)));
	const nativeBytes =
		props.nativeComponent === undefined
			? canonicalNativeComponentBytes
			: encodeJson(JSON.stringify(props.nativeComponent));
	const fixtureOracleBytes = props.fixtureOracleBytes ?? canonicalFixtureOracleBytes;
	const browserSha256 =
		browserBytes === canonicalBrowserComponentBytes
			? canonicalBrowserComponentSha256
			: sha256(browserBytes);
	const nativeSha256 =
		nativeBytes === canonicalNativeComponentBytes
			? canonicalNativeComponentSha256
			: sha256(nativeBytes);
	const fixtureOracleSha256 =
		fixtureOracleBytes === canonicalFixtureOracleBytes
			? canonicalFixtureOracleSha256
			: sha256(fixtureOracleBytes);
	const manifest: TestAggregateManifest = {
		schemaVersion: 1,
		runIdentityFingerprint: runIdentity.runIdentityFingerprint,
		components: {
			controlled_dev_chromium: {
				relativePath: 'browser/component.json',
				sha256: browserSha256,
			},
			packaged_wkwebview: {
				relativePath: 'native/component.json',
				sha256: nativeSha256,
			},
		},
		fixtureOracle: {
			relativePath: 'fixtures/endpoint-oracle.json',
			sha256: fixtureOracleSha256,
		},
		aggregateManifestFingerprint: '0'.repeat(64),
	};
	props.mutateManifest?.(manifest);
	manifest.aggregateManifestFingerprint = bridgeLocalFirstProofAggregateManifestFingerprint({
		schemaVersion: manifest.schemaVersion,
		runIdentityFingerprint: manifest.runIdentityFingerprint,
		components: {
			controlled_dev_chromium: {
				relativePath: manifest.components.controlled_dev_chromium.relativePath,
				sha256: manifest.components.controlled_dev_chromium.sha256,
			},
			packaged_wkwebview: {
				relativePath: manifest.components.packaged_wkwebview.relativePath,
				sha256: manifest.components.packaged_wkwebview.sha256,
			},
		},
		fixtureOracle: {
			relativePath: manifest.fixtureOracle.relativePath,
			sha256: manifest.fixtureOracle.sha256,
		},
	});
	if (props.tamperAggregateFingerprint === true) {
		manifest.aggregateManifestFingerprint = 'f'.repeat(64);
	}
	const fileBytes = new Map<string, Uint8Array>([
		[manifestPath, encodeJson(JSON.stringify(manifest))],
		[fixtureOraclePath, fixtureOracleBytes],
		[browserComponentPath, browserBytes],
		[nativeComponentPath, nativeBytes],
	]);
	const fileReadPaths: string[] = [];
	let processInspectionCount = 0;
	let liveIdentityReadCount = 0;
	let provenanceIdentityReadCount = 0;
	return {
		fileReadPaths,
		inspectedProcessCount: (): number => processInspectionCount,
		liveIdentityReadCount: (): number => liveIdentityReadCount,
		ports: {
			files: {
				canonicalizePath: async (filePath): Promise<string> =>
					props.canonicalPathOverrides?.get(resolve(filePath)) ?? resolve(filePath),
				readBytes: async (filePath): Promise<Uint8Array> => {
					fileReadPaths.push(filePath);
					return requiredValue(fileBytes.get(filePath));
				},
			},
			processes: {
				inspectProcessIdentity: async (evidence) => {
					processInspectionCount += 1;
					return props.processObservation?.(evidence) ?? { state: 'exited' };
				},
			},
			liveIdentity: {
				readCurrentRunIdentity: async (): Promise<BridgeLocalFirstProofRunIdentity> => {
					const identity =
						props.liveIdentities?.[liveIdentityReadCount] ??
						props.liveIdentities?.at(-1) ??
						runIdentity;
					liveIdentityReadCount += 1;
					return structuredClone(identity);
				},
			},
			provenance: {
				readCurrentRunIdentity: async () => {
					const identity =
						props.liveIdentities?.[provenanceIdentityReadCount] ??
						props.liveIdentities?.at(-1) ??
						runIdentity;
					provenanceIdentityReadCount += 1;
					return { state: 'verified' as const, identity: structuredClone(identity) };
				},
				inspectLaunchProvenance: async (launchId) =>
					props.launchProvenance?.(launchId) ?? verifiedLaunchProvenance(launchId),
			},
		},
	};
}

async function expectValidationFailure(fixture: TestFixture, message: RegExp): Promise<void> {
	await expect(
		validateBridgeLocalFirstPerformance({ manifestPath, ports: fixture.ports }),
	).rejects.toThrow(message);
}

function componentForRuntime(
	runtime: BridgeLocalFirstProofRuntime,
): DeepMutable<BridgeLocalFirstProofCohortInput> {
	return {
		schemaVersion: 1,
		runIdentity: structuredClone(runIdentity),
		cells: structuredClone(
			completeCohort.cells.filter((cell) => cell.identity.runtime === runtime),
		),
	};
}

function cloneBrowserComponent(): DeepMutable<BridgeLocalFirstProofCohortInput> {
	return structuredClone(baseBrowserComponent);
}

function cloneNativeComponent(): DeepMutable<BridgeLocalFirstProofCohortInput> {
	return structuredClone(baseNativeComponent);
}

function reductionWithBoundaryDuration(
	scope: 'launch' | 'pooled' | 'worst-launch',
	durationField: 'p95DurationMilliseconds' | 'p99DurationMilliseconds',
	durationMilliseconds: number,
): typeof validatedCompleteReduction {
	const baseCell = requiredValue(validatedCompleteReduction.cells[0]);
	const boundaryCell =
		scope === 'launch'
			? {
					...baseCell,
					launches: [
						{
							...requiredValue(baseCell.launches[0]),
							[durationField]: durationMilliseconds,
						},
						...baseCell.launches.slice(1),
					],
				}
			: scope === 'pooled'
				? {
						...baseCell,
						pooled: { ...baseCell.pooled, [durationField]: durationMilliseconds },
					}
				: {
						...baseCell,
						worstLaunch: {
							...baseCell.worstLaunch,
							[durationField]: durationMilliseconds,
						},
					};
	return {
		...validatedCompleteReduction,
		cells: [boundaryCell, ...validatedCompleteReduction.cells.slice(1)],
	};
}

function internalSloBoundaryCell(
	boundary: 'commQueue' | 'mainToPierre',
	durationMilliseconds: number,
	selection: 'all' | 'last-two',
): BridgeLocalFirstValidatedProofCohort['cells'][number] {
	const spanKind = boundary === 'commQueue' ? 'selected_comm_queue' : 'main_to_pierre';
	const cell = requiredValue(
		validatedCompleteCohort.cells.find((candidate) => {
			if (candidate.identity.telemetryState !== 'on') return false;
			const applicability = bridgeLocalFirstProofApplicabilityByCellId.get(
				candidate.identity.cellId,
			);
			return boundary === 'commQueue'
				? applicability?.selectedCommQueue === 'required' &&
						candidate.identity.family.endsWith('terminal-availability')
				: applicability?.pierreSubmission === 'required' &&
						candidate.identity.sourceCacheState === 'cold-miss';
		}),
	);
	const launch = requiredValue(cell.launches[0]);
	const selectedAttemptIndexes =
		selection === 'all' ? [...launch.attempts.keys()] : [...launch.attempts.keys()].slice(-2);
	const selectedAttemptIndexSet = new Set(selectedAttemptIndexes);
	const boundaryLaunch = {
		...launch,
		// oxlint-disable-next-line oxc(no-map-spread) -- Preserve the validated fixture while replacing only boundary timestamps.
		interactionEvidence: launch.interactionEvidence.map((evidence, attemptIndex) => {
			if (evidence.internal.mode !== 'on') {
				throw new Error('test fixture expected telemetry-on internal evidence');
			}
			return {
				...evidence,
				internal: {
					...evidence.internal,
					spans: evidence.internal.spans.map((span) =>
						span.kind === spanKind
							? {
									...span,
									completedAtMonotonicMilliseconds:
										span.startedAtMonotonicMilliseconds +
										(selectedAttemptIndexSet.has(attemptIndex) ? durationMilliseconds : 1),
								}
							: span,
					),
				},
			};
		}),
	};
	return {
		...cell,
		launches: [boundaryLaunch, ...cell.launches.slice(1)],
	};
}

function verifiedLaunchProvenance(launchId: string): BridgeLocalFirstVerifiedLaunchProvenance {
	const cell = requiredValue(
		completeCohort.cells.find((candidate) =>
			candidate.launches.some((launch) => launch.identity.launchId === launchId),
		),
	);
	const launch = requiredValue(
		cell.launches.find((candidate) => candidate.identity.launchId === launchId),
	);
	const applicability = requiredValue(
		bridgeLocalFirstProofApplicabilityByCellId.get(cell.identity.cellId),
	);
	const receiptId = (kind: string): string => `${launchId}:provenance:${kind}`;
	return {
		state: 'verified',
		launchId,
		processInstanceId: launch.identity.processInstanceId,
		runningReceipt: {
			runningEventId: receiptId('running'),
			processId: launch.identity.processId,
			processStartToken: launch.identity.processStartToken,
			executableSha256: launch.identity.executableSha256,
		},
		exitReceipt: {
			processInstanceId: launch.identity.processInstanceId,
			exitEventId: receiptId('exit'),
		},
		cachePreparationReceipt: {
			requirement: applicability.cachePreparationRequirement,
			receiptId: receiptId('cache'),
		},
		runtimeReadyReceipt: { eventId: receiptId('ready') },
		telemetryTopologyReceipt: {
			telemetryState: cell.identity.telemetryState,
			topology: cell.identity.telemetryState === 'on' ? 'separate_worker' : 'absent',
			receiptId: receiptId('telemetry'),
		},
		packagedBundleReceipt:
			launch.identity.runtimeProcessIdentity.runtime === 'controlled_dev_chromium'
				? { runtime: 'controlled_dev_chromium', receiptId: receiptId('bundle') }
				: {
						runtime: 'packaged_wkwebview',
						bundleIdentifier: launch.identity.runtimeProcessIdentity.bundleIdentifier,
						bundleHash: launch.identity.runtimeProcessIdentity.bundleHash,
						receiptId: receiptId('bundle'),
					},
	};
}

function encodeJson(value: string): Uint8Array {
	return new TextEncoder().encode(value);
}

function sha256(bytes: Uint8Array): string {
	return createHash('sha256').update(bytes).digest('hex');
}

function refreshRunIdentityHashes(identity: DeepMutable<BridgeLocalFirstProofRunIdentity>): void {
	identity.runManifestHash = bridgeLocalFirstProofRunManifestHash(identity);
	identity.runIdentityFingerprint = bridgeLocalFirstProofRunIdentityFingerprint(identity);
}

function yieldToVitestWorkerRpc(): Promise<void> {
	return new Promise((completeYield): void => {
		setImmediate(completeYield);
	});
}

function requiredValue<TValue>(value: TValue | undefined): TValue {
	if (value === undefined) {
		throw new Error('unit-test fixture expected value');
	}
	return value;
}

type DeepMutable<TValue> = BridgeLocalFirstTestDeepMutable<TValue>;
