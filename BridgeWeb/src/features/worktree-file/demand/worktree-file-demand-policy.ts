import type { BridgeContentDemandCandidate } from '../../../core/demand/bridge-content-demand-reconciler.js';
import type {
	BridgeContentDemandRole,
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
	return mapWorktreeFileDemandStimulusToContentDemandCandidates(props).map(
		(candidate): BridgeDemandIntent => candidate.intent,
	);
}

export function mapWorktreeFileDemandStimulusToContentDemandCandidates(
	props: MapWorktreeFileDemandStimulusToIntentsProps,
): readonly BridgeContentDemandCandidate[] {
	switch (props.stimulus.kind) {
		case 'fileSelected':
		case 'explicitRefresh':
			return candidatesForDescriptor({
				descriptorRef: props.stimulus.descriptorRef,
				forcedInterest: { kind: 'selected' },
				readContext: props.readContext,
			});
		case 'openFileInvalidated':
			return [];
		case 'treeViewportChanged':
			return props.stimulus.descriptorRefs.flatMap(
				(descriptorRef: BridgeDescriptorRef): readonly BridgeContentDemandCandidate[] =>
					candidatesForDescriptor({
						descriptorRef,
						forcedInterest: { kind: 'visible' },
						readContext: props.readContext,
					}),
			);
		case 'treeExpanded':
			return [
				...candidatesForDescriptor({
					descriptorRef: props.stimulus.descriptorRef,
					forcedInterest: { kind: 'visible' },
					readContext: props.readContext,
				}),
				...(props.stimulus.nearbyDescriptorRefs ?? []).flatMap(
					(descriptorRef: BridgeDescriptorRef): readonly BridgeContentDemandCandidate[] =>
						candidatesForDescriptor({
							descriptorRef,
							forcedInterest: { kind: 'nearby' },
							readContext: props.readContext,
						}),
				),
			];
		case 'hoverChanged':
			return props.stimulus.descriptorRef === null
				? []
				: candidatesForDescriptor({
						descriptorRef: props.stimulus.descriptorRef,
						forcedInterest: { kind: 'speculative' },
						readContext: props.readContext,
					});
		case 'recentlyUpdatedFile':
			return candidatesForDescriptor({
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

function candidatesForDescriptor(props: {
	readonly descriptorRef: BridgeDescriptorRef;
	readonly forcedInterest: BridgeViewInterest;
	readonly readContext: WorktreeFileDemandReadContext;
}): readonly BridgeContentDemandCandidate[] {
	const descriptorState = props.readContext.getDescriptorState(props.descriptorRef);
	if (
		descriptorState.kind === 'missing' ||
		descriptorState.kind === 'reset' ||
		!descriptorState.needsBodyOrWindow
	) {
		return [];
	}
	const role = contentDemandRoleForViewInterest(props.forcedInterest);
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
	return assertNever(viewInterest);
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
	throw new Error(`Unhandled worktree file demand policy case: ${String(value)}`);
}
