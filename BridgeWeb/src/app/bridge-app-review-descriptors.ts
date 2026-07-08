import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
	BridgeIdentity,
} from '../core/models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import { parseBridgeCoreResourceUrl } from '../core/resources/bridge-resource-url.js';
import {
	applyValidatedReviewProtocolFrame,
	type ReviewMaterializerDelta,
} from '../features/review/materialization/review-materializer.js';
import type {
	ReviewMetadataDeltaFrame,
	ReviewMetadataSnapshotFrame,
	ReviewMetadataWindowFrame,
	ReviewInvalidationFrame,
	ReviewProtocolFrame,
	ReviewResetFrame,
} from '../features/review/models/review-protocol-models.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import type { BridgeReviewFrameAuthority } from './bridge-app-review-frame-authority.js';
import { bridgeReviewContentByteBoundsForHandle } from './bridge-review-content-byte-budget.js';

export const bridgeReviewAllowedResourceKindsByProtocol = {
	review: new Set(['content']),
};

type ReviewSnapshotMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataSnapshot' }
>;
type ReviewDeltaMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataDelta' }
>;
type ReviewWindowMaterializerDelta = Extract<
	ReviewMaterializerDelta,
	{ readonly kind: 'metadataWindow' }
>;

interface MaterializedReviewSnapshotForPackage {
	readonly descriptorRefsByHandleId: ReadonlyMap<string, BridgeDescriptorRef>;
}

export function materializeReviewProtocolSnapshotFrame(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): ReviewSnapshotMaterializerDelta | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataSnapshot' ||
		!reviewSnapshotFrameMatchesAuthority({
			frame: props.protocolFrame,
			reviewFrameAuthority: props.reviewFrameAuthority,
		}) ||
		props.reviewFrameAuthority === null
	) {
		return null;
	}
	const materializeResult = applyValidatedReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	return materializeResult.ok && materializeResult.delta.kind === 'metadataSnapshot'
		? materializeResult.delta
		: null;
}

export function materializeReviewProtocolDeltaFrame(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): ReviewDeltaMaterializerDelta | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataDelta' ||
		!reviewDeltaFrameMatchesAuthority({
			frame: props.protocolFrame,
			reviewFrameAuthority: props.reviewFrameAuthority,
		}) ||
		props.reviewFrameAuthority === null
	) {
		return null;
	}
	const materializeResult = applyValidatedReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	return materializeResult.ok && materializeResult.delta.kind === 'metadataDelta'
		? materializeResult.delta
		: null;
}

export function materializeReviewProtocolWindowFrame(props: {
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): ReviewWindowMaterializerDelta | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataWindow' ||
		!reviewWindowFrameMatchesAuthority({
			frame: props.protocolFrame,
			reviewFrameAuthority: props.reviewFrameAuthority,
		}) ||
		props.reviewFrameAuthority === null
	) {
		return null;
	}
	const materializeResult = applyValidatedReviewProtocolFrame({
		frame: props.protocolFrame,
		paneId: props.reviewFrameAuthority.paneId,
		registry: props.descriptorRegistry,
	});
	return materializeResult.ok && materializeResult.delta.kind === 'metadataWindow'
		? materializeResult.delta
		: null;
}

export function materializeAcceptedReviewSnapshotForPackage(props: {
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly protocolFrame: ReviewProtocolFrame | null;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
	readonly reviewPackage: BridgeReviewPackage;
	readonly snapshotFrame: ReviewSnapshotMaterializerDelta;
}): MaterializedReviewSnapshotForPackage | null {
	if (
		props.protocolFrame?.frameKind !== 'review.metadataSnapshot' ||
		props.reviewFrameAuthority === null ||
		!reviewSnapshotFrameMatchesPackage({
			frame: props.protocolFrame,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		})
	) {
		return null;
	}
	const descriptorRefsByHandleId = reviewSnapshotDescriptorRefsByHandleIdForPackage({
		descriptorRegistry: props.descriptorRegistry,
		frame: props.protocolFrame,
		reviewFrameAuthority: props.reviewFrameAuthority,
		reviewPackage: props.reviewPackage,
	});
	if (descriptorRefsByHandleId === null) {
		return null;
	}
	return { descriptorRefsByHandleId };
}

export function reviewSnapshotDescriptorRefsByHandleIdForPackage(props: {
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
	readonly frame: ReviewMetadataSnapshotFrame;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): ReadonlyMap<string, BridgeDescriptorRef> | null {
	if (
		!reviewSnapshotFrameMatchesPackage({
			frame: props.frame,
			reviewFrameAuthority: props.reviewFrameAuthority,
			reviewPackage: props.reviewPackage,
		})
	) {
		return null;
	}
	return deriveAndRegisterReviewContentDescriptorRefs({
		descriptorRegistry: props.descriptorRegistry,
		frame: props.frame,
		reviewFrameAuthority: props.reviewFrameAuthority,
		reviewPackage: props.reviewPackage,
	});
}

export function reviewInvalidationFrameMatchesCurrentAuthority(props: {
	readonly frame: ReviewInvalidationFrame;
	readonly currentReviewPackage: BridgeReviewPackage | null;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	if (props.currentReviewPackage === null) {
		return true;
	}
	return props.frame.generation >= props.currentReviewPackage.reviewGeneration;
}

export function reviewResetFrameMatchesCurrentAuthority(props: {
	readonly frame: ReviewResetFrame;
	readonly currentReviewPackage: BridgeReviewPackage | null;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	if (props.currentReviewPackage === null) {
		return true;
	}
	if (props.frame.sourceIdentity !== props.currentReviewPackage.query.queryId) {
		return false;
	}
	if (props.frame.generation < props.currentReviewPackage.reviewGeneration) {
		return false;
	}
	return true;
}

function reviewSnapshotFrameMatchesPackage(props: {
	readonly frame: ReviewMetadataSnapshotFrame;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	if (
		props.frame.comparison.packageId === props.reviewPackage.packageId &&
		props.frame.comparison.sourceIdentity === props.reviewPackage.query.queryId &&
		props.frame.comparison.generation === props.reviewPackage.reviewGeneration &&
		props.frame.comparison.revision === props.reviewPackage.revision
	) {
		return reviewSnapshotFrameDescriptorsMatchPackage({
			frame: props.frame,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		});
	}
	return false;
}

export function reviewSnapshotFrameDescriptorsMatchPackage(props: {
	readonly frame: ReviewMetadataSnapshotFrame;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): boolean {
	const handlesById = contentHandlesByIdForReviewPackage(props.reviewPackage);
	const descriptorIds = new Set<string>();
	const attachedDescriptors = props.frame.comparison.contentDescriptors ?? [];
	if (attachedDescriptors.length === 0) {
		return true;
	}
	for (const attachedDescriptor of attachedDescriptors) {
		if (descriptorIds.has(attachedDescriptor.ref.descriptorId)) {
			return false;
		}
		descriptorIds.add(attachedDescriptor.ref.descriptorId);
		if (
			!contentDescriptorMatchesPackageHandle({
				attachedDescriptor,
				frameAuthority: props.reviewFrameAuthority,
				handlesById,
				props,
			})
		) {
			return false;
		}
	}
	return true;
}

function contentDescriptorMatchesPackageHandle(args: {
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly frameAuthority: BridgeReviewFrameAuthority;
	readonly handlesById: ReadonlyMap<string, BridgeContentHandle>;
	readonly props: {
		readonly reviewPackage: BridgeReviewPackage;
		readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
	};
}): boolean {
	const handle = args.handlesById.get(args.attachedDescriptor.ref.descriptorId) ?? null;
	if (handle === null) {
		return false;
	}
	const expectedIdentity: BridgeIdentity = {
		paneId: args.frameAuthority.paneId,
		protocol: 'review',
		sourceId: args.props.reviewPackage.query.queryId,
		packageId: args.props.reviewPackage.packageId,
		generation: handle.reviewGeneration,
		...(args.attachedDescriptor.descriptor.identity.revision === undefined
			? {}
			: { revision: args.attachedDescriptor.descriptor.identity.revision }),
		streamId: args.frameAuthority.streamId,
		...(args.attachedDescriptor.descriptor.identity.cursor === undefined
			? {}
			: { cursor: args.attachedDescriptor.descriptor.identity.cursor }),
	};
	return (
		args.attachedDescriptor.ref.expectedProtocol === 'review' &&
		args.attachedDescriptor.ref.expectedResourceKind === 'content' &&
		args.attachedDescriptor.descriptor.protocol === 'review' &&
		args.attachedDescriptor.descriptor.resourceKind === 'content' &&
		contentDescriptorResourceUrlMatchesPackageHandle({
			attachedDescriptor: args.attachedDescriptor,
			handle,
		}) &&
		args.attachedDescriptor.descriptor.content.mediaType === handle.mimeType &&
		contentDescriptorByteBoundsMatchPackageHandle({
			attachedDescriptor: args.attachedDescriptor,
			handle,
		}) &&
		bridgeIdentitiesEqual(args.attachedDescriptor.ref.expectedIdentity, expectedIdentity) &&
		bridgeIdentitiesEqual(args.attachedDescriptor.descriptor.identity, expectedIdentity)
	);
}

function contentDescriptorResourceUrlMatchesPackageHandle(args: {
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly handle: BridgeContentHandle;
}): boolean {
	const descriptorResourceUrl = parseBridgeCoreResourceUrl(
		args.attachedDescriptor.descriptor.resourceUrl,
		{
			allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
		},
	);
	const handleResourceUrl = parseBridgeCoreResourceUrl(args.handle.resourceUrl, {
		allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
	});
	return (
		descriptorResourceUrl !== null &&
		handleResourceUrl !== null &&
		descriptorResourceUrl.protocol === 'review' &&
		descriptorResourceUrl.resourceKind === 'content' &&
		descriptorResourceUrl.opaqueId === args.handle.handleId &&
		descriptorResourceUrl.canonicalUrl === handleResourceUrl.canonicalUrl
	);
}

function contentDescriptorByteBoundsMatchPackageHandle(args: {
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly handle: BridgeContentHandle;
}): boolean {
	const descriptorBounds = args.attachedDescriptor.descriptor.content;
	const handleBounds = bridgeReviewContentByteBoundsForHandle(args.handle);
	return (
		descriptorBounds.expectedBytes === handleBounds.expectedBytes &&
		descriptorBounds.maxBytes === handleBounds.maxBytes
	);
}

function contentHandlesByIdForReviewPackage(
	reviewPackage: BridgeReviewPackage,
): ReadonlyMap<string, BridgeContentHandle> {
	const handlesById = new Map<string, BridgeContentHandle>();
	for (const item of Object.values(reviewPackage.itemsById)) {
		for (const handle of Object.values(item.contentRoles)) {
			if (handle !== null && handle !== undefined) {
				handlesById.set(handle.handleId, handle);
			}
		}
	}
	return handlesById;
}

function deriveAndRegisterReviewContentDescriptorRefs(props: {
	readonly reviewPackage: BridgeReviewPackage;
	readonly frame?: ReviewMetadataSnapshotFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
	readonly descriptorRegistry: BridgeResourceDescriptorRegistry;
}): ReadonlyMap<string, BridgeDescriptorRef> | null {
	const descriptorRefsByHandleId = new Map<string, BridgeDescriptorRef>();
	const handlesById = contentHandlesByIdForReviewPackage(props.reviewPackage);
	for (const attachedDescriptor of props.frame?.comparison.contentDescriptors ?? []) {
		const handle = handlesById.get(attachedDescriptor.ref.descriptorId);
		if (handle === undefined) {
			return null;
		}
		const registerResult = props.descriptorRegistry.register(attachedDescriptor);
		if (!registerResult.ok) {
			return null;
		}
		descriptorRefsByHandleId.set(handle.handleId, attachedDescriptor.ref);
	}
	for (const handle of handlesById.values()) {
		if (descriptorRefsByHandleId.has(handle.handleId)) {
			continue;
		}
		const attachedDescriptor = deriveReviewContentDescriptorFromHandle({
			handle,
			reviewPackage: props.reviewPackage,
			reviewFrameAuthority: props.reviewFrameAuthority,
		});
		if (attachedDescriptor === null) {
			return null;
		}
		const registerResult = props.descriptorRegistry.register(attachedDescriptor);
		if (!registerResult.ok) {
			return null;
		}
		descriptorRefsByHandleId.set(handle.handleId, attachedDescriptor.ref);
	}
	return descriptorRefsByHandleId;
}

function deriveReviewContentDescriptorFromHandle(props: {
	readonly handle: BridgeContentHandle;
	readonly reviewPackage: BridgeReviewPackage;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority;
}): BridgeAttachedResourceDescriptor | null {
	const parsedResourceUrl = parseBridgeCoreResourceUrl(props.handle.resourceUrl, {
		allowedResourceKindsByProtocol: bridgeReviewAllowedResourceKindsByProtocol,
	});
	if (
		parsedResourceUrl === null ||
		parsedResourceUrl.protocol !== 'review' ||
		parsedResourceUrl.resourceKind !== 'content' ||
		parsedResourceUrl.opaqueId !== props.handle.handleId
	) {
		return null;
	}
	const identity: BridgeIdentity = {
		paneId: props.reviewFrameAuthority.paneId,
		protocol: 'review',
		sourceId: props.reviewPackage.query.queryId,
		packageId: props.reviewPackage.packageId,
		generation: props.handle.reviewGeneration,
		...(parsedResourceUrl.revision === undefined ? {} : { revision: parsedResourceUrl.revision }),
		streamId: props.reviewFrameAuthority.streamId,
		...(parsedResourceUrl.cursor === undefined ? {} : { cursor: parsedResourceUrl.cursor }),
	};
	const integrity =
		props.handle.contentHashAlgorithm === 'sha256' && props.handle.contentHash.length > 0
			? ({
					kind: 'wholeHash',
					algorithm: 'sha256',
					value: props.handle.contentHash,
				} as const)
			: undefined;
	const byteBounds = bridgeReviewContentByteBoundsForHandle(props.handle);
	const descriptor = {
		descriptorId: parsedResourceUrl.opaqueId,
		protocol: 'review',
		resourceKind: 'content',
		resourceUrl: parsedResourceUrl.canonicalUrl,
		identity,
		content: {
			mediaType: props.handle.mimeType,
			encoding: props.handle.isBinary ? 'binary' : 'utf-8',
			...(byteBounds.expectedBytes === undefined
				? {}
				: { expectedBytes: byteBounds.expectedBytes }),
			maxBytes: byteBounds.maxBytes,
			...(integrity === undefined ? {} : { integrity }),
		},
	} satisfies BridgeAttachedResourceDescriptor['descriptor'];
	return {
		ref: {
			descriptorId: descriptor.descriptorId,
			expectedProtocol: descriptor.protocol,
			expectedResourceKind: descriptor.resourceKind,
			expectedIdentity: identity,
		},
		descriptor,
	};
}

export function reviewItemDemandCancellationTargetForSelectionChange(props: {
	readonly previousSelectedItemId: string | null;
	readonly reviewPackage: BridgeReviewPackage;
}): BridgeReviewItemDescriptor | undefined {
	return props.previousSelectedItemId === null
		? undefined
		: props.reviewPackage.itemsById[props.previousSelectedItemId];
}

function bridgeIdentitiesEqual(left: BridgeIdentity, right: BridgeIdentity): boolean {
	return (
		left.paneId === right.paneId &&
		left.protocol === right.protocol &&
		left.sourceId === right.sourceId &&
		left.packageId === right.packageId &&
		left.generation === right.generation &&
		left.revision === right.revision &&
		left.streamId === right.streamId &&
		left.cursor === right.cursor
	);
}

export function reviewSnapshotFrameMatchesAuthority(props: {
	readonly frame: ReviewMetadataSnapshotFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	return (
		props.frame.comparison.packageId.length > 0 &&
		props.frame.comparison.sourceIdentity.length > 0 &&
		props.frame.comparison.generation === props.frame.generation
	);
}

function reviewDeltaFrameMatchesAuthority(props: {
	readonly frame: ReviewMetadataDeltaFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	return (
		props.frame.packageId.length > 0 &&
		props.frame.fromRevision <= props.frame.toRevision &&
		props.frame.generation >= 0
	);
}

function reviewWindowFrameMatchesAuthority(props: {
	readonly frame: ReviewMetadataWindowFrame;
	readonly reviewFrameAuthority: BridgeReviewFrameAuthority | null;
}): boolean {
	if (
		props.reviewFrameAuthority === null ||
		props.frame.streamId !== props.reviewFrameAuthority.streamId
	) {
		return false;
	}
	return props.frame.packageId.length > 0 && props.frame.generation >= 0;
}
