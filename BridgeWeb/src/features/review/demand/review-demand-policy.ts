import type { BridgeContentDemandCandidate } from '../../../core/demand/bridge-content-demand-reconciler.js';
import type {
	BridgeContentDemandRole,
	BridgeDemandIntent,
	BridgeDemandKeys,
	BridgeDescriptorDemandState,
	BridgeViewInterest,
} from '../../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../../core/models/bridge-resource-descriptor.js';
import type { ReviewDemandStimulus } from '../models/review-protocol-models.js';

export interface ReviewDemandReadContext {
	getDescriptorState(ref: BridgeDescriptorRef): BridgeDescriptorDemandState;
	getViewInterest(ref: BridgeDescriptorRef): BridgeViewInterest;
	buildDemandKeys(ref: BridgeDescriptorRef): BridgeDemandKeys;
}

export interface MapReviewDemandStimulusToIntentsProps {
	readonly stimulus: ReviewDemandStimulus;
	readonly readContext: ReviewDemandReadContext;
}

export function mapReviewDemandStimulusToIntents(
	props: MapReviewDemandStimulusToIntentsProps,
): readonly BridgeDemandIntent[] {
	return mapReviewDemandStimulusToContentDemandCandidates(props).map(
		(candidate): BridgeDemandIntent => candidate.intent,
	);
}

export function mapReviewDemandStimulusToContentDemandCandidates(
	props: MapReviewDemandStimulusToIntentsProps,
): readonly BridgeContentDemandCandidate[] {
	switch (props.stimulus.kind) {
		case 'reviewItemSelected':
		case 'reviewExplicitRefresh':
			return candidatesForDescriptor({
				descriptorRef: props.stimulus.descriptorRef,
				forcedInterest: { kind: 'selected' },
				readContext: props.readContext,
			});
		case 'reviewDescriptorInvalidated':
			return candidatesForDescriptor({
				descriptorRef: props.stimulus.descriptorRef,
				readContext: props.readContext,
			});
		case 'reviewViewportChanged':
			return props.stimulus.descriptorRefs.flatMap(
				(descriptorRef: BridgeDescriptorRef): readonly BridgeContentDemandCandidate[] =>
					candidatesForDescriptor({
						descriptorRef,
						forcedInterest: { kind: 'visible' },
						readContext: props.readContext,
					}),
			);
		case 'reviewHoverChanged':
			return props.stimulus.descriptorRef === null
				? []
				: candidatesForDescriptor({
						descriptorRef: props.stimulus.descriptorRef,
						forcedInterest: { kind: 'speculative' },
						readContext: props.readContext,
					});
		case 'reviewSourceReset':
			return [];
	}
	return [];
}

function candidatesForDescriptor(props: {
	readonly descriptorRef: BridgeDescriptorRef;
	readonly forcedInterest?: BridgeViewInterest;
	readonly readContext: ReviewDemandReadContext;
}): readonly BridgeContentDemandCandidate[] {
	const descriptorState = props.readContext.getDescriptorState(props.descriptorRef);
	if (
		descriptorState.kind === 'missing' ||
		descriptorState.kind === 'reset' ||
		!descriptorState.needsBodyOrWindow
	) {
		return [];
	}
	const viewInterest =
		props.forcedInterest ?? props.readContext.getViewInterest(props.descriptorRef);
	const role = contentDemandRoleForViewInterest(viewInterest);
	if (role === null) {
		return [];
	}
	return [
		{
			intent: {
				descriptorRef: props.descriptorRef,
				lane: laneForContentDemandRole(role),
				...props.readContext.buildDemandKeys(props.descriptorRef),
			},
			role,
		},
	];
}

function contentDemandRoleForViewInterest(
	viewInterest: BridgeViewInterest,
): BridgeContentDemandRole | null {
	switch (viewInterest.kind) {
		case 'selected':
			return 'selected';
		case 'open':
			return 'visible';
		case 'visible':
			return 'visible';
		case 'nearby':
			return 'nearby';
		case 'speculative':
			return 'speculative';
		case 'background':
			return 'background';
		case 'none':
			return null;
	}
	return null;
}

function laneForContentDemandRole(role: BridgeContentDemandRole): BridgeDemandIntent['lane'] {
	switch (role) {
		case 'selected':
			return 'foreground';
		case 'visible':
			return 'visible';
		case 'nearby':
			return 'nearby';
		case 'speculative':
			return 'speculative';
		case 'background':
			return 'idle';
	}
	return assertNever(role);
}

function assertNever(value: never): never {
	throw new Error(`Unhandled review demand policy case: ${String(value)}`);
}
