import type { BridgeWorkerPanelChromePatchPayload } from '../core/comm-worker/bridge-worker-contracts.js';

export type BridgeReviewComparisonTarget = NonNullable<
	NonNullable<BridgeWorkerPanelChromePatchPayload['reviewComparison']>['activeTarget']
>;

export function bridgeReviewComparisonTargetsAreEqual(
	first: BridgeReviewComparisonTarget,
	second: BridgeReviewComparisonTarget,
): boolean {
	if (first.kind !== second.kind) return false;
	switch (first.kind) {
		case 'localDefaultBranch':
			return (
				second.kind === first.kind &&
				first.basis === second.basis &&
				first.branchName === second.branchName
			);
		case 'originDefaultBranch':
			return (
				second.kind === first.kind &&
				first.basis === second.basis &&
				first.branchName === second.branchName &&
				first.remoteName === second.remoteName
			);
		case 'branch':
		case 'ref':
			return (
				second.kind === first.kind && first.basis === second.basis && first.name === second.name
			);
		case 'commit':
			return second.kind === first.kind && first.oid === second.oid;
		default:
			return assertNeverComparisonTarget(first);
	}
}

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
