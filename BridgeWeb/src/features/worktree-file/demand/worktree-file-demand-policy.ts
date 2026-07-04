import type {
	BridgeDemandIntent,
	BridgeDemandKeys,
	BridgeDescriptorDemandState,
	BridgeViewInterest,
} from '../../../core/models/bridge-demand-models.js';
import type { BridgeDescriptorRef } from '../../../core/models/bridge-resource-descriptor.js';
import type { WorktreeFileDemandStimulus } from '../models/worktree-file-protocol-models.js';

export interface WorktreeFileDemandReadContext {
	getDescriptorState(ref: BridgeDescriptorRef): BridgeDescriptorDemandState;
	getViewInterest(ref: BridgeDescriptorRef): BridgeViewInterest;
	buildDemandKeys(ref: BridgeDescriptorRef): BridgeDemandKeys;
}

export interface MapWorktreeFileDemandStimulusToIntentsProps {
	readonly stimulus: WorktreeFileDemandStimulus;
	readonly readContext: WorktreeFileDemandReadContext;
}

export function mapWorktreeFileDemandStimulusToIntents(
	props: MapWorktreeFileDemandStimulusToIntentsProps,
): readonly BridgeDemandIntent[] {
	switch (props.stimulus.kind) {
		case 'fileSelected':
		case 'explicitRefresh':
			return intentForDescriptor({
				descriptorRef: props.stimulus.descriptorRef,
				forcedInterest: { kind: 'selected' },
				readContext: props.readContext,
			});
		case 'openFileInvalidated':
			return [];
		case 'treeViewportChanged':
			return props.stimulus.descriptorRefs.flatMap(
				(descriptorRef: BridgeDescriptorRef): readonly BridgeDemandIntent[] =>
					intentForDescriptor({
						descriptorRef,
						forcedInterest: { kind: 'visible' },
						readContext: props.readContext,
					}),
			);
		case 'treeExpanded':
			return [
				...intentForDescriptor({
					descriptorRef: props.stimulus.descriptorRef,
					forcedInterest: { kind: 'visible' },
					readContext: props.readContext,
				}),
				...(props.stimulus.nearbyDescriptorRefs ?? []).flatMap(
					(descriptorRef: BridgeDescriptorRef): readonly BridgeDemandIntent[] =>
						intentForDescriptor({
							descriptorRef,
							forcedInterest: { kind: 'nearby' },
							readContext: props.readContext,
						}),
				),
			];
		case 'hoverChanged':
			return props.stimulus.descriptorRef === null
				? []
				: intentForDescriptor({
						descriptorRef: props.stimulus.descriptorRef,
						forcedInterest: { kind: 'speculative' },
						readContext: props.readContext,
					});
		case 'recentlyUpdatedFile':
			return intentForDescriptor({
				descriptorRef: props.stimulus.descriptorRef,
				forcedInterest:
					props.stimulus.proximity === 'nearby' ? { kind: 'nearby' } : { kind: 'speculative' },
				readContext: props.readContext,
			});
		case 'sourceReset':
			return [];
	}
	return assertNever(props.stimulus);
}

function intentForDescriptor(props: {
	readonly descriptorRef: BridgeDescriptorRef;
	readonly forcedInterest: BridgeViewInterest;
	readonly readContext: WorktreeFileDemandReadContext;
}): readonly BridgeDemandIntent[] {
	const descriptorState = props.readContext.getDescriptorState(props.descriptorRef);
	if (
		descriptorState.kind === 'missing' ||
		descriptorState.kind === 'reset' ||
		!descriptorState.needsBodyOrWindow
	) {
		return [];
	}
	const lane = laneForViewInterest(props.forcedInterest);
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
		case 'background':
			return 'idle';
		case 'none':
			return null;
	}
	return assertNever(viewInterest);
}

function assertNever(value: never): never {
	throw new Error(`Unhandled worktree file demand policy case: ${String(value)}`);
}
