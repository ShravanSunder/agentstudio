import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, realpath } from 'node:fs/promises';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { parseArgs } from 'node:util';

import { z } from 'zod';

import {
	bridgeLocalFirstProofApplicabilityByCellId,
	bridgeLocalFirstProofCells,
	bridgeLocalFirstProofMinimumMeasuredAttemptCount,
	bridgeLocalFirstProofRequiredCellCount,
	bridgeLocalFirstProofRequiredLaunchCount,
	bridgeLocalFirstProofRunIdentitySchema,
	bridgeLocalFirstProofRuntimes,
	parseBridgeLocalFirstProofCohort,
	type BridgeLocalFirstProofCachePreparationRequirement,
	type BridgeLocalFirstProofCellContract,
	type BridgeLocalFirstProofRunIdentity,
	type BridgeLocalFirstProofRuntime,
	type BridgeLocalFirstValidatedProofCohort,
} from './bridge-local-first-proof-contract.ts';
import {
	parseBridgeLocalFirstProofFixtureOracle,
	type BridgeLocalFirstValidatedFixtureOracle,
} from './bridge-local-first-proof-evidence.ts';
import {
	bridgeLocalFirstProofProvenanceJournalSchema,
	bridgeLocalFirstVerifiedLaunchProvenanceSchema,
	type BridgeLocalFirstProofProvenanceJournal,
	type BridgeLocalFirstProofProvenancePort,
	type BridgeLocalFirstVerifiedLaunchProvenance,
} from './bridge-local-first-proof-provenance.ts';
import {
	reduceBridgeLocalFirstValidatedProofCohort,
	type BridgeLocalFirstProofCohortReduction,
	validateBridgeLocalFirstInternalSloBudgets,
} from './bridge-local-first-proof-reducer.ts';

const sha256Schema = z.string().regex(/^[a-f0-9]{64}$/u);
const componentDescriptorSchema = z
	.object({
		relativePath: z.string().min(1),
		sha256: sha256Schema,
	})
	.strict()
	.readonly();
const aggregateComponentDescriptorsSchema = z
	.object({
		controlled_dev_chromium: componentDescriptorSchema,
		packaged_wkwebview: componentDescriptorSchema,
	})
	.strict()
	.readonly();
const aggregateManifestFingerprintFactsSchema = z
	.object({
		schemaVersion: z.literal(1),
		runIdentityFingerprint: sha256Schema,
		components: aggregateComponentDescriptorsSchema,
		fixtureOracle: componentDescriptorSchema,
	})
	.strict()
	.readonly();
const aggregateManifestSchema = z
	.object({
		schemaVersion: z.literal(1),
		runIdentityFingerprint: sha256Schema,
		components: aggregateComponentDescriptorsSchema,
		fixtureOracle: componentDescriptorSchema,
		aggregateManifestFingerprint: sha256Schema,
	})
	.strict()
	.readonly();
const componentEnvelopeSchema = z
	.object({
		schemaVersion: z.literal(1),
		runIdentity: bridgeLocalFirstProofRunIdentitySchema,
		cells: z.array(z.unknown()).readonly(),
	})
	.strict()
	.readonly();
const componentCellPartitionSchema = z
	.object({
		identity: z
			.object({
				cellId: z.string().min(1),
				runtime: z.enum(bridgeLocalFirstProofRuntimes),
			})
			.passthrough(),
	})
	.passthrough();

type ComponentDescriptor = z.output<typeof componentDescriptorSchema>;
type ComponentEnvelope = z.output<typeof componentEnvelopeSchema>;
type ValidatedLaunchIdentity =
	BridgeLocalFirstValidatedProofCohort['cells'][number]['launches'][number]['identity'];
export type BridgeLocalFirstProcessInstanceEvidence = Pick<
	ValidatedLaunchIdentity,
	| 'executableSha256'
	| 'launchId'
	| 'processId'
	| 'processInstanceId'
	| 'processStartToken'
	| 'runtimeProcessIdentity'
>;

export interface BridgeLocalFirstProofFileIdentityPort {
	readonly canonicalizePath: (filePath: string) => Promise<string>;
	readonly readBytes: (filePath: string) => Promise<Uint8Array>;
}

export type BridgeLocalFirstProcessIdentityObservation =
	| { readonly state: 'exited' }
	| {
			readonly state: 'running';
			readonly processStartToken: string;
			readonly executableSha256: string;
	  }
	| { readonly state: 'indeterminate'; readonly reason: string };

export interface BridgeLocalFirstProcessIdentityPort {
	readonly inspectProcessIdentity: (
		evidence: BridgeLocalFirstProcessInstanceEvidence,
	) => Promise<BridgeLocalFirstProcessIdentityObservation>;
}

export interface BridgeLocalFirstLiveIdentityPort {
	readonly readCurrentRunIdentity: () => Promise<BridgeLocalFirstProofRunIdentity>;
}

export interface BridgeLocalFirstPerformanceValidationPorts {
	readonly files: BridgeLocalFirstProofFileIdentityPort;
	readonly liveIdentity: BridgeLocalFirstLiveIdentityPort;
	readonly processes: BridgeLocalFirstProcessIdentityPort;
	readonly provenance: BridgeLocalFirstProofProvenancePort;
}

export interface BridgeLocalFirstPerformanceArguments {
	readonly manifestPath: string;
	readonly validateOnly: true;
}

export interface ValidateBridgeLocalFirstPerformanceProps {
	readonly manifestPath: string;
	readonly ports?: BridgeLocalFirstPerformanceValidationPorts;
}

export interface BridgeLocalFirstPerformanceValidationResult {
	readonly manifestPath: string;
	readonly reduction: BridgeLocalFirstProofCohortReduction;
}

export function bridgeLocalFirstProofAggregateManifestFingerprint(
	manifestFactsInput: z.input<typeof aggregateManifestFingerprintFactsSchema>,
): string {
	const manifestFacts = aggregateManifestFingerprintFactsSchema.parse(manifestFactsInput);
	return createHash('sha256').update(JSON.stringify(manifestFacts)).digest('hex');
}

const repoRootPath = fileURLToPath(new URL('../../', import.meta.url));
const defaultManifestPath = resolve(repoRootPath, 'tmp/bridge-local-first-proof/latest.json');
export function parseBridgeLocalFirstPerformanceArguments(
	argumentsToParse: readonly string[],
): BridgeLocalFirstPerformanceArguments {
	try {
		const parsedArguments = parseArgs({
			args: [...argumentsToParse],
			allowPositionals: false,
			options: {
				'validate-only': { type: 'boolean' },
				manifest: { type: 'string' },
			},
			strict: true,
			tokens: true,
		});
		const validateOnlyTokens = parsedArguments.tokens.filter(
			(token) => token.kind === 'option' && token.name === 'validate-only',
		);
		const manifestTokens = parsedArguments.tokens.filter(
			(token) => token.kind === 'option' && token.name === 'manifest',
		);
		if (parsedArguments.values['validate-only'] !== true || validateOnlyTokens.length !== 1) {
			throw new Error('the validator requires exactly one --validate-only flag');
		}
		if (manifestTokens.length > 1) {
			throw new Error('--manifest may be supplied at most once');
		}
		const manifestPath = parsedArguments.values.manifest ?? defaultManifestPath;
		if (manifestPath.trim().length === 0) {
			throw new Error('--manifest requires a nonempty path');
		}
		return Object.freeze({ manifestPath, validateOnly: true });
	} catch (error: unknown) {
		throw new Error(`invalid validate-only arguments: ${errorMessage(error)}`, { cause: error });
	}
}

export async function validateBridgeLocalFirstPerformance(
	props: ValidateBridgeLocalFirstPerformanceProps,
): Promise<BridgeLocalFirstPerformanceValidationResult> {
	const ports = props.ports ?? (await defaultPerformanceValidationPorts());
	const initialLiveIdentity = bridgeLocalFirstProofRunIdentitySchema.parse(
		await ports.liveIdentity.readCurrentRunIdentity(),
	);
	await validateIndependentRunIdentity(ports.provenance, initialLiveIdentity);
	const manifestPath = await ports.files.canonicalizePath(resolve(props.manifestPath));
	const proofRootPath = await ports.files.canonicalizePath(dirname(manifestPath));
	const aggregateManifest = aggregateManifestSchema.parse(
		parseJsonBytes(await ports.files.readBytes(manifestPath), manifestPath),
	);
	const expectedAggregateFingerprint = bridgeLocalFirstProofAggregateManifestFingerprint({
		schemaVersion: aggregateManifest.schemaVersion,
		runIdentityFingerprint: aggregateManifest.runIdentityFingerprint,
		components: aggregateManifest.components,
		fixtureOracle: aggregateManifest.fixtureOracle,
	});
	if (aggregateManifest.aggregateManifestFingerprint !== expectedAggregateFingerprint) {
		throw new Error('aggregate manifest fingerprint does not match artifact descriptors');
	}
	const fixtureOracle = await loadFixtureOracle({
		descriptor: aggregateManifest.fixtureOracle,
		files: ports.files,
		proofRootPath,
		runIdentity: initialLiveIdentity,
	});
	const loadedComponents = await Promise.all(
		bridgeLocalFirstProofRuntimes.map(async (runtime) => {
			const descriptor = aggregateManifest.components[runtime];
			const componentPath = await resolveContainedArtifactPath({
				descriptor,
				files: ports.files,
				proofRootPath,
			});
			const componentBytes = await ports.files.readBytes(componentPath);
			const actualHash = sha256(componentBytes);
			if (actualHash !== descriptor.sha256) {
				throw new Error(`${runtime}: component SHA-256 mismatch`);
			}
			const envelope = componentEnvelopeSchema.parse(parseJsonBytes(componentBytes, componentPath));
			validateRuntimePartition(envelope, runtime);
			return { componentPath, descriptor, envelope, runtime } as const;
		}),
	);
	if (loadedComponents[0]?.componentPath === loadedComponents[1]?.componentPath) {
		throw new Error('runtime components must reference distinct files');
	}
	if (loadedComponents.some((component) => component.componentPath === fixtureOracle.path)) {
		throw new Error('fixture oracle must reference a distinct file');
	}

	const browserComponent = requiredValue(loadedComponents[0], 'controlled Chromium component');
	const nativeComponent = requiredValue(loadedComponents[1], 'packaged WKWebView component');
	validateMatchingRunIdentities(browserComponent.envelope, nativeComponent.envelope);
	if (
		aggregateManifest.runIdentityFingerprint !==
		browserComponent.envelope.runIdentity.runIdentityFingerprint
	) {
		throw new Error('aggregate manifest is bound to a different run identity');
	}
	const rawCombinedCohort = {
		schemaVersion: 1 as const,
		runIdentity: browserComponent.envelope.runIdentity,
		cells: [...browserComponent.envelope.cells, ...nativeComponent.envelope.cells],
	};
	const cohort = parseBridgeLocalFirstProofCohort(
		rawCombinedCohort,
		initialLiveIdentity,
		fixtureOracle.oracle,
	);
	const reduction = reduceBridgeLocalFirstValidatedProofCohort(cohort);
	validateReductionBudgets(reduction);
	validateBridgeLocalFirstInternalSloBudgets(cohort);
	const seenProvenanceReceiptIds = new Set<string>();
	await Promise.all(
		loadedComponents.map((component) =>
			validateComponentProcessInstances({
				cohort,
				processes: ports.processes,
				provenance: ports.provenance,
				runtime: component.runtime,
				seenReceiptIds: seenProvenanceReceiptIds,
			}),
		),
	);
	const finalLiveIdentity = bridgeLocalFirstProofRunIdentitySchema.parse(
		await ports.liveIdentity.readCurrentRunIdentity(),
	);
	if (JSON.stringify(finalLiveIdentity) !== JSON.stringify(initialLiveIdentity)) {
		throw new Error('live run identity changed during validation');
	}
	await validateIndependentRunIdentity(ports.provenance, finalLiveIdentity);
	return Object.freeze({ manifestPath, reduction });
}

async function loadFixtureOracle(props: {
	readonly descriptor: ComponentDescriptor;
	readonly files: BridgeLocalFirstProofFileIdentityPort;
	readonly proofRootPath: string;
	readonly runIdentity: BridgeLocalFirstProofRunIdentity;
}): Promise<{ readonly oracle: BridgeLocalFirstValidatedFixtureOracle; readonly path: string }> {
	const oraclePath = await resolveContainedArtifactPath(props);
	const oracleBytes = await props.files.readBytes(oraclePath);
	if (sha256(oracleBytes) !== props.descriptor.sha256) {
		throw new Error('fixture oracle SHA-256 mismatch');
	}
	return {
		oracle: parseBridgeLocalFirstProofFixtureOracle({
			expectedFixtureChecksum: props.runIdentity.fixtureChecksum,
			expectedFixtureId: props.runIdentity.fixtureId,
			rawOracle: parseJsonBytes(oracleBytes, oraclePath),
		}),
		path: oraclePath,
	};
}

async function resolveContainedArtifactPath(props: {
	readonly descriptor: ComponentDescriptor;
	readonly files: BridgeLocalFirstProofFileIdentityPort;
	readonly proofRootPath: string;
}): Promise<string> {
	const componentRelativePath = props.descriptor.relativePath;
	if (
		isAbsolute(componentRelativePath) ||
		componentRelativePath.includes('\\') ||
		componentRelativePath.includes('\0')
	) {
		throw new Error(`component path must be a relative POSIX path: ${componentRelativePath}`);
	}
	const unresolvedComponentPath = resolve(props.proofRootPath, componentRelativePath);
	if (!isPathContainedByRoot(props.proofRootPath, unresolvedComponentPath)) {
		throw new Error(`component path escapes proof root: ${componentRelativePath}`);
	}
	const componentPath = await props.files.canonicalizePath(unresolvedComponentPath);
	if (!isPathContainedByRoot(props.proofRootPath, componentPath)) {
		throw new Error(`component canonical path escapes proof root: ${componentRelativePath}`);
	}
	return componentPath;
}

function isPathContainedByRoot(rootPath: string, candidatePath: string): boolean {
	const relativePath = relative(rootPath, candidatePath);
	return (
		relativePath.length > 0 &&
		!isAbsolute(relativePath) &&
		relativePath !== '..' &&
		!relativePath.startsWith(`..${sep}`)
	);
}

function validateRuntimePartition(
	envelope: ComponentEnvelope,
	runtime: BridgeLocalFirstProofRuntime,
): void {
	const expectedCellIds = new Set(
		bridgeLocalFirstProofCells
			.filter((cell) => cell.runtime === runtime)
			.map((cell) => cell.cellId),
	);
	if (envelope.cells.length !== expectedCellIds.size) {
		throw new Error(
			`${runtime}: component must contain exactly ${expectedCellIds.size} runtime cells, got ${envelope.cells.length}`,
		);
	}
	const observedCellIds = new Set<string>();
	for (const rawCell of envelope.cells) {
		const cell = componentCellPartitionSchema.parse(rawCell);
		if (cell.identity.runtime !== runtime) {
			throw new Error(`${runtime}: component contains ${cell.identity.runtime} cell`);
		}
		if (!expectedCellIds.has(cell.identity.cellId) || observedCellIds.has(cell.identity.cellId)) {
			throw new Error(`${runtime}: invalid or duplicate runtime cell ${cell.identity.cellId}`);
		}
		observedCellIds.add(cell.identity.cellId);
	}
}

function validateMatchingRunIdentities(left: ComponentEnvelope, right: ComponentEnvelope): void {
	if (left.runIdentity.runIdentityFingerprint !== right.runIdentity.runIdentityFingerprint) {
		throw new Error('runtime components have different run identity fingerprints');
	}
	if (JSON.stringify(left.runIdentity) !== JSON.stringify(right.runIdentity)) {
		throw new Error('runtime components have different run identities');
	}
}

function validateReductionBudgets(reduction: BridgeLocalFirstProofCohortReduction): void {
	if (
		reduction.totals.cellCount !== bridgeLocalFirstProofRequiredCellCount ||
		reduction.totals.launchCount !== bridgeLocalFirstProofRequiredLaunchCount ||
		reduction.totals.measuredAttemptCount < bridgeLocalFirstProofMinimumMeasuredAttemptCount
	) {
		throw new Error('aggregate reduction does not satisfy the closed cohort cardinality');
	}
	if (reduction.totals.failureCount !== 0) {
		throw new Error(`aggregate has ${reduction.totals.failureCount} correctness failures`);
	}
	const cellContracts = new Map(bridgeLocalFirstProofCells.map((cell) => [cell.cellId, cell]));
	for (const cell of reduction.cells) {
		const contract = cellContracts.get(cell.identity.cellId);
		if (contract === undefined) {
			throw new Error(`reduction contains unknown cell ${cell.identity.cellId}`);
		}
		const p95BudgetMilliseconds = p95BudgetForCell(contract);
		for (const launch of cell.launches) {
			validatePercentileBudget({
				label: `${cell.identity.cellId}/${launch.launchId}`,
				p95BudgetMilliseconds,
				p95DurationMilliseconds: launch.p95DurationMilliseconds,
				p99BudgetMilliseconds: contract.p99BudgetMilliseconds,
				p99DurationMilliseconds: launch.p99DurationMilliseconds,
			});
		}
		validatePercentileBudget({
			label: `${cell.identity.cellId}/pooled`,
			p95BudgetMilliseconds,
			p95DurationMilliseconds: cell.pooled.p95DurationMilliseconds,
			p99BudgetMilliseconds: contract.p99BudgetMilliseconds,
			p99DurationMilliseconds: cell.pooled.p99DurationMilliseconds,
		});
		validatePercentileBudget({
			label: `${cell.identity.cellId}/worst-launch`,
			p95BudgetMilliseconds,
			p95DurationMilliseconds: cell.worstLaunch.p95DurationMilliseconds,
			p99BudgetMilliseconds: contract.p99BudgetMilliseconds,
			p99DurationMilliseconds: cell.worstLaunch.p99DurationMilliseconds,
		});
	}
}

function p95BudgetForCell(cell: BridgeLocalFirstProofCellContract): number {
	if (cell.p99BudgetMilliseconds === 32) {
		return 32;
	}
	return cell.runtime === 'controlled_dev_chromium' ? 50 : 100;
}

function validatePercentileBudget(props: {
	readonly label: string;
	readonly p95BudgetMilliseconds: number;
	readonly p95DurationMilliseconds: number;
	readonly p99BudgetMilliseconds: number;
	readonly p99DurationMilliseconds: number;
}): void {
	if (props.p95DurationMilliseconds >= props.p95BudgetMilliseconds) {
		throw new Error(
			`${props.label}: p95 ${props.p95DurationMilliseconds} ms does not satisfy < ${props.p95BudgetMilliseconds} ms`,
		);
	}
	if (props.p99DurationMilliseconds >= props.p99BudgetMilliseconds) {
		throw new Error(
			`${props.label}: p99 ${props.p99DurationMilliseconds} ms does not satisfy < ${props.p99BudgetMilliseconds} ms`,
		);
	}
}

async function validateComponentProcessInstances(props: {
	readonly cohort: ReturnType<typeof parseBridgeLocalFirstProofCohort>;
	readonly processes: BridgeLocalFirstProcessIdentityPort;
	readonly provenance: BridgeLocalFirstProofProvenancePort;
	readonly runtime: BridgeLocalFirstProofRuntime;
	readonly seenReceiptIds: Set<string>;
}): Promise<void> {
	const launches = props.cohort.cells
		.filter((cell) => cell.identity.runtime === props.runtime)
		.flatMap((cell) => {
			const applicability = bridgeLocalFirstProofApplicabilityByCellId.get(cell.identity.cellId);
			if (applicability === undefined) {
				throw new Error(`${cell.identity.cellId}: missing provenance applicability`);
			}
			return cell.launches.map((launch) => ({
				cachePreparationRequirement: applicability.cachePreparationRequirement,
				evidence: launch.identity,
				telemetryState: cell.identity.telemetryState,
			}));
		});
	await validateLaunchProcessInstances({
		launchIndex: 0,
		launches,
		processes: props.processes,
		provenance: props.provenance,
		seenReceiptIds: props.seenReceiptIds,
	});
}

async function validateLaunchProcessInstances(props: {
	readonly launchIndex: number;
	readonly launches: readonly {
		readonly cachePreparationRequirement: BridgeLocalFirstProofCachePreparationRequirement;
		readonly evidence: ValidatedLaunchIdentity;
		readonly telemetryState: 'off' | 'on';
	}[];
	readonly processes: BridgeLocalFirstProcessIdentityPort;
	readonly provenance: BridgeLocalFirstProofProvenancePort;
	readonly seenReceiptIds: Set<string>;
}): Promise<void> {
	const launch = props.launches[props.launchIndex];
	if (launch === undefined) {
		return;
	}
	const evidence: BridgeLocalFirstProcessInstanceEvidence = launch.evidence;
	const provenance = await props.provenance.inspectLaunchProvenance(evidence.launchId);
	validateLaunchProvenance({
		cachePreparationRequirement: launch.cachePreparationRequirement,
		evidence: launch.evidence,
		observation: provenance,
		seenReceiptIds: props.seenReceiptIds,
		telemetryState: launch.telemetryState,
	});
	const observation = await props.processes.inspectProcessIdentity(evidence);
	validateProcessObservation(evidence, observation);
	await validateLaunchProcessInstances({ ...props, launchIndex: props.launchIndex + 1 });
}

function validateLaunchProvenance(props: {
	readonly cachePreparationRequirement: BridgeLocalFirstProofCachePreparationRequirement;
	readonly evidence: ValidatedLaunchIdentity;
	readonly observation: Awaited<
		ReturnType<BridgeLocalFirstProofProvenancePort['inspectLaunchProvenance']>
	>;
	readonly seenReceiptIds: Set<string>;
	readonly telemetryState: 'off' | 'on';
}): void {
	if (props.observation.state !== 'verified') {
		throw new Error(
			`${props.evidence.launchId}: launch provenance is unverified: ${props.observation.reason}`,
		);
	}
	const provenance = bridgeLocalFirstVerifiedLaunchProvenanceSchema.parse(props.observation);
	const running = provenance.runningReceipt;
	if (
		provenance.launchId !== props.evidence.launchId ||
		provenance.processInstanceId !== props.evidence.processInstanceId ||
		running.processId !== props.evidence.processId ||
		normalizeProcessStartToken(running.processStartToken) !==
			normalizeProcessStartToken(props.evidence.processStartToken) ||
		running.executableSha256 !== props.evidence.executableSha256 ||
		provenance.exitReceipt.processInstanceId !== props.evidence.processInstanceId
	) {
		throw new Error(`${props.evidence.launchId}: independent process provenance mismatch`);
	}
	if (provenance.cachePreparationReceipt.requirement !== props.cachePreparationRequirement) {
		throw new Error(`${props.evidence.launchId}: independent cache preparation mismatch`);
	}
	const topology = props.telemetryState === 'on' ? 'separate_worker' : 'absent';
	if (
		provenance.telemetryTopologyReceipt.telemetryState !== props.telemetryState ||
		provenance.telemetryTopologyReceipt.topology !== topology
	) {
		throw new Error(`${props.evidence.launchId}: independent telemetry topology mismatch`);
	}
	validateBundleProvenance(props.evidence, provenance);
	for (const receiptId of [
		running.runningEventId,
		provenance.exitReceipt.exitEventId,
		provenance.cachePreparationReceipt.receiptId,
		provenance.runtimeReadyReceipt.eventId,
		provenance.telemetryTopologyReceipt.receiptId,
		provenance.packagedBundleReceipt.receiptId,
	]) {
		if (props.seenReceiptIds.has(receiptId)) {
			throw new Error(`${props.evidence.launchId}: reused independent provenance receipt`);
		}
		props.seenReceiptIds.add(receiptId);
	}
}

function validateBundleProvenance(
	evidence: ValidatedLaunchIdentity,
	provenance: BridgeLocalFirstVerifiedLaunchProvenance,
): void {
	const expected = evidence.runtimeProcessIdentity;
	const observed = provenance.packagedBundleReceipt;
	if (expected.runtime !== observed.runtime) {
		throw new Error(`${evidence.launchId}: independent runtime binding mismatch`);
	}
	if (
		expected.runtime === 'packaged_wkwebview' &&
		observed.runtime === 'packaged_wkwebview' &&
		(expected.bundleIdentifier !== observed.bundleIdentifier ||
			expected.bundleHash !== observed.bundleHash)
	) {
		throw new Error(`${evidence.launchId}: independent bundle binding mismatch`);
	}
}

async function validateIndependentRunIdentity(
	provenance: BridgeLocalFirstProofProvenancePort,
	expectedIdentity: BridgeLocalFirstProofRunIdentity,
): Promise<void> {
	const observation = await provenance.readCurrentRunIdentity();
	if (observation.state !== 'verified') {
		throw new Error(`run provenance is unverified: ${observation.reason}`);
	}
	const identity = bridgeLocalFirstProofRunIdentitySchema.parse(observation.identity);
	if (JSON.stringify(identity) !== JSON.stringify(expectedIdentity)) {
		throw new Error('independent provenance run identity mismatch');
	}
}

async function defaultPerformanceValidationPorts(): Promise<BridgeLocalFirstPerformanceValidationPorts> {
	const provenanceJournal = await readProvenanceJournalFromEnvironment();
	return {
		files: { canonicalizePath: realpath, readBytes: readFile },
		liveIdentity: { readCurrentRunIdentity: readLiveRunIdentityFromEnvironment },
		processes: { inspectProcessIdentity: inspectOperatingSystemProcessIdentity },
		provenance: provenancePortFromJournal(provenanceJournal),
	};
}

function provenancePortFromJournal(
	journal: BridgeLocalFirstProofProvenanceJournal,
): BridgeLocalFirstProofProvenancePort {
	const launches = new Map<string, BridgeLocalFirstVerifiedLaunchProvenance>();
	for (const launch of journal.launches) {
		if (launches.has(launch.launchId)) {
			throw new Error(`duplicate launch provenance: ${launch.launchId}`);
		}
		launches.set(launch.launchId, launch);
	}
	return {
		readCurrentRunIdentity: async () => ({ state: 'verified', identity: journal.runIdentity }),
		inspectLaunchProvenance: async (launchId) =>
			launches.get(launchId) ?? {
				state: 'unverified',
				reason: `launch journal has no receipt for ${launchId}`,
			},
	};
}

async function readProvenanceJournalFromEnvironment(): Promise<BridgeLocalFirstProofProvenanceJournal> {
	const journalPath = process.env['AGENTSTUDIO_BRIDGE_LOCAL_FIRST_PROVENANCE_PATH'];
	if (journalPath === undefined || journalPath.trim().length === 0) {
		throw new Error(
			'AGENTSTUDIO_BRIDGE_LOCAL_FIRST_PROVENANCE_PATH must identify an independent launch journal',
		);
	}
	const canonicalJournalPath = await realpath(resolve(journalPath));
	return bridgeLocalFirstProofProvenanceJournalSchema.parse(
		parseJsonBytes(await readFile(canonicalJournalPath), canonicalJournalPath),
	);
}

function validateProcessObservation(
	evidence: BridgeLocalFirstProcessInstanceEvidence,
	observation: BridgeLocalFirstProcessIdentityObservation,
): void {
	if (observation.state === 'exited') {
		return;
	}
	if (observation.state === 'indeterminate') {
		throw new Error(
			`${evidence.launchId}: process identity is indeterminate: ${observation.reason}`,
		);
	}
	const observedProcessStartToken = normalizeProcessStartToken(observation.processStartToken);
	if (
		observedProcessStartToken.length === 0 ||
		!sha256Schema.safeParse(observation.executableSha256).success
	) {
		throw new Error(`${evidence.launchId}: live PID returned an invalid process identity`);
	}
	if (observedProcessStartToken !== normalizeProcessStartToken(evidence.processStartToken)) {
		return;
	}
	if (observation.executableSha256 !== evidence.executableSha256) {
		throw new Error(`${evidence.launchId}: live PID has an indeterminate executable identity`);
	}
	throw new Error(`${evidence.launchId}: owned process instance is still live`);
}

async function inspectOperatingSystemProcessIdentity(
	evidence: BridgeLocalFirstProcessInstanceEvidence,
): Promise<BridgeLocalFirstProcessIdentityObservation> {
	const initialStartToken = await readProcessStartToken(evidence.processId);
	if (initialStartToken.state !== 'running') {
		return initialStartToken;
	}
	let executablePath: string;
	try {
		const stdout = await executeFile('lsof', [
			'-a',
			'-p',
			String(evidence.processId),
			'-d',
			'txt',
			'-Fn',
		]);
		executablePath =
			stdout
				.split(/\r?\n/u)
				.find((line) => line.startsWith('n'))
				?.slice(1) ?? '';
	} catch (error: unknown) {
		const secondStartToken = await readProcessStartToken(evidence.processId);
		return secondStartToken.state === 'exited'
			? secondStartToken
			: { state: 'indeterminate', reason: `executable inspection failed: ${errorMessage(error)}` };
	}
	if (executablePath.length === 0) {
		return { state: 'indeterminate', reason: 'live process executable path is unavailable' };
	}
	try {
		const executableHash = sha256(await readFile(executablePath));
		const finalStartToken = await readProcessStartToken(evidence.processId);
		if (finalStartToken.state !== 'running') {
			return finalStartToken;
		}
		return {
			state: 'running',
			processStartToken: finalStartToken.processStartToken,
			executableSha256: executableHash,
		};
	} catch (error: unknown) {
		return {
			state: 'indeterminate',
			reason: `live process executable hash failed: ${errorMessage(error)}`,
		};
	}
}

async function readLiveRunIdentityFromEnvironment(): Promise<BridgeLocalFirstProofRunIdentity> {
	const liveIdentityPath = process.env['AGENTSTUDIO_BRIDGE_LOCAL_FIRST_LIVE_IDENTITY_PATH'];
	if (liveIdentityPath === undefined || liveIdentityPath.trim().length === 0) {
		throw new Error(
			'AGENTSTUDIO_BRIDGE_LOCAL_FIRST_LIVE_IDENTITY_PATH must identify independent live facts',
		);
	}
	const canonicalLiveIdentityPath = await realpath(resolve(liveIdentityPath));
	return bridgeLocalFirstProofRunIdentitySchema.parse(
		parseJsonBytes(await readFile(canonicalLiveIdentityPath), canonicalLiveIdentityPath),
	);
}

async function readProcessStartToken(
	processId: number,
): Promise<
	| { readonly state: 'exited' }
	| { readonly state: 'running'; readonly processStartToken: string }
	| { readonly state: 'indeterminate'; readonly reason: string }
> {
	try {
		const stdout = await executeFile('ps', ['-p', String(processId), '-o', 'lstart=']);
		const processStartToken = normalizeProcessStartToken(stdout);
		return processStartToken.length === 0
			? { state: 'exited' }
			: { state: 'running', processStartToken };
	} catch (error: unknown) {
		return isMissingProcessResult(error)
			? { state: 'exited' }
			: { state: 'indeterminate', reason: `process inspection failed: ${errorMessage(error)}` };
	}
}

class ReadOnlyCommandError extends Error {
	readonly exitCode: null | number | string | undefined;
	readonly stderr: string;
	readonly stdout: string;

	constructor(props: {
		readonly cause: Error & { readonly code?: null | number | string };
		readonly command: string;
		readonly stderr: string;
		readonly stdout: string;
	}) {
		super(`${props.command} failed: ${props.cause.message}`, { cause: props.cause });
		this.exitCode = props.cause.code;
		this.stderr = props.stderr;
		this.stdout = props.stdout;
	}
}

function executeFile(command: string, argumentsToPass: readonly string[]): Promise<string> {
	return new Promise((resolvePromise, rejectPromise): void => {
		execFile(command, [...argumentsToPass], { encoding: 'utf8' }, (error, stdout, stderr) => {
			if (error !== null) {
				rejectPromise(new ReadOnlyCommandError({ cause: error, command, stderr, stdout }));
				return;
			}
			resolvePromise(stdout);
		});
	});
}

function normalizeProcessStartToken(processStartToken: string): string {
	return processStartToken.trim().replace(/\s+/gu, ' ');
}

function parseJsonBytes(bytes: Uint8Array, sourcePath: string): unknown {
	try {
		const decodedJson = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
		const parsedJson: unknown = JSON.parse(decodedJson);
		return parsedJson;
	} catch (error: unknown) {
		throw new Error(`invalid JSON artifact ${sourcePath}: ${errorMessage(error)}`, {
			cause: error,
		});
	}
}

function sha256(bytes: Uint8Array): string {
	return createHash('sha256').update(bytes).digest('hex');
}

function isMissingProcessResult(error: unknown): boolean {
	return (
		error instanceof ReadOnlyCommandError &&
		error.exitCode === 1 &&
		error.stdout.trim().length === 0 &&
		error.stderr.trim().length === 0
	);
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

function requiredValue<TValue>(value: TValue | undefined, label: string): TValue {
	if (value === undefined) {
		throw new Error(`missing ${label}`);
	}
	return value;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
	try {
		const argumentsForValidation = parseBridgeLocalFirstPerformanceArguments(process.argv.slice(2));
		const result = await validateBridgeLocalFirstPerformance({
			manifestPath: argumentsForValidation.manifestPath,
		});
		console.log(
			`Bridge local-first proof verified: ${result.reduction.totals.cellCount} cells, ${result.reduction.totals.launchCount} launches, ${result.reduction.totals.measuredAttemptCount} attempts`,
		);
	} catch (error: unknown) {
		console.error(errorMessage(error));
		process.exitCode = 1;
	}
}
