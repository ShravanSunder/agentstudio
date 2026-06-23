import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
} from '../../../core/models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../../../core/resources/bridge-resource-registry.js';
import type {
	ReviewChangesetClusterMetadata,
	ReviewProtocolFrame,
} from '../models/review-protocol-models.js';
import { reviewProtocolFrameSchema } from '../models/review-protocol-models.js';

export type ReviewMaterializerDelta =
	| {
			readonly kind: 'snapshot';
			readonly packageId: string;
			readonly sourceIdentity: string;
			readonly generation: number;
			readonly revision: number;
			readonly rootDescriptorRef: BridgeDescriptorRef;
			readonly registeredContentDescriptorRefs: readonly BridgeDescriptorRef[];
			readonly changesetCluster: ReviewChangesetClusterMetadata | null;
	  }
	| {
			readonly kind: 'reset';
			readonly reason:
				| 'sourceChanged'
				| 'subscriptionReset'
				| 'providerRestart'
				| 'authorityChanged';
			readonly sourceIdentity: string;
			readonly packageId?: string;
			readonly replacementDescriptorRef?: BridgeDescriptorRef;
	  }
	| {
			readonly kind: 'delta';
			readonly packageId: string;
			readonly fromRevision: number;
			readonly toRevision: number;
			readonly operationsDescriptorRef: BridgeDescriptorRef;
			readonly registeredContentDescriptorRefs: readonly BridgeDescriptorRef[];
	  }
	| {
			readonly kind: 'invalidate';
			readonly scope: 'package' | 'items' | 'paths' | 'treeWindow';
			readonly itemIds?: readonly string[];
			readonly pathHints?: readonly string[];
			readonly reason: 'sourceChanged' | 'watchEvent' | 'lineageReplaced' | 'unknown';
	  };

export type ApplyReviewProtocolFrameResult =
	| {
			readonly ok: true;
			readonly delta: ReviewMaterializerDelta;
	  }
	| {
			readonly ok: false;
			readonly reason: 'invalid_frame' | 'descriptor_rejected' | 'unsupported_frame';
	  };

export interface ApplyReviewProtocolFrameProps {
	readonly frame: ReviewProtocolFrame;
	readonly paneId: string;
	readonly registry: BridgeResourceDescriptorRegistry;
}

export function applyReviewProtocolFrame(
	props: ApplyReviewProtocolFrameProps,
): ApplyReviewProtocolFrameResult {
	const parsedFrame = reviewProtocolFrameSchema.safeParse(props.frame);
	if (!parsedFrame.success) {
		return { ok: false, reason: 'invalid_frame' };
	}
	const frame = parsedFrame.data;
	switch (frame.frameKind) {
		case 'review.snapshot': {
			const registeredRefs: BridgeDescriptorRef[] = [];
			const registeredContentDescriptorRefs: BridgeDescriptorRef[] = [];
			const registerRootResult = registerAttachedDescriptorTransactionally({
				registry: props.registry,
				attachedDescriptor: frame.package.rootDescriptor,
				registeredRefs,
			});
			if (!registerRootResult) {
				rollbackRegisteredDescriptors({ registry: props.registry, registeredRefs });
				return { ok: false, reason: 'descriptor_rejected' };
			}
			for (const attachedDescriptor of frame.package.contentDescriptors ?? []) {
				const contentRegisterResult = registerAttachedDescriptorTransactionally({
					registry: props.registry,
					attachedDescriptor,
					registeredRefs,
				});
				if (!contentRegisterResult) {
					rollbackRegisteredDescriptors({ registry: props.registry, registeredRefs });
					return { ok: false, reason: 'descriptor_rejected' };
				}
				registeredContentDescriptorRefs.push(attachedDescriptor.ref);
			}
			return {
				ok: true,
				delta: {
					kind: 'snapshot',
					packageId: frame.package.packageId,
					sourceIdentity: frame.package.sourceIdentity,
					generation: frame.package.generation,
					revision: frame.package.revision,
					rootDescriptorRef: frame.package.rootDescriptor.ref,
					registeredContentDescriptorRefs,
					changesetCluster: frame.package.changesetCluster ?? null,
				},
			};
		}
		case 'review.reset': {
			props.registry.resetIdentity({
				paneId: props.paneId,
				protocol: 'review',
				sourceId: frame.sourceIdentity,
				...(frame.packageId === undefined ? {} : { packageId: frame.packageId }),
			});
			if (frame.replacementDescriptor === undefined) {
				return {
					ok: true,
					delta: {
						kind: 'reset',
						reason: frame.reason,
						sourceIdentity: frame.sourceIdentity,
						...(frame.packageId === undefined ? {} : { packageId: frame.packageId }),
					},
				};
			}
			const replacementRegisterResult = props.registry.register(frame.replacementDescriptor);
			if (!replacementRegisterResult.ok) {
				return { ok: false, reason: 'descriptor_rejected' };
			}
			return {
				ok: true,
				delta: {
					kind: 'reset',
					reason: frame.reason,
					sourceIdentity: frame.sourceIdentity,
					...(frame.packageId === undefined ? {} : { packageId: frame.packageId }),
					replacementDescriptorRef: frame.replacementDescriptor.ref,
				},
			};
		}
		case 'review.delta': {
			const registeredRefs: BridgeDescriptorRef[] = [];
			const registeredContentDescriptorRefs: BridgeDescriptorRef[] = [];
			const registerOperationsResult = registerAttachedDescriptorTransactionally({
				registry: props.registry,
				attachedDescriptor: frame.operationsDescriptor,
				registeredRefs,
			});
			if (!registerOperationsResult) {
				rollbackRegisteredDescriptors({ registry: props.registry, registeredRefs });
				return { ok: false, reason: 'descriptor_rejected' };
			}
			for (const attachedDescriptor of frame.contentDescriptors ?? []) {
				const contentRegisterResult = registerAttachedDescriptorTransactionally({
					registry: props.registry,
					attachedDescriptor,
					registeredRefs,
				});
				if (!contentRegisterResult) {
					rollbackRegisteredDescriptors({ registry: props.registry, registeredRefs });
					return { ok: false, reason: 'descriptor_rejected' };
				}
				registeredContentDescriptorRefs.push(attachedDescriptor.ref);
			}
			return {
				ok: true,
				delta: {
					kind: 'delta',
					packageId: frame.packageId,
					fromRevision: frame.fromRevision,
					toRevision: frame.toRevision,
					operationsDescriptorRef: frame.operationsDescriptor.ref,
					registeredContentDescriptorRefs,
				},
			};
		}
		case 'review.invalidate':
			return {
				ok: true,
				delta: {
					kind: 'invalidate',
					scope: frame.invalidation.scope,
					...(frame.invalidation.itemIds === undefined
						? {}
						: { itemIds: frame.invalidation.itemIds }),
					...(frame.invalidation.pathHints === undefined
						? {}
						: { pathHints: frame.invalidation.pathHints }),
					reason: frame.invalidation.reason,
				},
			};
	}
	return { ok: false, reason: 'invalid_frame' };
}

function registerAttachedDescriptorTransactionally(props: {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly registeredRefs: BridgeDescriptorRef[];
}): boolean {
	const registerResult = props.registry.register(props.attachedDescriptor);
	if (!registerResult.ok) {
		return false;
	}
	props.registeredRefs.push(props.attachedDescriptor.ref);
	return true;
}

function rollbackRegisteredDescriptors(props: {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly registeredRefs: readonly BridgeDescriptorRef[];
}): void {
	for (const registeredRef of props.registeredRefs.toReversed()) {
		props.registry.revoke(registeredRef);
	}
}
