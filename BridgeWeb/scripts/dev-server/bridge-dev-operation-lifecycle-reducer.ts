import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';

export const bridgeOperationLifecyclePhaseFamilies = [
	'file_prepare',
	'review_prepare',
	'refresh_commit',
	'metadata_enqueue',
	'metadata_delivery',
	'worker_application',
	'panel_chrome_publish',
	'file_content_operation',
	'file_descriptor_wait',
	'content_operation',
	'content_transfer',
	'projection_convergence',
	'projection_query',
	'projection_validation',
	'projection_store',
	'main_thread_install',
	'render_operation',
	'paint_fulfillment',
	'native_annotation_work',
	'descriptor_claim',
	'annotation_paint',
] as const;

type BridgeOperationPhaseFamily = (typeof bridgeOperationLifecyclePhaseFamilies)[number];
const unpairedLifecycleFacts = new Set(['refresh_reserved', 'refresh_operation_terminal']);

type BridgeOperationLifecycleSample = BridgeTelemetrySample & {
	readonly observedAtUnixMilliseconds: number;
};

export type BridgeOperationLifecycleMalformedEntry = {
	readonly kind:
		| 'duplicate_start'
		| 'duplicate_terminal'
		| 'capacity_exceeded'
		| 'invalid_stage_attempt'
		| 'invalid_operation_correlation'
		| 'late_terminal'
		| 'noncontiguous_stage_attempt'
		| 'terminal_without_start'
		| 'unknown_phase';
	readonly operationCorrelationId: string;
	readonly phaseFamily: string;
	readonly stageAttempt: number;
};

export type BridgeOperationLifecycleMissingTerminal = {
	readonly operationCorrelationId: string;
	readonly phaseFamily: BridgeOperationPhaseFamily;
	readonly stageAttempt: number;
};

export type BridgeOperationLifecycleReduction = {
	readonly completedOperationIds: readonly string[];
	readonly malformed: readonly BridgeOperationLifecycleMalformedEntry[];
	readonly missingTerminals: readonly BridgeOperationLifecycleMissingTerminal[];
};

export function reduceBridgeOperationLifecycle(props: {
	readonly maximumTrackedStageAttempts?: number | undefined;
	readonly nowUnixMilliseconds: number;
	readonly samples: readonly BridgeOperationLifecycleSample[];
	readonly terminalWindowMilliseconds: number;
}): BridgeOperationLifecycleReduction {
	const maximumTrackedStageAttempts = props.maximumTrackedStageAttempts ?? 4096;
	const trackedAttempts = new Map<string, TrackedAttempt>();
	const highestAttemptByOperationAndFamily = new Map<string, number>();
	const malformed: BridgeOperationLifecycleMalformedEntry[] = [];

	const orderedSamples = props.samples
		.map((sample, inputOrdinal) => ({ inputOrdinal, sample }))
		.sort(
			(left, right) =>
				left.sample.observedAtUnixMilliseconds - right.sample.observedAtUnixMilliseconds ||
				left.inputOrdinal - right.inputOrdinal,
		);
	for (const { sample } of orderedSamples) {
		const operationCorrelationId = sample.stringAttributes['agentstudio.bridge.operation.id'] ?? '';
		const phase = sample.stringAttributes['agentstudio.bridge.phase'] ?? '';
		const stageAttempt = sample.numericAttributes['agentstudio.bridge.stage.attempt'];
		if (unpairedLifecycleFacts.has(phase)) continue;
		const parsedPhase = parseLifecyclePhase(phase);
		if (!/^[0-9a-f]{64}$/.test(operationCorrelationId)) {
			malformed.push({
				kind: 'invalid_operation_correlation',
				operationCorrelationId,
				phaseFamily: parsedPhase?.family ?? phase,
				stageAttempt: Number.isSafeInteger(stageAttempt) ? (stageAttempt ?? -1) : -1,
			});
			continue;
		}
		if (parsedPhase === null) {
			malformed.push({
				kind: 'unknown_phase',
				operationCorrelationId,
				phaseFamily: phase,
				stageAttempt: Number.isSafeInteger(stageAttempt) ? (stageAttempt ?? -1) : -1,
			});
			continue;
		}
		if (stageAttempt === undefined || !Number.isSafeInteger(stageAttempt) || stageAttempt < 0) {
			malformed.push({
				kind: 'invalid_stage_attempt',
				operationCorrelationId,
				phaseFamily: parsedPhase.family,
				stageAttempt: stageAttempt ?? -1,
			});
			continue;
		}
		const key = `${operationCorrelationId}\0${parsedPhase.family}\0${stageAttempt}`;
		const familyKey = `${operationCorrelationId}\0${parsedPhase.family}`;
		const tracked = trackedAttempts.get(key);
		if (parsedPhase.kind === 'started') {
			if (tracked !== undefined) {
				malformed.push({
					kind: 'duplicate_start',
					operationCorrelationId,
					phaseFamily: parsedPhase.family,
					stageAttempt,
				});
				continue;
			}
			const highestAttempt = highestAttemptByOperationAndFamily.get(familyKey);
			if (
				(highestAttempt === undefined && stageAttempt !== 0) ||
				(highestAttempt !== undefined && stageAttempt !== highestAttempt + 1)
			) {
				malformed.push({
					kind: 'noncontiguous_stage_attempt',
					operationCorrelationId,
					phaseFamily: parsedPhase.family,
					stageAttempt,
				});
				continue;
			}
			highestAttemptByOperationAndFamily.set(familyKey, stageAttempt);
			if (trackedAttempts.size >= maximumTrackedStageAttempts) {
				malformed.push({
					kind: 'capacity_exceeded',
					operationCorrelationId,
					phaseFamily: parsedPhase.family,
					stageAttempt,
				});
				continue;
			}
			trackedAttempts.set(key, {
				family: parsedPhase.family,
				operationCorrelationId,
				stageAttempt,
				startedAtUnixMilliseconds: sample.observedAtUnixMilliseconds,
				terminalAtUnixMilliseconds: null,
			});
			continue;
		}
		if (tracked === undefined) {
			malformed.push({
				kind: 'terminal_without_start',
				operationCorrelationId,
				phaseFamily: parsedPhase.family,
				stageAttempt,
			});
			continue;
		}
		if (tracked.terminalAtUnixMilliseconds !== null) {
			malformed.push({
				kind: 'duplicate_terminal',
				operationCorrelationId,
				phaseFamily: parsedPhase.family,
				stageAttempt,
			});
			continue;
		}
		if (
			sample.observedAtUnixMilliseconds - tracked.startedAtUnixMilliseconds >
			props.terminalWindowMilliseconds
		) {
			malformed.push({
				kind: 'late_terminal',
				operationCorrelationId,
				phaseFamily: parsedPhase.family,
				stageAttempt,
			});
			continue;
		}
		tracked.terminalAtUnixMilliseconds = sample.observedAtUnixMilliseconds;
	}

	const missingByOperation = new Map<string, BridgeOperationLifecycleMissingTerminal>();
	for (const attempt of trackedAttempts.values()) {
		if (
			attempt.terminalAtUnixMilliseconds !== null ||
			props.nowUnixMilliseconds - attempt.startedAtUnixMilliseconds <=
				props.terminalWindowMilliseconds
		) {
			continue;
		}
		const existing = missingByOperation.get(attempt.operationCorrelationId);
		if (
			existing === undefined ||
			phaseFamilyOrdinal(attempt.family) < phaseFamilyOrdinal(existing.phaseFamily)
		) {
			missingByOperation.set(attempt.operationCorrelationId, {
				operationCorrelationId: attempt.operationCorrelationId,
				phaseFamily: attempt.family,
				stageAttempt: attempt.stageAttempt,
			});
		}
	}

	const operationIds = new Set(
		[...trackedAttempts.values()].map((attempt) => attempt.operationCorrelationId),
	);
	const malformedOperationIds = new Set(malformed.map((entry) => entry.operationCorrelationId));
	const completedOperationIds = [...operationIds]
		.filter(
			(operationId) =>
				!malformedOperationIds.has(operationId) &&
				!missingByOperation.has(operationId) &&
				[...trackedAttempts.values()]
					.filter((attempt) => attempt.operationCorrelationId === operationId)
					.every((attempt) => attempt.terminalAtUnixMilliseconds !== null),
		)
		.sort();

	return {
		completedOperationIds,
		malformed,
		missingTerminals: [...missingByOperation.values()].sort(
			(left, right) => phaseFamilyOrdinal(left.phaseFamily) - phaseFamilyOrdinal(right.phaseFamily),
		),
	};
}

type TrackedAttempt = {
	readonly family: BridgeOperationPhaseFamily;
	readonly operationCorrelationId: string;
	readonly stageAttempt: number;
	readonly startedAtUnixMilliseconds: number;
	terminalAtUnixMilliseconds: number | null;
};

function parseLifecyclePhase(
	phase: string,
): { readonly family: BridgeOperationPhaseFamily; readonly kind: 'started' | 'terminal' } | null {
	for (const family of bridgeOperationLifecyclePhaseFamilies) {
		if (phase === `${family}_started`) return { family, kind: 'started' };
		if (phase === `${family}_terminal`) return { family, kind: 'terminal' };
	}
	return null;
}

function phaseFamilyOrdinal(family: BridgeOperationPhaseFamily): number {
	return bridgeOperationLifecyclePhaseFamilies.indexOf(family);
}
