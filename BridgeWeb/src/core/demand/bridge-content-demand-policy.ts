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
	/** Paces executor-stage delivery retries after fetch errors; validated by retry/backoff lifecycle tests. */
	deliveryFailureBackoffInitialMilliseconds: 500,
	/** Escalates persistent delivery failures without parking membership; validated by retry/backoff lifecycle tests. */
	deliveryFailureBackoffMultiplier: 4,
	/** Caps persistent fetch-error retry delay so visible content remains re-derivable; validated by retry/backoff lifecycle tests. */
	deliveryFailureBackoffMaxMilliseconds: 8_000,
	/** Half-frame main-thread materialization slice, derived from 60Hz paint budget and validated by chunk/yield tests plus frame-liveness telemetry. */
	materializationFrameBudgetMilliseconds: 8,
	/** R46 execution cap for main-thread DOM/Pierre apply; mirrors AppPolicies.Bridge.applyPumpFrameBudgetMilliseconds. */
	applyPumpFrameBudgetMilliseconds: 8,
	/** R46 execution unit cap; bounds one apply turn even when individual units are cheap. */
	applyPumpMaxUnitsPerFrame: 4,
	/** R46 pacing cap; stale pending units are cleared without monopolizing a frame. */
	applyPumpStaleScanLimit: 64,
	/** R46 fairness cap; visible apply must progress after this many selected batches. */
	applyPumpNoStarvationSelectedBatchLimit: 3,
	/** R46 selected first-paint window; first selected content apply never parses the whole file. */
	selectedApplyInitialWindowLineCount: 1_500,
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
