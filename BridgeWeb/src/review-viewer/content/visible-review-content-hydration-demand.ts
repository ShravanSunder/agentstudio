import {
	reconcileBridgeContentDemand,
	type BridgeContentDemandCandidate,
	type BridgeContentDemandPlan,
	type BridgeContentDemandPlanEntry,
} from '../../core/demand/bridge-content-demand-reconciler.js';
import type { BridgeContentDemandRole } from '../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../core/models/bridge-resource-descriptor.js';
import { mapReviewDemandStimulusToContentDemandCandidates } from '../../features/review/demand/review-demand-policy.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import {
	demandFreshnessKeyForReviewDescriptorRef,
	demandKeysForPlan,
	demandPlansForReviewItem,
} from './review-content-demand-policy.js';
import type { BridgeReviewContentRegistry } from './review-content-registry.js';
import {
	makeVisibleReviewItemContentResourcesKey,
	selectedAdjacentReviewItemIds,
} from './visible-review-content-hydration-identity.js';
import type { VisibleContentResourcesState } from './visible-review-content-hydration-support.js';

type VisibleReviewContentDemandInterest = Extract<
	import('./review-content-demand-loader.js').ReviewContentDemandInterest,
	'nearby' | 'visible'
>;

export interface DeriveVisibleReviewContentLoadPlansProps {
	readonly contentInvalidationVersion: number;
	readonly contentRegistry: Pick<BridgeReviewContentRegistry, 'peekResource'>;
	readonly contentStateByItemId: ReadonlyMap<string, VisibleContentResourcesState>;
	readonly generation: number;
	readonly paused: boolean;
	readonly previousEntries: readonly BridgeContentDemandPlanEntry[];
	readonly reviewPackage: BridgeReviewPackage;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
	readonly scheduledContentKeys: ReadonlySet<string>;
	readonly selectedItemId: string | null;
	readonly visibleItemIds: readonly string[];
}

export interface DerivedVisibleReviewContentLoadPlans {
	readonly loadPlans: readonly VisibleReviewContentLoadPlan[];
	readonly reconciledPlan: BridgeContentDemandPlan;
}

export interface VisibleReviewContentLoadPlan {
	readonly contentKey: string;
	readonly interest: VisibleReviewContentDemandInterest;
	readonly item: BridgeReviewItemDescriptor;
	readonly itemId: string;
}

interface VisibleReviewContentDemandItemContext {
	readonly contentKey: string;
	readonly interest: VisibleReviewContentDemandInterest | 'selected';
	readonly item: BridgeReviewItemDescriptor;
	readonly itemId: string;
}

export function deriveVisibleReviewContentLoadPlans(
	props: DeriveVisibleReviewContentLoadPlansProps,
): DerivedVisibleReviewContentLoadPlans {
	const itemContexts = visibleReviewContentDemandItemContexts(props);
	const demandCandidates: BridgeContentDemandCandidate[] = [];
	const loadedDedupeKeys = new Set<string>();
	const inFlightDedupeKeys = new Set<string>();
	const contextByDedupeKey = new Map<string, VisibleReviewContentDemandItemContext>();
	for (const itemContext of itemContexts) {
		const candidateResult = contentDemandCandidatesForItemContext({
			contentRegistry: props.contentRegistry,
			itemContext,
			resolveDescriptorRef: props.resolveDescriptorRef,
		});
		for (const loadedDedupeKey of candidateResult.loadedDedupeKeys) {
			loadedDedupeKeys.add(loadedDedupeKey);
		}
		for (const candidate of candidateResult.candidates) {
			demandCandidates.push(candidate);
			contextByDedupeKey.set(candidate.intent.dedupeKey, itemContext);
			if (
				props.scheduledContentKeys.has(itemContext.contentKey) ||
				props.contentStateByItemId.get(itemContext.itemId)?.status === 'loading'
			) {
				inFlightDedupeKeys.add(candidate.intent.dedupeKey);
			}
		}
	}
	const reconciledPlan = reconcileBridgeContentDemand({
		candidates: demandCandidates,
		generation: props.generation,
		inFlightDedupeKeys,
		loadedDedupeKeys,
		paused: props.paused,
		previousEntries: props.previousEntries,
	});
	const loadPlans = loadPlansForReconciledEntries({
		contextByDedupeKey,
		entries: reconciledPlan.entries,
	});
	return { loadPlans, reconciledPlan };
}

function visibleReviewContentDemandItemContexts(
	props: DeriveVisibleReviewContentLoadPlansProps,
): readonly VisibleReviewContentDemandItemContext[] {
	const itemContexts: VisibleReviewContentDemandItemContext[] = [];
	const seenItemIds = new Set<string>();
	const selectedItem =
		props.selectedItemId === null ? undefined : props.reviewPackage.itemsById[props.selectedItemId];
	if (selectedItem !== undefined && props.selectedItemId !== null) {
		itemContexts.push({
			contentKey: makeVisibleReviewItemContentResourcesKey({
				contentInvalidationVersion: props.contentInvalidationVersion,
				item: selectedItem,
				reviewPackage: props.reviewPackage,
			}),
			interest: 'selected',
			item: selectedItem,
			itemId: props.selectedItemId,
		});
		seenItemIds.add(props.selectedItemId);
	}
	const selectedAdjacentItemIds = new Set(
		selectedAdjacentReviewItemIds({
			reviewPackage: props.reviewPackage,
			selectedItemId: props.selectedItemId,
		}),
	);
	for (const itemId of props.visibleItemIds) {
		if (seenItemIds.has(itemId)) {
			continue;
		}
		const item = props.reviewPackage.itemsById[itemId];
		if (item === undefined) {
			continue;
		}
		itemContexts.push({
			contentKey: makeVisibleReviewItemContentResourcesKey({
				contentInvalidationVersion: props.contentInvalidationVersion,
				item,
				reviewPackage: props.reviewPackage,
			}),
			interest: selectedAdjacentItemIds.has(itemId) ? 'nearby' : 'visible',
			item,
			itemId,
		});
		seenItemIds.add(itemId);
	}
	return itemContexts;
}

function contentDemandCandidatesForItemContext(props: {
	readonly contentRegistry: Pick<BridgeReviewContentRegistry, 'peekResource'>;
	readonly itemContext: VisibleReviewContentDemandItemContext;
	readonly resolveDescriptorRef: (handle: BridgeContentHandle) => BridgeDescriptorRef | null;
}): {
	readonly candidates: readonly BridgeContentDemandCandidate[];
	readonly loadedDedupeKeys: readonly string[];
} {
	const plans = demandPlansForReviewItem({
		item: props.itemContext.item,
		interest: props.itemContext.interest,
		presentation: null,
		resolveDescriptorRef: props.resolveDescriptorRef,
	});
	if (plans === null) {
		return { candidates: [], loadedDedupeKeys: [] };
	}
	const candidates: BridgeContentDemandCandidate[] = [];
	const loadedDedupeKeys: string[] = [];
	for (const plan of plans) {
		const planCandidates = mapReviewDemandStimulusToContentDemandCandidates({
			stimulus: { kind: 'reviewDescriptorInvalidated', descriptorRef: plan.descriptorRef },
			readContext: {
				getDescriptorState: () => ({
					kind: 'valid',
					freshnessKey: demandFreshnessKeyForReviewDescriptorRef(plan.descriptorRef),
					needsBodyOrWindow: true,
				}),
				getViewInterest: () => ({ kind: props.itemContext.interest }),
				buildDemandKeys: () => demandKeysForPlan(plan, props.itemContext.interest),
			},
		});
		const cachedResource = props.contentRegistry.peekResource(plan.handle);
		for (const candidate of planCandidates) {
			if (cachedResource === null) {
				candidates.push(candidate);
				continue;
			}
			loadedDedupeKeys.push(candidate.intent.dedupeKey);
		}
	}
	return { candidates, loadedDedupeKeys };
}

function loadPlansForReconciledEntries(props: {
	readonly contextByDedupeKey: ReadonlyMap<string, VisibleReviewContentDemandItemContext>;
	readonly entries: readonly BridgeContentDemandPlanEntry[];
}): readonly VisibleReviewContentLoadPlan[] {
	const plannedItemIds = new Set<string>();
	const loadPlans: VisibleReviewContentLoadPlan[] = [];
	for (const entry of props.entries) {
		if (!entry.startEligible) {
			continue;
		}
		const interest = visibleReviewContentDemandInterestForRole(entry.role);
		if (interest === null) {
			continue;
		}
		const itemContext = props.contextByDedupeKey.get(entry.intent.dedupeKey);
		if (itemContext === undefined || plannedItemIds.has(itemContext.itemId)) {
			continue;
		}
		plannedItemIds.add(itemContext.itemId);
		loadPlans.push({
			contentKey: itemContext.contentKey,
			interest,
			item: itemContext.item,
			itemId: itemContext.itemId,
		});
	}
	return loadPlans;
}

function visibleReviewContentDemandInterestForRole(
	role: BridgeContentDemandRole,
): VisibleReviewContentDemandInterest | null {
	switch (role) {
		case 'visible':
			return 'visible';
		case 'nearby':
			return 'nearby';
		case 'selected':
		case 'speculative':
		case 'background':
			return null;
	}
	return null;
}
