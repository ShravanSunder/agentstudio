import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
} from '../../../core/models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../../../core/resources/bridge-resource-registry.js';
import type {
	BridgeReviewPackageSummary,
	BridgeSourceEndpoint,
} from '../../../foundation/review-package/bridge-review-package.js';
import type {
	BridgeReviewProjectionInput,
	BridgeReviewProjectionInputItem,
} from '../../../review-viewer/models/review-projection-models.js';
import type {
	ReviewChangesetClusterMetadata,
	ReviewExtentFact,
	ReviewMetadataOperation,
	ReviewProtocolFrame,
	ReviewTreeRowMetadata,
} from '../models/review-protocol-models.js';
import { reviewProtocolFrameSchema } from '../models/review-protocol-models.js';

export type ReviewMaterializerDelta =
	| {
			readonly kind: 'metadataSnapshot';
			readonly packageId: string;
			readonly sourceIdentity: string;
			readonly generation: number;
			readonly revision: number;
			readonly baseEndpoint: BridgeSourceEndpoint;
			readonly headEndpoint: BridgeSourceEndpoint;
			readonly selectedItemId: string | null;
			readonly visibleItemIds: readonly string[];
			readonly projectionInput: BridgeReviewProjectionInput;
			readonly treeRows: readonly ReviewTreeRowMetadata[];
			readonly extentFacts: readonly ReviewExtentFact[];
			readonly summary: BridgeReviewPackageSummary;
			readonly registeredContentDescriptorRefs: readonly BridgeDescriptorRef[];
			readonly contentDescriptors: readonly BridgeAttachedResourceDescriptor[];
			readonly changesetCluster: ReviewChangesetClusterMetadata | null;
	  }
	| {
			readonly kind: 'metadataWindow';
			readonly packageId: string;
			readonly generation: number;
			readonly revision: number;
			readonly itemMetadata: readonly BridgeReviewProjectionInputItem[];
			readonly treeRows: readonly ReviewTreeRowMetadata[];
			readonly extentFacts: readonly ReviewExtentFact[];
			readonly summary: BridgeReviewPackageSummary;
			readonly registeredContentDescriptorRefs: readonly BridgeDescriptorRef[];
			readonly contentDescriptors: readonly BridgeAttachedResourceDescriptor[];
	  }
	| {
			readonly kind: 'reset';
			readonly reason:
				| 'sourceChanged'
				| 'subscriptionReset'
				| 'providerRestart'
				| 'authorityChanged';
			readonly sourceIdentity: string;
	  }
	| {
			readonly kind: 'metadataDelta';
			readonly packageId: string;
			readonly fromRevision: number;
			readonly toRevision: number;
			readonly operations: readonly ReviewMetadataOperation[];
			readonly summary: BridgeReviewPackageSummary;
			readonly registeredContentDescriptorRefs: readonly BridgeDescriptorRef[];
			readonly contentDescriptors: readonly BridgeAttachedResourceDescriptor[];
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
		case 'review.metadataSnapshot': {
			const contentRegisterResult = registerContentDescriptorsTransactionally({
				registry: props.registry,
				attachedDescriptors: frame.comparison.contentDescriptors ?? [],
			});
			if (!contentRegisterResult.ok) {
				return { ok: false, reason: 'descriptor_rejected' };
			}
			return {
				ok: true,
				delta: {
					kind: 'metadataSnapshot',
					packageId: frame.comparison.packageId,
					sourceIdentity: frame.comparison.sourceIdentity,
					generation: frame.comparison.generation,
					revision: frame.comparison.revision,
					baseEndpoint: frame.comparison.baseEndpoint,
					headEndpoint: frame.comparison.headEndpoint,
					selectedItemId: frame.selectedItemId,
					visibleItemIds: frame.visibleItemIds,
					projectionInput: {
						packageId: frame.comparison.packageId,
						reviewGeneration: frame.comparison.generation,
						revision: frame.comparison.revision,
						orderedItems: frame.itemMetadata,
					},
					treeRows: frame.treeRows,
					extentFacts: frame.extentFacts,
					summary: frame.summary,
					registeredContentDescriptorRefs: contentRegisterResult.registeredContentDescriptorRefs,
					contentDescriptors: frame.comparison.contentDescriptors ?? [],
					changesetCluster: frame.comparison.changesetCluster ?? null,
				},
			};
		}
		case 'review.metadataWindow': {
			const contentRegisterResult = registerContentDescriptorsTransactionally({
				registry: props.registry,
				attachedDescriptors: frame.contentDescriptors ?? [],
			});
			if (!contentRegisterResult.ok) {
				return { ok: false, reason: 'descriptor_rejected' };
			}
			return {
				ok: true,
				delta: {
					kind: 'metadataWindow',
					packageId: frame.packageId,
					generation: frame.generation,
					revision: frame.revision,
					itemMetadata: frame.itemMetadata,
					treeRows: frame.treeRows,
					extentFacts: frame.extentFacts,
					summary: frame.summary,
					registeredContentDescriptorRefs: contentRegisterResult.registeredContentDescriptorRefs,
					contentDescriptors: frame.contentDescriptors ?? [],
				},
			};
		}
		case 'review.reset': {
			props.registry.resetIdentity({
				paneId: props.paneId,
				protocol: 'review',
				sourceId: frame.sourceIdentity,
			});
			return {
				ok: true,
				delta: {
					kind: 'reset',
					reason: frame.reason,
					sourceIdentity: frame.sourceIdentity,
				},
			};
		}
		case 'review.metadataDelta': {
			const contentRegisterResult = registerContentDescriptorsTransactionally({
				registry: props.registry,
				attachedDescriptors: frame.contentDescriptors ?? [],
			});
			if (!contentRegisterResult.ok) {
				return { ok: false, reason: 'descriptor_rejected' };
			}
			return {
				ok: true,
				delta: {
					kind: 'metadataDelta',
					packageId: frame.packageId,
					fromRevision: frame.fromRevision,
					toRevision: frame.toRevision,
					operations: frame.operations,
					summary: frame.summary,
					registeredContentDescriptorRefs: contentRegisterResult.registeredContentDescriptorRefs,
					contentDescriptors: frame.contentDescriptors ?? [],
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

function registerContentDescriptorsTransactionally(props: {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly attachedDescriptors: readonly BridgeAttachedResourceDescriptor[];
}):
	| {
			readonly ok: true;
			readonly registeredContentDescriptorRefs: readonly BridgeDescriptorRef[];
	  }
	| { readonly ok: false } {
	const registeredRefs: BridgeDescriptorRef[] = [];
	const registeredContentDescriptorRefs: BridgeDescriptorRef[] = [];
	for (const attachedDescriptor of props.attachedDescriptors) {
		const contentRegisterResult = registerAttachedDescriptorTransactionally({
			registry: props.registry,
			attachedDescriptor,
			registeredRefs,
		});
		if (!contentRegisterResult) {
			rollbackRegisteredDescriptors({ registry: props.registry, registeredRefs });
			return { ok: false };
		}
		registeredContentDescriptorRefs.push(attachedDescriptor.ref);
	}
	return { ok: true, registeredContentDescriptorRefs };
}

function rollbackRegisteredDescriptors(props: {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly registeredRefs: readonly BridgeDescriptorRef[];
}): void {
	for (const registeredRef of props.registeredRefs.toReversed()) {
		props.registry.revoke(registeredRef);
	}
}
