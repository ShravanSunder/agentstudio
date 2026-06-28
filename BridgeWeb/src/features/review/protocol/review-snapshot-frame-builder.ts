import type { BridgeAttachedResourceDescriptor } from '../../../core/models/bridge-resource-descriptor.js';
import type { BridgeReviewPackage } from '../../../foundation/review-package/bridge-review-package.js';
import type {
	ReviewChangesetClusterMetadata,
	ReviewDeltaFrame,
	ReviewSnapshotFrame,
} from '../models/review-protocol-models.js';

export interface BuildReviewSnapshotFrameProps {
	readonly package: BridgeReviewPackage;
	readonly paneId: string;
	readonly sourceIdentity: string;
	readonly streamId: string;
	readonly sequence: number;
	readonly changesetCluster?: ReviewChangesetClusterMetadata;
}

export interface BuildReviewDeltaFrameProps extends BuildReviewSnapshotFrameProps {
	readonly fromRevision: number;
	readonly toRevision: number;
}

const reviewProtocolMetadataDescriptorMaxBytes = 768 * 1024;

export function buildReviewSnapshotFrame(
	props: BuildReviewSnapshotFrameProps,
): ReviewSnapshotFrame {
	const rootDescriptor = buildRootDescriptor(props);

	return {
		kind: 'snapshot',
		streamId: props.streamId,
		generation: props.package.reviewGeneration,
		sequence: props.sequence,
		frameKind: 'review.snapshot',
		package: {
			packageId: props.package.packageId,
			sourceIdentity: props.sourceIdentity,
			generation: props.package.reviewGeneration,
			revision: props.package.revision,
			rootDescriptor,
			...(props.changesetCluster === undefined ? {} : { changesetCluster: props.changesetCluster }),
		},
	};
}

export function buildReviewDeltaFrame(props: BuildReviewDeltaFrameProps): ReviewDeltaFrame {
	const operationsDescriptor = buildDeltaOperationsDescriptor(props);

	return {
		kind: 'delta',
		streamId: props.streamId,
		generation: props.package.reviewGeneration,
		sequence: props.sequence,
		frameKind: 'review.delta',
		packageId: props.package.packageId,
		fromRevision: props.fromRevision,
		toRevision: props.toRevision,
		operationsDescriptor,
	};
}

function buildRootDescriptor(
	props: BuildReviewSnapshotFrameProps,
): BridgeAttachedResourceDescriptor {
	const packageByteLength = new TextEncoder().encode(JSON.stringify(props.package)).byteLength;
	const descriptorId = [
		'review-package',
		props.package.packageId,
		String(props.package.reviewGeneration),
		String(props.package.revision),
	].join('-');
	const identity = {
		paneId: props.paneId,
		protocol: 'review',
		sourceId: props.sourceIdentity,
		packageId: props.package.packageId,
		generation: props.package.reviewGeneration,
		revision: props.package.revision,
		streamId: props.streamId,
	};
	const descriptor = {
		descriptorId,
		protocol: 'review',
		resourceKind: 'review-package',
		resourceUrl: `agentstudio://resource/review/review-package/${descriptorId}?generation=${props.package.reviewGeneration}&revision=${props.package.revision}`,
		identity,
		content: {
			mediaType: 'application/json',
			encoding: 'utf-8',
			expectedBytes: packageByteLength,
			maxBytes: Math.max(packageByteLength, 1),
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

function buildDeltaOperationsDescriptor(
	props: BuildReviewDeltaFrameProps,
): BridgeAttachedResourceDescriptor {
	const descriptorId = [
		'review-delta',
		props.package.packageId,
		String(props.fromRevision),
		String(props.toRevision),
	].join('-');
	const identity = {
		paneId: props.paneId,
		protocol: 'review',
		sourceId: props.sourceIdentity,
		packageId: props.package.packageId,
		generation: props.package.reviewGeneration,
		revision: props.toRevision,
		streamId: props.streamId,
	};
	const descriptor = {
		descriptorId,
		protocol: 'review',
		resourceKind: 'review-delta',
		resourceUrl: `agentstudio://resource/review/review-delta/${descriptorId}?generation=${props.package.reviewGeneration}&revision=${props.toRevision}`,
		identity,
		content: {
			mediaType: 'application/json',
			encoding: 'utf-8',
			maxBytes: reviewProtocolMetadataDescriptorMaxBytes,
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
