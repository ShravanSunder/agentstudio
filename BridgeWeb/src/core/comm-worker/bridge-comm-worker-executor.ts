import { demandRankForContentRole } from '../demand/bridge-content-demand-policy.js';
import type { BridgeCommWorkerDemandMember } from './bridge-comm-worker-reconciler.js';

export type { BridgeCommWorkerDemandMember };

export interface BridgeCommWorkerDemandBackoff {
	readonly attemptCount: number;
	readonly retryEligibleAtMilliseconds: number;
}

export type BridgeCommWorkerDemandDeferredItem =
	| {
			readonly itemId: string;
			readonly reason: 'backoff';
			readonly retryEligibleAtMilliseconds: number;
	  }
	| {
			readonly itemId: string;
			readonly reason: 'inFlight' | 'pacing';
			readonly retryEligibleAtMilliseconds: null;
	  };

export interface PlanBridgeCommWorkerDemandExecutionProps {
	readonly backoffByItemId: ReadonlyMap<string, BridgeCommWorkerDemandBackoff>;
	readonly inFlightItemIds: ReadonlySet<string>;
	readonly maxStartCount: number;
	readonly membership: readonly BridgeCommWorkerDemandMember[];
	readonly nowMilliseconds: number;
}

export interface BridgeCommWorkerDemandExecutionPlan {
	readonly deferredItems: readonly BridgeCommWorkerDemandDeferredItem[];
	readonly startItemIds: readonly string[];
}

export function planBridgeCommWorkerDemandExecution(
	props: PlanBridgeCommWorkerDemandExecutionProps,
): BridgeCommWorkerDemandExecutionPlan {
	const startItemIds: string[] = [];
	const deferredItems: BridgeCommWorkerDemandDeferredItem[] = [];
	const sortedMembership = [...props.membership].toSorted(compareBridgeCommWorkerDemandMembers);
	for (const member of sortedMembership) {
		if (props.inFlightItemIds.has(member.itemId)) {
			deferredItems.push({
				itemId: member.itemId,
				reason: 'inFlight',
				retryEligibleAtMilliseconds: null,
			});
			continue;
		}
		const backoff = props.backoffByItemId.get(member.itemId);
		if (backoff !== undefined && backoff.retryEligibleAtMilliseconds > props.nowMilliseconds) {
			deferredItems.push({
				itemId: member.itemId,
				reason: 'backoff',
				retryEligibleAtMilliseconds: backoff.retryEligibleAtMilliseconds,
			});
			continue;
		}
		if (startItemIds.length >= props.maxStartCount) {
			deferredItems.push({
				itemId: member.itemId,
				reason: 'pacing',
				retryEligibleAtMilliseconds: null,
			});
			continue;
		}
		startItemIds.push(member.itemId);
	}
	return { deferredItems, startItemIds };
}

function compareBridgeCommWorkerDemandMembers(
	left: BridgeCommWorkerDemandMember,
	right: BridgeCommWorkerDemandMember,
): number {
	return demandRankForContentRole(left.role) - demandRankForContentRole(right.role);
}
