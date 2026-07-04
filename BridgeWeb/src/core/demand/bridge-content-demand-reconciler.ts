import type {
	BridgeContentDemandRole,
	BridgeDemandIntent,
} from '../models/bridge-demand-models.js';
import { demandRankForContentRole } from './bridge-content-demand-policy.js';

export interface BridgeContentDemandCandidate {
	readonly intent: BridgeDemandIntent;
	readonly role: BridgeContentDemandRole;
}

export interface BridgeContentDemandPlanEntry {
	readonly generation: number;
	readonly intent: BridgeDemandIntent;
	readonly rank: number;
	readonly role: BridgeContentDemandRole;
	readonly startEligible: boolean;
}

export type BridgeContentDemandPlanOperation =
	| {
			readonly dedupeKey: string;
			readonly kind: 'enqueue';
			readonly role: BridgeContentDemandRole;
	  }
	| {
			readonly dedupeKey: string;
			readonly fromRole: BridgeContentDemandRole;
			readonly kind: 'promote';
			readonly toRole: BridgeContentDemandRole;
	  }
	| {
			readonly dedupeKey: string;
			readonly fromRole: BridgeContentDemandRole;
			readonly kind: 'demote';
			readonly toRole: BridgeContentDemandRole;
	  }
	| {
			readonly cancellationGroup: string;
			readonly dedupeKey: string;
			readonly kind: 'cancel';
			readonly reason: 'generation-reset' | 'superseded';
	  }
	| {
			readonly dedupeKey: string;
			readonly kind: 'cacheHit';
			readonly role: BridgeContentDemandRole;
	  };

export interface BridgeContentDemandPlan {
	readonly entries: readonly BridgeContentDemandPlanEntry[];
	readonly generation: number;
	readonly operations: readonly BridgeContentDemandPlanOperation[];
}

export interface ReconcileBridgeContentDemandProps {
	readonly candidates: readonly BridgeContentDemandCandidate[];
	readonly generation: number;
	readonly inFlightDedupeKeys: ReadonlySet<string>;
	readonly loadedDedupeKeys: ReadonlySet<string>;
	readonly paused: boolean;
	readonly previousEntries: readonly BridgeContentDemandPlanEntry[];
}

export function reconcileBridgeContentDemand(
	props: ReconcileBridgeContentDemandProps,
): BridgeContentDemandPlan {
	const candidateByDedupeKey = dedupeCandidatesToHighestRole(props.candidates);
	const previousEntryByDedupeKey = new Map(
		props.previousEntries.map((entry): readonly [string, BridgeContentDemandPlanEntry] => [
			entry.intent.dedupeKey,
			entry,
		]),
	);
	const operations: BridgeContentDemandPlanOperation[] = [];
	const entries: BridgeContentDemandPlanEntry[] = [];

	for (const previousEntry of props.previousEntries) {
		if (previousEntry.generation !== props.generation) {
			operations.push({
				cancellationGroup: previousEntry.intent.cancellationGroup,
				dedupeKey: previousEntry.intent.dedupeKey,
				kind: 'cancel',
				reason: 'generation-reset',
			});
			continue;
		}
		if (!candidateByDedupeKey.has(previousEntry.intent.dedupeKey)) {
			operations.push({
				cancellationGroup: previousEntry.intent.cancellationGroup,
				dedupeKey: previousEntry.intent.dedupeKey,
				kind: 'cancel',
				reason: 'superseded',
			});
		}
	}

	for (const candidate of candidateByDedupeKey.values()) {
		const rank = demandRankForContentRole(candidate.role);
		if (props.loadedDedupeKeys.has(candidate.intent.dedupeKey)) {
			operations.push({
				dedupeKey: candidate.intent.dedupeKey,
				kind: 'cacheHit',
				role: candidate.role,
			});
			continue;
		}
		const previousEntry = previousEntryByDedupeKey.get(candidate.intent.dedupeKey);
		if (previousEntry !== undefined && previousEntry.generation === props.generation) {
			const previousRank = demandRankForContentRole(previousEntry.role);
			if (rank < previousRank) {
				operations.push({
					dedupeKey: candidate.intent.dedupeKey,
					fromRole: previousEntry.role,
					kind: 'promote',
					toRole: candidate.role,
				});
			}
			if (rank > previousRank) {
				operations.push({
					dedupeKey: candidate.intent.dedupeKey,
					fromRole: previousEntry.role,
					kind: 'demote',
					toRole: candidate.role,
				});
			}
		}
		if (previousEntry === undefined && !props.inFlightDedupeKeys.has(candidate.intent.dedupeKey)) {
			operations.push({
				dedupeKey: candidate.intent.dedupeKey,
				kind: 'enqueue',
				role: candidate.role,
			});
		}
		entries.push({
			generation: props.generation,
			intent: { ...candidate.intent, demandRank: rank },
			rank,
			role: candidate.role,
			startEligible: candidate.role === 'selected' || !props.paused,
		});
	}

	return {
		entries: entries.toSorted(comparePlanEntries),
		generation: props.generation,
		operations,
	};
}

function dedupeCandidatesToHighestRole(
	candidates: readonly BridgeContentDemandCandidate[],
): ReadonlyMap<string, BridgeContentDemandCandidate> {
	const candidateByDedupeKey = new Map<string, BridgeContentDemandCandidate>();
	for (const candidate of candidates) {
		const existingCandidate = candidateByDedupeKey.get(candidate.intent.dedupeKey);
		if (existingCandidate === undefined || compareCandidates(candidate, existingCandidate) < 0) {
			candidateByDedupeKey.set(candidate.intent.dedupeKey, candidate);
		}
	}
	return candidateByDedupeKey;
}

function compareCandidates(
	left: BridgeContentDemandCandidate,
	right: BridgeContentDemandCandidate,
): number {
	const rankComparison = demandRankForContentRole(left.role) - demandRankForContentRole(right.role);
	if (rankComparison !== 0) {
		return rankComparison;
	}
	return left.intent.orderingKey.localeCompare(right.intent.orderingKey);
}

function comparePlanEntries(
	left: BridgeContentDemandPlanEntry,
	right: BridgeContentDemandPlanEntry,
): number {
	const rankComparison = left.rank - right.rank;
	if (rankComparison !== 0) {
		return rankComparison;
	}
	return left.intent.orderingKey.localeCompare(right.intent.orderingKey);
}
