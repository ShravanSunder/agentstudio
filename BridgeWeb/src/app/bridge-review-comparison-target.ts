import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';

export type BridgeReviewComparisonTarget = NonNullable<
	NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']>['activeTarget']
>;

export function bridgeReviewComparisonTargetLabel(target: BridgeReviewComparisonTarget): string {
	switch (target.kind) {
		case 'localDefaultBranch':
			return target.branchName;
		case 'originDefaultBranch':
			return `${target.remoteName}/${target.branchName}`;
		case 'branch':
		case 'ref':
			return target.name;
		case 'commit':
			return target.oid;
		default:
			return assertNeverComparisonTarget(target);
	}
}

function assertNeverComparisonTarget(target: never): never {
	throw new Error(`Unexpected Review comparison target: ${JSON.stringify(target)}`);
}
