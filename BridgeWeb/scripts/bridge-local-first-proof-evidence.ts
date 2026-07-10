import { createHash } from 'node:crypto';

import { z } from 'zod';

import {
	bridgeLocalFirstProofInternalSlo,
	type BridgeLocalFirstProofCellApplicability,
	type BridgeLocalFirstProofRuntime,
} from './bridge-local-first-proof-manifest.ts';

const nonemptyIdentitySchema = z.string().min(1);
const finiteNonnegativeDurationSchema = z.number().finite().nonnegative();
const timestampPairObjectSchema = z
	.object({
		startedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		completedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
	})
	.strict();

export const bridgeLocalFirstProofFailureKinds = [
	'timeout',
	'stale',
	'wrong',
	'blank',
	'disappeared',
	'missing_endpoint',
] as const;
export type BridgeLocalFirstProofFailureKind = (typeof bridgeLocalFirstProofFailureKinds)[number];

const controlledChromiumTimingSchema = z
	.object({
		runtime: z.literal('controlled_dev_chromium'),
		interactionId: nonemptyIdentitySchema,
		clockDomain: z.literal('browser_performance'),
		eventIsTrusted: z.literal(true),
		actionable: z.literal(true),
		stimulusAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		handlerStartedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		endpointObservedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
	})
	.strict()
	.readonly();

const packagedWebKitTimingSchema = z
	.object({
		runtime: z.literal('packaged_wkwebview'),
		interactionId: nonemptyIdentitySchema,
		clockDomain: z.literal('controller_monotonic'),
		semanticCommandId: nonemptyIdentitySchema,
		correlatedHandlerReceiptId: nonemptyIdentitySchema,
		actionable: z.literal(true),
		stimulusAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		endpointObservedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
	})
	.strict()
	.readonly();

export const bridgeLocalFirstProofRuntimeTimingSchema = z.discriminatedUnion('runtime', [
	controlledChromiumTimingSchema,
	packagedWebKitTimingSchema,
]);

const observedTimestampPairSchema = timestampPairObjectSchema
	.extend({ interactionId: nonemptyIdentitySchema })
	.readonly();
const eventLoopObserverCoverageSchema = z
	.object({
		installReceiptId: nonemptyIdentitySchema,
		drainReceiptId: nonemptyIdentitySchema,
		callbackTimestamps: z
			.array(finiteNonnegativeDurationSchema)
			.min(2, 'event-loop observer coverage requires callback boundaries')
			.readonly(),
		animationFrameTimestamps: z
			.array(finiteNonnegativeDurationSchema)
			.min(2, 'event-loop observer coverage requires rAF boundaries')
			.readonly(),
	})
	.strict()
	.readonly();

const chromiumEventLoopSchema = z
	.object({
		runtime: z.literal('controlled_dev_chromium'),
		interactionId: nonemptyIdentitySchema,
		observerReady: z.literal(true),
		observationStartedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		observationCompletedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		observerCoverage: eventLoopObserverCoverageSchema,
		longTasks: z.array(observedTimestampPairSchema).readonly(),
		rafGaps: z.array(observedTimestampPairSchema).readonly(),
	})
	.strict()
	.readonly();

const webKitEventLoopSchema = z
	.object({
		runtime: z.literal('packaged_wkwebview'),
		interactionId: nonemptyIdentitySchema,
		sentinelReady: z.literal(true),
		nominalCadenceMilliseconds: z.number().finite().positive().max(8),
		observationStartedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		observationCompletedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
		observerCoverage: eventLoopObserverCoverageSchema,
		callbackGaps: z.array(observedTimestampPairSchema).readonly(),
		rafGaps: z.array(observedTimestampPairSchema).readonly(),
	})
	.strict()
	.readonly();

export const bridgeLocalFirstProofEventLoopSchema = z.discriminatedUnion('runtime', [
	chromiumEventLoopSchema,
	webKitEventLoopSchema,
]);

const selectionFeedbackEndpointSchema = z
	.object({
		kind: z.literal('selection_feedback'),
		observedSelectionIdentity: z.string(),
		observedPresentation: z.enum(['readable', 'terminal', 'honest_placeholder', 'blank']),
	})
	.strict()
	.readonly();

const selectedReadableEndpointSchema = z
	.object({
		kind: z.literal('selected_readable'),
		observedSemanticIdentity: z.string(),
		observedWindowIdentity: z.string(),
		observedRenderIdentity: z.string(),
		observedChecksum: z.string(),
		validationLeaseCurrent: z.boolean(),
	})
	.strict()
	.readonly();

const terminalAvailabilityEndpointSchema = z
	.object({
		kind: z.literal('terminal_availability'),
		observedSemanticIdentity: z.string(),
		observedAvailability: z.enum([
			'binary',
			'unsupported_encoding',
			'unavailable',
			'truncated',
			'blank',
		]),
	})
	.strict()
	.readonly();

const railScrollEndpointSchema = z
	.object({
		kind: z.literal('rail_scroll'),
		observedRowsChecksum: z.string(),
		motionPixels: z.number().finite(),
	})
	.strict()
	.readonly();

const contentScrollEndpointSchema = z
	.object({
		kind: z.literal('content_scroll'),
		observedWindowIdentity: z.string(),
		observedChecksum: z.string(),
		motionPixels: z.number().finite(),
	})
	.strict()
	.readonly();

const failedEndpointSchema = z
	.object({
		kind: z.literal('failure'),
		failureKind: z.enum(bridgeLocalFirstProofFailureKinds),
	})
	.strict()
	.readonly();

export const bridgeLocalFirstProofEndpointSchema = z.discriminatedUnion('kind', [
	selectionFeedbackEndpointSchema,
	selectedReadableEndpointSchema,
	terminalAvailabilityEndpointSchema,
	railScrollEndpointSchema,
	contentScrollEndpointSchema,
	failedEndpointSchema,
]);

const expectedSelectionFeedbackEndpointSchema = z
	.object({
		kind: z.literal('selection_feedback'),
		selectionIdentity: nonemptyIdentitySchema,
		presentation: z.enum(['readable', 'terminal', 'honest_placeholder']),
	})
	.strict()
	.readonly();
const expectedSelectedReadableEndpointSchema = z
	.object({
		kind: z.literal('selected_readable'),
		semanticIdentity: nonemptyIdentitySchema,
		windowIdentity: nonemptyIdentitySchema,
		renderIdentity: nonemptyIdentitySchema,
		checksum: nonemptyIdentitySchema,
	})
	.strict()
	.readonly();
const expectedTerminalAvailabilityEndpointSchema = z
	.object({
		kind: z.literal('terminal_availability'),
		semanticIdentity: nonemptyIdentitySchema,
		availability: z.enum(['binary', 'unsupported_encoding', 'unavailable', 'truncated']),
	})
	.strict()
	.readonly();
const expectedRailScrollEndpointSchema = z
	.object({ kind: z.literal('rail_scroll'), rowsChecksum: nonemptyIdentitySchema })
	.strict()
	.readonly();
const expectedContentScrollEndpointSchema = z
	.object({
		kind: z.literal('content_scroll'),
		windowIdentity: nonemptyIdentitySchema,
		checksum: nonemptyIdentitySchema,
	})
	.strict()
	.readonly();
export const bridgeLocalFirstProofExpectedEndpointSchema = z.discriminatedUnion('kind', [
	expectedSelectionFeedbackEndpointSchema,
	expectedSelectedReadableEndpointSchema,
	expectedTerminalAvailabilityEndpointSchema,
	expectedRailScrollEndpointSchema,
	expectedContentScrollEndpointSchema,
]);
export type BridgeLocalFirstProofExpectedEndpoint = z.output<
	typeof bridgeLocalFirstProofExpectedEndpointSchema
>;

export const bridgeLocalFirstProofActionDescriptorSchema = z
	.object({
		manifestRowId: nonemptyIdentitySchema,
		actionIndex: z.union([z.literal('warmup'), z.number().int().nonnegative()]),
	})
	.strict()
	.readonly();
export type BridgeLocalFirstProofActionDescriptor = z.output<
	typeof bridgeLocalFirstProofActionDescriptorSchema
>;
const fixtureOracleEntrySchema = z
	.object({
		oracleEntryId: nonemptyIdentitySchema,
		actionDescriptor: bridgeLocalFirstProofActionDescriptorSchema,
		expectedEndpoint: bridgeLocalFirstProofExpectedEndpointSchema,
	})
	.strict()
	.readonly();
export const bridgeLocalFirstProofFixtureOracleSchema = z
	.object({
		schemaVersion: z.literal(1),
		fixtureId: nonemptyIdentitySchema,
		fixtureChecksum: z.string().regex(/^[a-f0-9]{64}$/u),
		entries: z.array(fixtureOracleEntrySchema).readonly(),
	})
	.strict()
	.readonly();
export type BridgeLocalFirstProofFixtureOracleInput = z.input<
	typeof bridgeLocalFirstProofFixtureOracleSchema
>;
const bridgeLocalFirstValidatedFixtureOracleBrand = Symbol(
	'BridgeLocalFirstValidatedFixtureOracle',
);
export interface BridgeLocalFirstValidatedFixtureOracle {
	readonly fixtureChecksum: string;
	readonly fixtureId: string;
	readonly expectedEndpointFor: (oracleEntryId: string) => BridgeLocalFirstProofExpectedEndpoint;
	readonly [bridgeLocalFirstValidatedFixtureOracleBrand]: true;
}

export function bridgeLocalFirstProofOracleEntryId(props: {
	readonly actionDescriptor: BridgeLocalFirstProofActionDescriptor;
	readonly fixtureChecksum: string;
}): string {
	const actionDescriptor = bridgeLocalFirstProofActionDescriptorSchema.parse(
		props.actionDescriptor,
	);
	const fixtureChecksum = z
		.string()
		.regex(/^[a-f0-9]{64}$/u)
		.parse(props.fixtureChecksum);
	return `oracle:${createHash('sha256')
		.update(JSON.stringify({ fixtureChecksum, actionDescriptor }))
		.digest('hex')}`;
}

export function parseBridgeLocalFirstProofFixtureOracle(props: {
	readonly expectedFixtureChecksum: string;
	readonly expectedFixtureId: string;
	readonly rawOracle: unknown;
}): BridgeLocalFirstValidatedFixtureOracle {
	const oracle = bridgeLocalFirstProofFixtureOracleSchema.parse(props.rawOracle);
	if (
		oracle.fixtureId !== props.expectedFixtureId ||
		oracle.fixtureChecksum !== props.expectedFixtureChecksum
	) {
		throw new Error('fixture oracle identity does not match immutable run identity');
	}
	const entries = new Map<string, BridgeLocalFirstProofExpectedEndpoint>();
	for (const entry of oracle.entries) {
		const expectedEntryId = bridgeLocalFirstProofOracleEntryId({
			actionDescriptor: entry.actionDescriptor,
			fixtureChecksum: oracle.fixtureChecksum,
		});
		if (entry.oracleEntryId !== expectedEntryId || entries.has(entry.oracleEntryId)) {
			throw new Error(`fixture oracle has invalid or duplicate entry ${entry.oracleEntryId}`);
		}
		entries.set(entry.oracleEntryId, entry.expectedEndpoint);
	}
	return Object.freeze({
		fixtureChecksum: oracle.fixtureChecksum,
		fixtureId: oracle.fixtureId,
		expectedEndpointFor: (oracleEntryId: string) => {
			const endpoint = entries.get(oracleEntryId);
			if (endpoint === undefined) {
				throw new Error(`fixture oracle is missing ${oracleEntryId}`);
			}
			return endpoint;
		},
		[bridgeLocalFirstValidatedFixtureOracleBrand]: true as const,
	});
}

export const bridgeLocalFirstProofExternalEvidenceSchema = z
	.object({
		interactionId: nonemptyIdentitySchema,
		runtimeTiming: bridgeLocalFirstProofRuntimeTimingSchema,
		endpoint: bridgeLocalFirstProofEndpointSchema,
		eventLoop: bridgeLocalFirstProofEventLoopSchema,
	})
	.strict()
	.readonly();

export const bridgeLocalFirstProofInternalStages = [
	'stimulus_issued',
	'main_intent_received',
	'local_intent_committed',
	'local_feedback_painted',
	'worker_intent_received',
	'demand_issued',
	'content_source_resolved',
	'swift_request_issued',
	'swift_response_received',
	'worker_ready',
	'selection_accepted',
	'main_job_received',
	'main_validity_decided',
	'apply_queued',
	'pierre_queued',
	'dom_applied',
	'readable_painted',
	'terminal_availability_painted',
	'render_disposition_received',
	'attempt_closed',
] as const;
export type BridgeLocalFirstProofInternalStage =
	(typeof bridgeLocalFirstProofInternalStages)[number];

const internalEventSchema = z
	.object({
		interactionId: nonemptyIdentitySchema,
		producer: z.enum(['main', 'comm']),
		producerSequence: z.number().int().positive(),
		interactionSequence: z.number().int().positive(),
		stage: z.enum(bridgeLocalFirstProofInternalStages),
		observedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
	})
	.strict()
	.readonly();

const internalSpanSchema = timestampPairObjectSchema
	.extend({
		interactionId: nonemptyIdentitySchema,
		kind: z.enum(['selected_comm_queue', 'main_to_pierre']),
	})
	.readonly();

const synchronousSliceSchema = timestampPairObjectSchema
	.extend({
		interactionId: nonemptyIdentitySchema,
		owner: z.enum(['main', 'comm']),
	})
	.readonly();

const telemetryOffInternalEvidenceSchema = z
	.object({ mode: z.literal('off') })
	.strict()
	.readonly();
const telemetryOnInternalEvidenceSchema = z
	.object({
		mode: z.literal('on'),
		events: z.array(internalEventSchema).readonly(),
		spans: z.array(internalSpanSchema).readonly(),
		synchronousSlices: z.array(synchronousSliceSchema).readonly(),
	})
	.strict()
	.readonly();

export const bridgeLocalFirstProofInternalEvidenceSchema = z.discriminatedUnion('mode', [
	telemetryOffInternalEvidenceSchema,
	telemetryOnInternalEvidenceSchema,
]);

export const bridgeLocalFirstProofInteractionEvidenceSchema = z
	.object({
		interactionId: nonemptyIdentitySchema,
		external: bridgeLocalFirstProofExternalEvidenceSchema,
		internal: bridgeLocalFirstProofInternalEvidenceSchema,
	})
	.strict()
	.readonly();

const lossRangeSchema = z
	.object({
		producer: z.enum(['main', 'comm']),
		firstMissingSequence: z.number().int().positive(),
		lastMissingSequence: z.number().int().positive(),
		required: z.boolean(),
	})
	.strict()
	.readonly();
const drainReceiptSchema = z
	.object({
		producer: z.enum(['main', 'comm']),
		acknowledgedProducerSequence: z.number().int().nonnegative(),
		drainedAtMonotonicMilliseconds: finiteNonnegativeDurationSchema,
	})
	.strict()
	.readonly();

export const bridgeLocalFirstProofTelemetryProofSchema = z.discriminatedUnion('mode', [
	z
		.object({ mode: z.literal('off') })
		.strict()
		.readonly(),
	z
		.object({
			mode: z.literal('on'),
			lossRanges: z.array(lossRangeSchema).readonly(),
			drainReceipts: z.array(drainReceiptSchema).readonly(),
		})
		.strict()
		.readonly(),
]);

export type BridgeLocalFirstProofExternalEvidence = z.output<
	typeof bridgeLocalFirstProofExternalEvidenceSchema
>;
export type BridgeLocalFirstProofInteractionEvidence = z.output<
	typeof bridgeLocalFirstProofInteractionEvidenceSchema
>;

interface AttemptOutcomeEvidence {
	readonly outcome: 'failed' | 'succeeded';
	readonly failureKind?: BridgeLocalFirstProofFailureKind;
	readonly durationMilliseconds?: number;
	readonly deadlineDurationMilliseconds: number;
}

export function bridgeLocalFirstProofExternalDurationMilliseconds(
	externalEvidence: BridgeLocalFirstProofExternalEvidence,
): number {
	return (
		externalEvidence.runtimeTiming.endpointObservedAtMonotonicMilliseconds -
		externalEvidence.runtimeTiming.stimulusAtMonotonicMilliseconds
	);
}

export function bridgeLocalFirstProofRequiredInternalStagesForApplicability(
	applicability: BridgeLocalFirstProofCellApplicability,
): readonly BridgeLocalFirstProofInternalStage[] {
	const localFeedbackStages = [
		'stimulus_issued',
		'main_intent_received',
		'local_intent_committed',
		'local_feedback_painted',
	] as const;
	if (
		applicability.endpointKind === 'selection_feedback' ||
		applicability.lifecycleVariant === 'fresh-display' ||
		applicability.lifecycleVariant === 'cached-terminal'
	) {
		return [
			...localFeedbackStages,
			'worker_intent_received',
			'selection_accepted',
			'attempt_closed',
		];
	}
	if (
		applicability.lifecycleVariant === 'resident-rows' ||
		applicability.lifecycleVariant === 'resident-window' ||
		applicability.lifecycleVariant === 'resident-prefix'
	) {
		return [...localFeedbackStages, 'attempt_closed'];
	}
	const sourceStages = [
		...localFeedbackStages,
		'worker_intent_received',
		'demand_issued',
		'content_source_resolved',
	] as const;
	const swiftStages =
		applicability.lifecycleVariant === 'cold-miss' ||
		applicability.lifecycleVariant === 'cold-terminal' ||
		applicability.lifecycleVariant === 'continuation-miss'
			? (['swift_request_issued', 'swift_response_received'] as const)
			: [];
	const mainApplyStages = [
		'worker_ready',
		'main_job_received',
		'main_validity_decided',
		'apply_queued',
	] as const;
	const pierreStages =
		applicability.pierreSubmission === 'required' ? (['pierre_queued'] as const) : [];
	const paintedStage =
		applicability.endpointKind === 'terminal_availability'
			? ('terminal_availability_painted' as const)
			: ('readable_painted' as const);
	return [
		...sourceStages,
		...swiftStages,
		...mainApplyStages,
		...pierreStages,
		'dom_applied',
		paintedStage,
		'render_disposition_received',
		'attempt_closed',
	];
}

export function bridgeLocalFirstProofProducerForStage(
	stage: BridgeLocalFirstProofInternalStage,
): 'comm' | 'main' {
	return [
		'worker_intent_received',
		'demand_issued',
		'content_source_resolved',
		'swift_request_issued',
		'swift_response_received',
		'worker_ready',
		'selection_accepted',
	].includes(stage)
		? 'comm'
		: 'main';
}

// oxlint-disable-next-line typescript/consistent-return -- The endpoint union is exhausted below.
function endpointFailureKind(
	externalEvidence: BridgeLocalFirstProofExternalEvidence,
	applicability: BridgeLocalFirstProofCellApplicability,
	expectedEndpoint: BridgeLocalFirstProofExpectedEndpoint,
): BridgeLocalFirstProofFailureKind | undefined {
	const endpoint = externalEvidence.endpoint;
	if (expectedEndpoint.kind !== applicability.endpointKind) {
		throw new Error(`${externalEvidence.interactionId}: fixture oracle endpoint kind mismatch`);
	}
	if (endpoint.kind === 'failure') return endpoint.failureKind;
	if (endpoint.kind !== expectedEndpoint.kind) {
		throw new Error(`${externalEvidence.interactionId}: observed endpoint kind mismatch`);
	}
	switch (expectedEndpoint.kind) {
		case 'selection_feedback':
			if (endpoint.kind !== 'selection_feedback') return 'wrong';
			if (endpoint.observedSelectionIdentity.length === 0) return 'blank';
			if (expectedEndpoint.selectionIdentity !== endpoint.observedSelectionIdentity) return 'stale';
			return expectedEndpoint.presentation === endpoint.observedPresentation ? undefined : 'wrong';
		case 'selected_readable':
			if (endpoint.kind !== 'selected_readable') return 'wrong';
			if (endpoint.observedChecksum.length === 0) return 'blank';
			if (
				expectedEndpoint.semanticIdentity !== endpoint.observedSemanticIdentity ||
				expectedEndpoint.windowIdentity !== endpoint.observedWindowIdentity ||
				expectedEndpoint.renderIdentity !== endpoint.observedRenderIdentity ||
				!endpoint.validationLeaseCurrent
			) {
				return 'stale';
			}
			return expectedEndpoint.checksum === endpoint.observedChecksum ? undefined : 'wrong';
		case 'terminal_availability':
			if (endpoint.kind !== 'terminal_availability') return 'wrong';
			if (endpoint.observedAvailability === 'blank') return 'blank';
			if (expectedEndpoint.semanticIdentity !== endpoint.observedSemanticIdentity) return 'stale';
			return expectedEndpoint.availability === endpoint.observedAvailability ? undefined : 'wrong';
		case 'rail_scroll':
			if (endpoint.kind !== 'rail_scroll') return 'wrong';
			if (endpoint.observedRowsChecksum.length === 0) return 'blank';
			if (endpoint.motionPixels === 0) return 'missing_endpoint';
			return expectedEndpoint.rowsChecksum === endpoint.observedRowsChecksum ? undefined : 'wrong';
		case 'content_scroll':
			if (endpoint.kind !== 'content_scroll') return 'wrong';
			if (endpoint.observedChecksum.length === 0) return 'blank';
			if (endpoint.motionPixels === 0) return 'missing_endpoint';
			if (expectedEndpoint.windowIdentity !== endpoint.observedWindowIdentity) return 'stale';
			return expectedEndpoint.checksum === endpoint.observedChecksum ? undefined : 'wrong';
	}
}

export function validateBridgeLocalFirstProofExternalEvidence(props: {
	readonly applicability: BridgeLocalFirstProofCellApplicability;
	readonly attempt: AttemptOutcomeEvidence;
	readonly evidence: BridgeLocalFirstProofExternalEvidence;
	readonly expectedEndpoint: BridgeLocalFirstProofExpectedEndpoint;
	readonly interactionId: string;
	readonly runtime: BridgeLocalFirstProofRuntime;
}): void {
	const { attempt, evidence } = props;
	if (
		evidence.interactionId !== props.interactionId ||
		evidence.runtimeTiming.interactionId !== props.interactionId ||
		evidence.eventLoop.interactionId !== props.interactionId
	) {
		throw new Error(`${props.interactionId}: external evidence identity mismatch`);
	}
	if (
		evidence.runtimeTiming.runtime !== props.runtime ||
		evidence.eventLoop.runtime !== props.runtime
	) {
		throw new Error(`${props.interactionId}: runtime evidence mismatch`);
	}
	const durationMilliseconds = bridgeLocalFirstProofExternalDurationMilliseconds(evidence);
	if (durationMilliseconds < 0) {
		throw new Error(`${props.interactionId}: external endpoint precedes trusted stimulus`);
	}
	if (
		evidence.runtimeTiming.runtime === 'controlled_dev_chromium' &&
		(evidence.runtimeTiming.handlerStartedAtMonotonicMilliseconds <
			evidence.runtimeTiming.stimulusAtMonotonicMilliseconds ||
			evidence.runtimeTiming.handlerStartedAtMonotonicMilliseconds >
				evidence.runtimeTiming.endpointObservedAtMonotonicMilliseconds)
	) {
		throw new Error(`${props.interactionId}: trusted handler timing is outside interaction`);
	}
	validateEventLoopEvidence(evidence);
	const derivedFailureKind = endpointFailureKind(
		evidence,
		props.applicability,
		props.expectedEndpoint,
	);
	if (derivedFailureKind === undefined) {
		if (attempt.outcome !== 'succeeded') {
			throw new Error(`${props.interactionId}: declared failure contradicts endpoint oracle`);
		}
		if (
			attempt.durationMilliseconds === undefined ||
			Math.abs(attempt.durationMilliseconds - durationMilliseconds) > 0.000_001
		) {
			throw new Error(`${props.interactionId}: duration does not match trusted endpoint evidence`);
		}
		if (durationMilliseconds > attempt.deadlineDurationMilliseconds) {
			throw new Error(`${props.interactionId}: success completed after its deadline`);
		}
		return;
	}
	if (attempt.outcome !== 'failed' || attempt.failureKind !== derivedFailureKind) {
		throw new Error(
			`${props.interactionId}: endpoint oracle derived ${derivedFailureKind}, not declared outcome`,
		);
	}
}

function validateEventLoopEvidence(evidence: BridgeLocalFirstProofExternalEvidence): void {
	const eventLoop = evidence.eventLoop;
	if (
		eventLoop.observationStartedAtMonotonicMilliseconds >
			evidence.runtimeTiming.stimulusAtMonotonicMilliseconds ||
		eventLoop.observationCompletedAtMonotonicMilliseconds <
			evidence.runtimeTiming.endpointObservedAtMonotonicMilliseconds ||
		eventLoop.observationCompletedAtMonotonicMilliseconds <
			eventLoop.observationStartedAtMonotonicMilliseconds
	) {
		throw new Error(`${evidence.interactionId}: event-loop window does not cover interaction`);
	}
	validateCoverageTimestamps({
		interactionId: evidence.interactionId,
		label: 'callback',
		observationCompletedAt: eventLoop.observationCompletedAtMonotonicMilliseconds,
		observationStartedAt: eventLoop.observationStartedAtMonotonicMilliseconds,
		interactionCompletedAt: evidence.runtimeTiming.endpointObservedAtMonotonicMilliseconds,
		interactionStartedAt: evidence.runtimeTiming.stimulusAtMonotonicMilliseconds,
		requiresPostInteractionBoundary: false,
		timestamps: eventLoop.observerCoverage.callbackTimestamps,
	});
	validateCoverageTimestamps({
		interactionId: evidence.interactionId,
		label: 'rAF',
		observationCompletedAt: eventLoop.observationCompletedAtMonotonicMilliseconds,
		observationStartedAt: eventLoop.observationStartedAtMonotonicMilliseconds,
		interactionCompletedAt: evidence.runtimeTiming.endpointObservedAtMonotonicMilliseconds,
		interactionStartedAt: evidence.runtimeTiming.stimulusAtMonotonicMilliseconds,
		requiresPostInteractionBoundary: true,
		timestamps: eventLoop.observerCoverage.animationFrameTimestamps,
	});
	const gapCollections =
		eventLoop.runtime === 'controlled_dev_chromium'
			? [eventLoop.longTasks, eventLoop.rafGaps]
			: [eventLoop.callbackGaps, eventLoop.rafGaps];
	for (const observations of gapCollections) {
		for (const observation of observations) {
			if (observation.interactionId !== evidence.interactionId) {
				throw new Error(`${evidence.interactionId}: event-loop observation identity mismatch`);
			}
			const duration =
				observation.completedAtMonotonicMilliseconds - observation.startedAtMonotonicMilliseconds;
			if (
				duration < 0 ||
				observation.startedAtMonotonicMilliseconds <
					eventLoop.observationStartedAtMonotonicMilliseconds ||
				observation.completedAtMonotonicMilliseconds >
					eventLoop.observationCompletedAtMonotonicMilliseconds
			) {
				throw new Error(`${evidence.interactionId}: event-loop timestamps are reversed`);
			}
			if (duration >= bridgeLocalFirstProofInternalSlo.mainThreadLongTaskMilliseconds) {
				throw new Error(`${evidence.interactionId}: event-loop gap reached 50 ms`);
			}
		}
	}
}

function validateCoverageTimestamps(props: {
	readonly interactionId: string;
	readonly interactionCompletedAt: number;
	readonly interactionStartedAt: number;
	readonly label: string;
	readonly observationCompletedAt: number;
	readonly observationStartedAt: number;
	readonly requiresPostInteractionBoundary: boolean;
	readonly timestamps: readonly number[];
}): void {
	const firstTimestamp = props.timestamps[0];
	const lastTimestamp = props.timestamps.at(-1);
	if (
		firstTimestamp === undefined ||
		lastTimestamp === undefined ||
		firstTimestamp < props.observationStartedAt ||
		firstTimestamp > props.interactionStartedAt ||
		(props.requiresPostInteractionBoundary
			? lastTimestamp <= props.interactionCompletedAt
			: lastTimestamp < props.interactionCompletedAt) ||
		lastTimestamp > props.observationCompletedAt
	) {
		throw new Error(
			`${props.interactionId}: event-loop observer coverage does not bound interaction`,
		);
	}
	for (const [timestampIndex, timestamp] of props.timestamps.entries()) {
		const previousTimestamp = props.timestamps[timestampIndex - 1];
		if (previousTimestamp !== undefined) {
			const gap = timestamp - previousTimestamp;
			if (gap <= 0) {
				throw new Error(`${props.interactionId}: ${props.label} coverage is not monotonic`);
			}
			if (gap >= bridgeLocalFirstProofInternalSlo.mainThreadLongTaskMilliseconds) {
				throw new Error(`${props.interactionId}: event-loop gap reached 50 ms`);
			}
		}
	}
}

export function validateBridgeLocalFirstProofInternalEvidence(props: {
	readonly applicability: BridgeLocalFirstProofCellApplicability;
	readonly evidence: BridgeLocalFirstProofInteractionEvidence['internal'];
	readonly interactionCompletedAtMonotonicMilliseconds: number;
	readonly interactionId: string;
	readonly interactionStartedAtMonotonicMilliseconds: number;
	readonly telemetryState: 'off' | 'on';
}): void {
	if (props.telemetryState === 'off') {
		if (props.evidence.mode !== 'off') {
			throw new Error(`${props.interactionId}: telemetry-off forbids internal evidence`);
		}
		return;
	}
	if (props.evidence.mode !== 'on') {
		throw new Error(`${props.interactionId}: telemetry-on requires internal evidence`);
	}
	const expectedStages = bridgeLocalFirstProofRequiredInternalStagesForApplicability(
		props.applicability,
	);
	if (props.evidence.events.length !== expectedStages.length) {
		throw new Error(`${props.interactionId}: internal lifecycle stage count mismatch`);
	}
	let previousStageTimestamp = Number.NEGATIVE_INFINITY;
	for (const [stageIndex, expectedStage] of expectedStages.entries()) {
		const event = props.evidence.events[stageIndex];
		if (
			event === undefined ||
			event.interactionId !== props.interactionId ||
			event.interactionSequence !== stageIndex + 1 ||
			event.stage !== expectedStage ||
			event.producer !== bridgeLocalFirstProofProducerForStage(expectedStage)
		) {
			throw new Error(`${props.interactionId}: internal lifecycle mismatch at ${expectedStage}`);
		}
		if (
			event.observedAtMonotonicMilliseconds < previousStageTimestamp ||
			event.observedAtMonotonicMilliseconds < props.interactionStartedAtMonotonicMilliseconds ||
			event.observedAtMonotonicMilliseconds > props.interactionCompletedAtMonotonicMilliseconds
		) {
			throw new Error(`${props.interactionId}: internal lifecycle timestamps are not monotonic`);
		}
		previousStageTimestamp = event.observedAtMonotonicMilliseconds;
	}
	validateInternalSpans({
		applicability: props.applicability,
		evidence: props.evidence,
		interactionCompletedAtMonotonicMilliseconds: props.interactionCompletedAtMonotonicMilliseconds,
		interactionId: props.interactionId,
		interactionStartedAtMonotonicMilliseconds: props.interactionStartedAtMonotonicMilliseconds,
	});
	const requiredOwners = new Set(
		expectedStages.map((stage) => bridgeLocalFirstProofProducerForStage(stage)),
	);
	const observedOwners = new Set<'comm' | 'main'>();
	for (const synchronousSlice of props.evidence.synchronousSlices) {
		if (synchronousSlice.interactionId !== props.interactionId) {
			throw new Error(`${props.interactionId}: synchronous slice identity mismatch`);
		}
		observedOwners.add(synchronousSlice.owner);
		const duration =
			synchronousSlice.completedAtMonotonicMilliseconds -
			synchronousSlice.startedAtMonotonicMilliseconds;
		if (
			duration < 0 ||
			duration > bridgeLocalFirstProofInternalSlo.maximumOwnedSynchronousSliceMilliseconds ||
			synchronousSlice.startedAtMonotonicMilliseconds <
				props.interactionStartedAtMonotonicMilliseconds ||
			synchronousSlice.completedAtMonotonicMilliseconds >
				props.interactionCompletedAtMonotonicMilliseconds
		) {
			throw new Error(`${props.interactionId}: owned synchronous slice exceeded 8 ms`);
		}
	}
	for (const requiredOwner of requiredOwners) {
		if (!observedOwners.has(requiredOwner)) {
			throw new Error(`${props.interactionId}: missing ${requiredOwner} synchronous evidence`);
		}
	}
}

function validateInternalSpans(props: {
	readonly applicability: BridgeLocalFirstProofCellApplicability;
	readonly evidence: Extract<BridgeLocalFirstProofInteractionEvidence['internal'], { mode: 'on' }>;
	readonly interactionCompletedAtMonotonicMilliseconds: number;
	readonly interactionId: string;
	readonly interactionStartedAtMonotonicMilliseconds: number;
}): void {
	for (const spanKind of ['selected_comm_queue', 'main_to_pierre'] as const) {
		const matchingSpans = props.evidence.spans.filter((span) => span.kind === spanKind);
		const required =
			spanKind === 'selected_comm_queue'
				? props.applicability.selectedCommQueue === 'required'
				: props.applicability.pierreSubmission === 'required';
		if (matchingSpans.length !== (required ? 1 : 0)) {
			throw new Error(
				`${props.interactionId}: ${spanKind} span is ${required ? 'required' : 'forbidden'}`,
			);
		}
		for (const span of matchingSpans) {
			if (span.interactionId !== props.interactionId) {
				throw new Error(`${props.interactionId}: internal span identity mismatch`);
			}
			if (span.completedAtMonotonicMilliseconds < span.startedAtMonotonicMilliseconds) {
				throw new Error(`${props.interactionId}: internal span timestamps are reversed`);
			}
			if (
				span.startedAtMonotonicMilliseconds < props.interactionStartedAtMonotonicMilliseconds ||
				span.completedAtMonotonicMilliseconds > props.interactionCompletedAtMonotonicMilliseconds
			) {
				throw new Error(`${props.interactionId}: internal span is outside interaction`);
			}
		}
	}
}
