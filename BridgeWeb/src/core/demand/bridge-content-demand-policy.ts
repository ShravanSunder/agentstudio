import type { BridgeContentDemandRole } from '../models/bridge-demand-models.js';

export const bridgeContentDemandExecutionPolicy = {
	/** Protects Shiki/highlight worker start pressure; validated by per-lane queue-wait telemetry. */
	immediateStartConcurrency: 6,
	/** Protects executor starts for adjacent warming; validated by review_content_demand lane counts. */
	nearbyStartConcurrency: 2,
	/** Protects executor starts for hover/prediction work; validated by review_content_demand lane counts. */
	speculativeStartConcurrency: 1,
	/** Protects executor starts for package-prefix warming; validated by review_content_demand lane counts. */
	backgroundStartConcurrency: 1,
	/** Protects visible queue wait; coalescing is per reconciler pass, validated by visible queue-wait p95. */
	dispatchDelayMilliseconds: 0,
} as const;

export const bridgeContentDemandMembershipPolicy = {
	/** Protects momentum-scroll coverage; validated by post-settle untracked drain time. */
	lookAheadViewportsInScrollDirection: 2,
	/** Protects reverse-scroll recovery; validated by post-settle untracked drain time. */
	lookBehindViewports: 1,
	/** Protects runaway derivation bugs only; validated by overflow telemetry and demotes, never drops. */
	sanityOverflowDemoteThreshold: 512,
} as const;

export const bridgeContentDemandRetentionPolicy = {
	/** Protects re-entry latency; validated by cache hit ratio on re-entry. */
	reviewContentRegistryMaxEntries: 2048,
	/** Protects startup IO and byte-cache pressure; validated by aborted background fetch count. */
	backgroundPrefixMaxFileCount: 40,
	/** Protects byte-cache pressure; validated by aborted background fetch count. */
	backgroundPrefixMaxByteCacheFraction: 0.25,
} as const;

const contentDemandRoleRank: Readonly<Record<BridgeContentDemandRole, number>> = {
	selected: 0,
	visible: 1,
	nearby: 2,
	speculative: 3,
	background: 4,
};

export function demandRankForContentRole(role: BridgeContentDemandRole): number {
	return contentDemandRoleRank[role];
}
