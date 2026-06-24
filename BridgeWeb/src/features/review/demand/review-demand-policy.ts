import type {
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
	switch (props.stimulus.kind) {
		case 'reviewItemSelected':
		case 'reviewExplicitRefresh':
			return intentForDescriptor({
				descriptorRef: props.stimulus.descriptorRef,
				forcedInterest: { kind: 'selected' },
				readContext: props.readContext,
			});
		case 'reviewDescriptorInvalidated':
			return intentForDescriptor({
				descriptorRef: props.stimulus.descriptorRef,
				readContext: props.readContext,
			});
		case 'reviewViewportChanged':
			return props.stimulus.descriptorRefs.flatMap(
				(descriptorRef: BridgeDescriptorRef): readonly BridgeDemandIntent[] =>
					intentForDescriptor({
						descriptorRef,
						forcedInterest: { kind: 'visible' },
						readContext: props.readContext,
					}),
			);
		case 'reviewHoverChanged':
			return props.stimulus.descriptorRef === null
				? []
				: intentForDescriptor({
						descriptorRef: props.stimulus.descriptorRef,
						forcedInterest: { kind: 'speculative' },
						readContext: props.readContext,
					});
		case 'reviewSourceReset':
			return [];
	}
	return [];
}

function intentForDescriptor(props: {
	readonly descriptorRef: BridgeDescriptorRef;
	readonly forcedInterest?: BridgeViewInterest;
	readonly readContext: ReviewDemandReadContext;
}): readonly BridgeDemandIntent[] {
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
	const lane = laneForViewInterest(viewInterest);
	if (lane === null) {
		return [];
	}
	return [
		{
			descriptorRef: props.descriptorRef,
			lane,
			...props.readContext.buildDemandKeys(props.descriptorRef),
		},
	];
}

function laneForViewInterest(viewInterest: BridgeViewInterest): BridgeDemandIntent['lane'] | null {
	switch (viewInterest.kind) {
		case 'selected':
			return 'foreground';
		case 'open':
			return 'active';
		case 'visible':
			return 'visible';
		case 'nearby':
			return 'nearby';
		case 'speculative':
			return 'speculative';
		case 'none':
			return null;
	}
	return null;
}
