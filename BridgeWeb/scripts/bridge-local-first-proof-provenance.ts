import { createHash } from 'node:crypto';

import { z } from 'zod';

import {
	bridgeLocalFirstProofApplicabilityByCellId,
	bridgeLocalFirstProofCells,
	bridgeLocalFirstProofInternalSlo,
	bridgeLocalFirstProofMinimumMeasuredAttemptsPerLaunch,
	bridgeLocalFirstProofRequiredLaunchesPerCell,
} from './bridge-local-first-proof-manifest.ts';

export const bridgeLocalFirstProofSha256Schema = z.string().regex(/^[a-f0-9]{64}$/u);
export const bridgeLocalFirstProofWorkerModeSchema = z.literal('pane-comm-worker');

const bridgeLocalFirstProofRunFactsObjectSchema = z
	.object({
		runId: z.string().min(1),
		headCommitSha: z.string().regex(/^[a-f0-9]{40}$/u),
		dirtyStateHash: bridgeLocalFirstProofSha256Schema,
		packagedBundleHash: bridgeLocalFirstProofSha256Schema,
		fixtureId: z.string().min(1),
		fixtureChecksum: bridgeLocalFirstProofSha256Schema,
		viewport: z
			.object({
				width: z.number().int().positive(),
				height: z.number().int().positive(),
				deviceScaleFactor: z.number().finite().positive(),
			})
			.strict()
			.readonly(),
		machineProfileHash: bridgeLocalFirstProofSha256Schema,
		pierreVersion: z.string().min(1),
		workerMode: bridgeLocalFirstProofWorkerModeSchema,
	})
	.strict();

export const bridgeLocalFirstProofRunFactsSchema =
	bridgeLocalFirstProofRunFactsObjectSchema.readonly();

export const bridgeLocalFirstProofRunIdentitySchema = bridgeLocalFirstProofRunFactsObjectSchema
	.extend({
		runManifestHash: bridgeLocalFirstProofSha256Schema,
		runIdentityFingerprint: bridgeLocalFirstProofSha256Schema,
	})
	.strict()
	.readonly();

export type BridgeLocalFirstProofRunFacts = z.input<typeof bridgeLocalFirstProofRunFactsSchema>;
export type BridgeLocalFirstProofRunIdentity = z.input<
	typeof bridgeLocalFirstProofRunIdentitySchema
>;

function sha256Canonical(value: unknown): string {
	return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

function runFactsFrom(
	runFactsInput: BridgeLocalFirstProofRunFacts,
): z.output<typeof bridgeLocalFirstProofRunFactsSchema> {
	return bridgeLocalFirstProofRunFactsSchema.parse({
		runId: runFactsInput.runId,
		headCommitSha: runFactsInput.headCommitSha,
		dirtyStateHash: runFactsInput.dirtyStateHash,
		packagedBundleHash: runFactsInput.packagedBundleHash,
		fixtureId: runFactsInput.fixtureId,
		fixtureChecksum: runFactsInput.fixtureChecksum,
		viewport: runFactsInput.viewport,
		machineProfileHash: runFactsInput.machineProfileHash,
		pierreVersion: runFactsInput.pierreVersion,
		workerMode: runFactsInput.workerMode,
	});
}

export function bridgeLocalFirstProofRunManifestHash(
	runFactsInput: BridgeLocalFirstProofRunFacts,
): string {
	const runFacts = runFactsFrom(runFactsInput);
	return sha256Canonical({
		schemaVersion: 1,
		runFacts,
		cohort: {
			requiredLaunchesPerCell: bridgeLocalFirstProofRequiredLaunchesPerCell,
			requiredMeasuredAttemptsPerLaunch: bridgeLocalFirstProofMinimumMeasuredAttemptsPerLaunch,
			internalSlo: bridgeLocalFirstProofInternalSlo,
		},
		cells: bridgeLocalFirstProofCells.map((cell) => ({
			cellId: cell.cellId,
			family: cell.family,
			sourceCacheState: cell.sourceCacheState,
			runtime: cell.runtime,
			telemetryState: cell.telemetryState,
			p99BudgetMilliseconds: cell.p99BudgetMilliseconds,
			attemptDeadlineMilliseconds: cell.attemptDeadlineMilliseconds,
			applicability: bridgeLocalFirstProofApplicabilityByCellId.get(cell.cellId),
		})),
	});
}

export function bridgeLocalFirstProofRunIdentityFingerprint(
	runIdentityWithoutFingerprintInput: BridgeLocalFirstProofRunFacts & {
		readonly runManifestHash: string;
	},
): string {
	const runFacts = runFactsFrom(runIdentityWithoutFingerprintInput);
	const runManifestHash = bridgeLocalFirstProofSha256Schema.parse(
		runIdentityWithoutFingerprintInput.runManifestHash,
	);
	return sha256Canonical({ schemaVersion: 1, runFacts, runManifestHash });
}

export function validateBridgeLocalFirstProofRunIdentitySelfConsistency(
	runIdentityInput: BridgeLocalFirstProofRunIdentity,
): void {
	const runIdentity = bridgeLocalFirstProofRunIdentitySchema.parse(runIdentityInput);
	const expectedRunManifestHash = bridgeLocalFirstProofRunManifestHash(runIdentity);
	if (runIdentity.runManifestHash !== expectedRunManifestHash) {
		throw new Error('run identity manifest hash does not match canonical run facts');
	}
	const expectedFingerprint = bridgeLocalFirstProofRunIdentityFingerprint(runIdentity);
	if (runIdentity.runIdentityFingerprint !== expectedFingerprint) {
		throw new Error('run identity fingerprint does not match canonical run facts');
	}
}

export function bridgeLocalFirstProofProcessInstanceId(props: {
	readonly executableSha256: string;
	readonly processId: number;
	readonly processStartToken: string;
}): string {
	const executableSha256 = bridgeLocalFirstProofSha256Schema.parse(props.executableSha256);
	const canonicalProcessIdentity = [
		props.processId,
		props.processStartToken.trim().replace(/\s+/gu, ' '),
		executableSha256,
	].join('\0');
	return `process:${createHash('sha256').update(canonicalProcessIdentity).digest('hex')}`;
}

export type BridgeLocalFirstLiveIdentityObservation =
	| { readonly state: 'unverified'; readonly reason: string }
	| {
			readonly state: 'verified';
			readonly identity: BridgeLocalFirstProofRunIdentity;
	  };

const nonemptyReceiptIdSchema = z.string().trim().min(1);
export const bridgeLocalFirstVerifiedLaunchProvenanceSchema = z
	.object({
		state: z.literal('verified'),
		launchId: nonemptyReceiptIdSchema,
		processInstanceId: nonemptyReceiptIdSchema,
		runningReceipt: z
			.object({
				runningEventId: nonemptyReceiptIdSchema,
				processId: z.number().int().positive(),
				processStartToken: nonemptyReceiptIdSchema,
				executableSha256: bridgeLocalFirstProofSha256Schema,
			})
			.strict()
			.readonly(),
		exitReceipt: z
			.object({
				processInstanceId: nonemptyReceiptIdSchema,
				exitEventId: nonemptyReceiptIdSchema,
			})
			.strict()
			.readonly(),
		cachePreparationReceipt: z
			.object({
				requirement: z.enum([
					'painted_residency',
					'worker_cache_seeded',
					'cold_cache_reset',
					'terminal_residency',
					'resident_rows',
					'resident_window',
					'continuation_reset',
					'resident_prefix',
				]),
				receiptId: nonemptyReceiptIdSchema,
			})
			.strict()
			.readonly(),
		runtimeReadyReceipt: z.object({ eventId: nonemptyReceiptIdSchema }).strict().readonly(),
		telemetryTopologyReceipt: z
			.object({
				telemetryState: z.enum(['off', 'on']),
				topology: z.enum(['absent', 'separate_worker']),
				receiptId: nonemptyReceiptIdSchema,
			})
			.strict()
			.readonly(),
		packagedBundleReceipt: z.discriminatedUnion('runtime', [
			z
				.object({
					runtime: z.literal('controlled_dev_chromium'),
					receiptId: nonemptyReceiptIdSchema,
				})
				.strict()
				.readonly(),
			z
				.object({
					runtime: z.literal('packaged_wkwebview'),
					bundleIdentifier: nonemptyReceiptIdSchema,
					bundleHash: bridgeLocalFirstProofSha256Schema,
					receiptId: nonemptyReceiptIdSchema,
				})
				.strict()
				.readonly(),
		]),
	})
	.strict()
	.readonly();
export type BridgeLocalFirstVerifiedLaunchProvenance = z.output<
	typeof bridgeLocalFirstVerifiedLaunchProvenanceSchema
>;

export const bridgeLocalFirstProofProvenanceJournalSchema = z
	.object({
		schemaVersion: z.literal(1),
		runIdentity: bridgeLocalFirstProofRunIdentitySchema,
		launches: z.array(bridgeLocalFirstVerifiedLaunchProvenanceSchema).readonly(),
	})
	.strict()
	.readonly();
export type BridgeLocalFirstProofProvenanceJournal = z.output<
	typeof bridgeLocalFirstProofProvenanceJournalSchema
>;

export type BridgeLocalFirstLaunchProvenanceObservation =
	| { readonly state: 'unverified'; readonly reason: string }
	| BridgeLocalFirstVerifiedLaunchProvenance;

export interface BridgeLocalFirstProofProvenancePort {
	readonly readCurrentRunIdentity: () => Promise<BridgeLocalFirstLiveIdentityObservation>;
	readonly inspectLaunchProvenance: (
		launchId: string,
	) => Promise<BridgeLocalFirstLaunchProvenanceObservation>;
}

export const bridgeLocalFirstUnverifiedProvenancePort: BridgeLocalFirstProofProvenancePort = {
	readCurrentRunIdentity: async () => ({
		state: 'unverified',
		reason: 'live identity producer is not implemented',
	}),
	inspectLaunchProvenance: async () => ({
		state: 'unverified',
		reason:
			'launch journal, cache reset, readiness, telemetry census, process lifecycle, and bundle binding are not implemented',
	}),
};
