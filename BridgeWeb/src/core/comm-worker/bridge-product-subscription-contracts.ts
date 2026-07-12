import { z } from 'zod';

import type { BridgeDemandLane } from '../models/bridge-demand-models.js';
import { bridgeProductFileContentDescriptorSchema } from './bridge-product-content-contracts.js';
import {
	type BridgeProductAssert,
	bridgeProductDemandLaneSchema,
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
	type BridgeProductRegistryValue,
	bridgeProductSafeMessageSchema,
	bridgeProductUnicodeScalarUtf8ByteLength,
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
	type BridgeProductTypeSetsEqual,
} from './bridge-product-contract-primitives.js';
import { bridgeProductExactUtf8IdentitySet } from './bridge-product-exact-utf8-identity.js';
import {
	bridgeProductFileSourceIdentitySchema,
	type BridgeProductFileSourceIdentity,
} from './bridge-product-file-contracts.js';
import { bridgeProductReviewMetadataEventSchema } from './bridge-product-review-metadata-contracts.js';
import { preflightBridgeProductSubscriptionInterestStateCanonicalEncoding } from './bridge-product-subscription-interest-preflight.js';

export { bridgeProductSubscriptionInterestDeltaItemCount } from './bridge-product-subscription-accounting.js';
export {
	preflightBridgeProductSubscriptionInterestStateCanonicalEncoding,
	type BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight,
} from './bridge-product-subscription-interest-preflight.js';

export {
	bridgeProductFileSourceIdentitySchema,
	type BridgeProductFileSourceIdentity,
} from './bridge-product-file-contracts.js';

export type BridgeProductDemandLaneParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<z.infer<typeof bridgeProductDemandLaneSchema>, BridgeDemandLane>
>;

const bridgeProductMaximumInterestGroupCount = 64;
const bridgeProductMaximumReviewInterestIdentityBytes = 128;
export const BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT = 10_000;
export const BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT = 40_000;
export const BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT = 256;
export const BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_OPERATION_COUNT = 256;
export const BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT = 256;

const bridgeProductReviewInterestIdentitySchema = z
	.string()
	.min(1)
	.superRefine((value, context): void => {
		const byteLength = bridgeProductUnicodeScalarUtf8ByteLength(value);
		if (byteLength === null) {
			context.addIssue({
				code: 'custom',
				message:
					'Bridge product Review interest identities must contain only Unicode scalar values.',
			});
			return;
		}
		if (byteLength > bridgeProductMaximumReviewInterestIdentityBytes) {
			context.addIssue({
				code: 'custom',
				message: `Bridge product Review interest identities cannot exceed ${bridgeProductMaximumReviewInterestIdentityBytes} UTF-8 bytes.`,
			});
		}
	});

const bridgeProductReviewMetadataInterestSchema = z
	.object({
		itemIds: z
			.array(bridgeProductReviewInterestIdentitySchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT)
			.readonly(),
		lane: bridgeProductDemandLaneSchema,
	})
	.strict();

export const bridgeProductReviewMetadataSubscriptionOptionsSchema = z
	.object({
		interests: z
			.array(bridgeProductReviewMetadataInterestSchema)
			.max(bridgeProductMaximumInterestGroupCount)
			.readonly(),
	})
	.strict()
	.superRefine((options, context): void => {
		const itemIds = options.interests.flatMap((interest) => interest.itemIds);
		if (itemIds.length > BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT) {
			context.addIssue({
				code: 'custom',
				message: 'Review metadata interests exceed the aggregate item ceiling.',
				path: ['interests'],
			});
		}
		if (bridgeProductExactUtf8IdentitySet(itemIds).size !== itemIds.length) {
			context.addIssue({
				code: 'custom',
				message: 'Review metadata interest items must be unique across demand lanes.',
				path: ['interests'],
			});
		}
	});

export const bridgeProductFileSourceConfigurationSchema = z
	.object({
		cwdScope: bridgeProductDisplayPathSchema.nullable(),
		freshness: z.literal('live'),
		includeStatuses: z.boolean(),
		repoId: z.uuid(),
		rootPathToken: bridgeProductOpaqueReferenceSchema,
		worktreeId: z.uuid(),
	})
	.strict();

const bridgeProductFileMetadataInterestSchema = z
	.object({
		lane: bridgeProductDemandLaneSchema,
		paths: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT)
			.readonly(),
	})
	.strict();

export const bridgeProductFileMetadataSubscriptionOptionsSchema = z
	.object({
		interests: z
			.array(bridgeProductFileMetadataInterestSchema)
			.max(bridgeProductMaximumInterestGroupCount)
			.readonly(),
		pathScope: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT)
			.readonly(),
		source: bridgeProductFileSourceConfigurationSchema,
	})
	.strict()
	.superRefine((options, context): void => {
		const interestPaths = options.interests.flatMap((interest) => interest.paths);
		if (interestPaths.length > BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata interests exceed the aggregate path ceiling.',
				path: ['interests'],
			});
		}
		if (bridgeProductExactUtf8IdentitySet(interestPaths).size !== interestPaths.length) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata interest paths must be unique across demand lanes.',
				path: ['interests'],
			});
		}
		if (bridgeProductExactUtf8IdentitySet(options.pathScope).size !== options.pathScope.length) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata path scope entries must be unique.',
				path: ['pathScope'],
			});
		}
	});

export const bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema =
	bridgeProductReviewMetadataSubscriptionOptionsSchema;

export const bridgeProductFileMetadataSubscriptionUpdateOptionsSchema = z
	.object({
		interests: z
			.array(bridgeProductFileMetadataInterestSchema)
			.max(bridgeProductMaximumInterestGroupCount)
			.readonly(),
		pathScope: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT)
			.readonly(),
	})
	.strict()
	.superRefine((options, context): void => {
		const interestPaths = options.interests.flatMap((interest) => interest.paths);
		if (interestPaths.length > BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata interests exceed the aggregate path ceiling.',
				path: ['interests'],
			});
		}
		if (bridgeProductExactUtf8IdentitySet(interestPaths).size !== interestPaths.length) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata interest paths must be unique across demand lanes.',
				path: ['interests'],
			});
		}
		if (bridgeProductExactUtf8IdentitySet(options.pathScope).size !== options.pathScope.length) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata path scope entries must be unique.',
				path: ['pathScope'],
			});
		}
	});

const bridgeProductSubscriptionInterestStateStructuralSchema = z.discriminatedUnion(
	'subscriptionKind',
	[
		bridgeProductFileMetadataSubscriptionUpdateOptionsSchema.safeExtend({
			subscriptionKind: z.literal('file.metadata'),
		}),
		bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema.safeExtend({
			subscriptionKind: z.literal('review.metadata'),
		}),
	],
);

export const bridgeProductSubscriptionInterestStateSchema =
	bridgeProductSubscriptionInterestStateStructuralSchema.superRefine((state, context): void => {
		const preflight = preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(state);
		if (preflight.status === 'exceedsMaximum') {
			context.addIssue({
				code: 'custom',
				message: `Bridge product canonical interest state cannot exceed ${BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES} bytes.`,
			});
		}
	});

export const bridgeProductFileChangeStatusSchema = z.enum([
	'added',
	'deleted',
	'modified',
	'renamed',
	'copied',
	'typeChanged',
	'unmerged',
	'untracked',
]);

export const bridgeProductFileMetadataLoadedBySchema = z.enum([
	'startup_window',
	'foreground',
	'visible',
	'nearby',
	'speculative',
	'idle',
	'delta',
	'reset',
	'replacement',
]);

export const bridgeProductFileMetadataLineageSchema = z
	.object({
		lane: bridgeProductDemandLaneSchema,
		loadedBy: bridgeProductFileMetadataLoadedBySchema,
	})
	.strict();

export const bridgeProductFileTreeRowSchema = z
	.object({
		changeStatus: bridgeProductFileChangeStatusSchema.nullable(),
		depth: bridgeProductNonnegativeSequenceSchema,
		fileId: bridgeProductIdentifierSchema.nullable(),
		isDirectory: z.boolean(),
		lineCount: bridgeProductNonnegativeSequenceSchema.nullable(),
		name: bridgeProductDisplayPathSchema,
		parentPath: bridgeProductDisplayPathSchema.nullable(),
		path: bridgeProductDisplayPathSchema,
		rowId: bridgeProductIdentifierSchema,
		sizeBytes: bridgeProductNonnegativeSequenceSchema.nullable(),
	})
	.strict();

const bridgeProductFileTreeOperationSchema = z.discriminatedUnion('op', [
	z
		.object({
			op: z.literal('upsertRows'),
			rows: z
				.array(bridgeProductFileTreeRowSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT)
				.readonly(),
		})
		.strict(),
	z
		.object({
			op: z.literal('removeRows'),
			paths: z
				.array(bridgeProductDisplayPathSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT)
				.readonly(),
			rowIds: z
				.array(bridgeProductIdentifierSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT)
				.readonly(),
		})
		.strict()
		.superRefine((operation, context): void => {
			if (operation.rowIds.length === 0 && operation.paths.length === 0) {
				context.addIssue({
					code: 'custom',
					message: 'File metadata row removal requires a row or path identity.',
				});
			}
		}),
]);

const bridgeProductFileStatusPatchSchema = z.discriminatedUnion('patchKind', [
	z
		.object({
			ahead: bridgeProductNonnegativeSequenceSchema.nullable(),
			behind: bridgeProductNonnegativeSequenceSchema.nullable(),
			branchName: bridgeProductSafeMessageSchema.nullable(),
			patchKind: z.literal('summary'),
			staged: bridgeProductNonnegativeSequenceSchema.nullable(),
			unstaged: bridgeProductNonnegativeSequenceSchema.nullable(),
			untracked: bridgeProductNonnegativeSequenceSchema.nullable(),
		})
		.strict(),
	z
		.object({
			patchKind: z.literal('invalidated'),
			reason: z.literal('git_status_changed'),
		})
		.strict(),
	z
		.object({
			patchKind: z.literal('path'),
			path: bridgeProductDisplayPathSchema,
			status: bridgeProductFileChangeStatusSchema.nullable(),
		})
		.strict(),
]);

export const bridgeProductFileVirtualizedExtentKindSchema = z.enum([
	'exactLineCount',
	'estimatedHeight',
	'previewBounded',
	'unavailable',
]);

export const bridgeProductFileTruncationKindSchema = z.enum([
	'none',
	'byteLimit',
	'lineLimit',
	'both',
]);

const bridgeProductFileDescriptorAvailabilitySchema = z.discriminatedUnion('availabilityKind', [
	z
		.object({
			availabilityKind: z.literal('available'),
			contentDescriptor: bridgeProductFileContentDescriptorSchema,
		})
		.strict(),
	z.object({ availabilityKind: z.literal('binary') }).strict(),
	z
		.object({
			availabilityKind: z.literal('unavailable'),
			reason: z.enum(['unreadable', 'unsupported_encoding', 'outside_scope']),
		})
		.strict(),
]);

const bridgeProductFileDescriptorReadyPayloadShape = {
	availability: bridgeProductFileDescriptorAvailabilitySchema,
	encoding: z.literal('utf-8').nullable(),
	endsMidLine: z.boolean(),
	endsWithNewline: z.boolean(),
	estimatedContentHeightPixels: z.number().finite().nonnegative().nullable(),
	fileExtension: bridgeProductSafeMessageSchema.nullable(),
	fileId: bridgeProductIdentifierSchema,
	language: bridgeProductSafeMessageSchema.nullable(),
	modifiedAtUnixMilliseconds: bridgeProductNonnegativeSequenceSchema.nullable(),
	path: bridgeProductDisplayPathSchema,
	payloadByteCount: bridgeProductNonnegativeSequenceSchema,
	payloadLineCount: bridgeProductNonnegativeSequenceSchema,
	rowId: bridgeProductIdentifierSchema,
	sizeBytes: bridgeProductNonnegativeSequenceSchema,
	source: bridgeProductFileSourceIdentitySchema,
	totalLineCount: bridgeProductNonnegativeSequenceSchema.nullable(),
	truncationKind: bridgeProductFileTruncationKindSchema,
	virtualizedExtentKind: bridgeProductFileVirtualizedExtentKindSchema,
} as const;

export const bridgeProductFileDescriptorReadyPayloadSchema = z
	.object(bridgeProductFileDescriptorReadyPayloadShape)
	.strict()
	.superRefine((descriptor, context): void => {
		if (
			descriptor.virtualizedExtentKind === 'exactLineCount' &&
			descriptor.totalLineCount === null
		) {
			context.addIssue({
				code: 'custom',
				message: 'Exact File metadata extents require a total line count.',
				path: ['totalLineCount'],
			});
		}
		if (
			descriptor.availability.availabilityKind === 'available' &&
			(descriptor.availability.contentDescriptor.fileId !== descriptor.fileId ||
				!bridgeProductFileSourceIdentitiesEqual(
					descriptor.availability.contentDescriptor.source,
					descriptor.source,
				))
		) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata and content descriptor identities must match.',
				path: ['availability', 'contentDescriptor', 'fileId'],
			});
		}
		validateBridgeProductFileExtentFacts(descriptor, context);
		validateBridgeProductFilePrefixFacts(descriptor, context);
	});

function validateBridgeProductFileExtentFacts(
	descriptor: z.infer<z.ZodObject<typeof bridgeProductFileDescriptorReadyPayloadShape>>,
	context: z.RefinementCtx,
): void {
	if (
		descriptor.virtualizedExtentKind === 'estimatedHeight' ||
		descriptor.estimatedContentHeightPixels !== null
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'File metadata cannot fabricate an estimated display height.',
			['virtualizedExtentKind'],
		);
	}
	if (descriptor.availability.availabilityKind !== 'available') {
		if (descriptor.virtualizedExtentKind !== 'unavailable') {
			addBridgeProductFilePrefixIssue(
				context,
				'Binary and unavailable File descriptors require an unavailable extent.',
				['virtualizedExtentKind'],
			);
		}
		return;
	}
	const expectedExtentKind =
		descriptor.truncationKind === 'none' ? 'exactLineCount' : 'previewBounded';
	if (descriptor.virtualizedExtentKind !== expectedExtentKind) {
		addBridgeProductFilePrefixIssue(
			context,
			'Available File descriptor extent must match complete or truncated prefix facts.',
			['virtualizedExtentKind'],
		);
	}
}

function validateBridgeProductFilePrefixFacts(
	descriptor: z.infer<z.ZodObject<typeof bridgeProductFileDescriptorReadyPayloadShape>>,
	context: z.RefinementCtx,
): void {
	if (descriptor.payloadByteCount > descriptor.sizeBytes) {
		addBridgeProductFilePrefixIssue(
			context,
			'File payload bytes cannot exceed the authoritative source byte count.',
			['payloadByteCount'],
		);
	}
	if (
		descriptor.totalLineCount !== null &&
		descriptor.payloadLineCount > descriptor.totalLineCount
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'File payload lines cannot exceed the authoritative total line count.',
			['payloadLineCount'],
		);
	}
	if (descriptor.endsMidLine && descriptor.endsWithNewline) {
		addBridgeProductFilePrefixIssue(
			context,
			'A File payload cannot end both mid-line and with a newline.',
			['endsMidLine'],
		);
	}
	if (
		(descriptor.payloadByteCount === 0 && descriptor.payloadLineCount !== 0) ||
		(descriptor.payloadByteCount > 0 && descriptor.payloadLineCount === 0)
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'File payload byte and line emptiness facts must agree.',
			['payloadLineCount'],
		);
	}
	if (descriptor.payloadByteCount === 0 && (descriptor.endsMidLine || descriptor.endsWithNewline)) {
		addBridgeProductFilePrefixIssue(
			context,
			'An empty File payload cannot carry a terminal line-boundary fact.',
			['endsWithNewline'],
		);
	}

	if (descriptor.availability.availabilityKind !== 'available') {
		validateBridgeProductUnavailableFilePrefixFacts(descriptor, context);
		return;
	}
	validateBridgeProductAvailableFilePrefixFacts(descriptor, context);
}

function validateBridgeProductUnavailableFilePrefixFacts(
	descriptor: z.infer<z.ZodObject<typeof bridgeProductFileDescriptorReadyPayloadShape>>,
	context: z.RefinementCtx,
): void {
	if (
		descriptor.encoding !== null ||
		descriptor.payloadByteCount !== 0 ||
		descriptor.payloadLineCount !== 0 ||
		descriptor.totalLineCount !== null ||
		descriptor.truncationKind !== 'none' ||
		descriptor.endsMidLine ||
		descriptor.endsWithNewline
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'Binary and unavailable File descriptors must carry explicit empty prefix facts.',
			['availability'],
		);
	}
}

function validateBridgeProductAvailableFilePrefixFacts(
	descriptor: z.infer<z.ZodObject<typeof bridgeProductFileDescriptorReadyPayloadShape>>,
	context: z.RefinementCtx,
): void {
	if (descriptor.availability.availabilityKind !== 'available') {
		return;
	}
	const contentDescriptor = descriptor.availability.contentDescriptor;
	if (descriptor.encoding !== 'utf-8') {
		addBridgeProductFilePrefixIssue(
			context,
			'Available File descriptors require literal UTF-8 encoding.',
			['encoding'],
		);
	}
	if (contentDescriptor.declaredByteLength !== descriptor.payloadByteCount) {
		addBridgeProductFilePrefixIssue(
			context,
			'File content declared bytes must equal the descriptor payload byte count.',
			['availability', 'contentDescriptor', 'declaredByteLength'],
		);
	}
	if (descriptor.payloadByteCount > contentDescriptor.window.maximumBytes) {
		addBridgeProductFilePrefixIssue(
			context,
			'File payload bytes exceed the declared prefix window.',
			['payloadByteCount'],
		);
	}
	if (descriptor.payloadLineCount > contentDescriptor.window.maximumLines) {
		addBridgeProductFilePrefixIssue(
			context,
			'File payload lines exceed the declared prefix window.',
			['payloadLineCount'],
		);
	}

	const isTruncated = descriptor.truncationKind !== 'none';
	if (isTruncated === (descriptor.payloadByteCount === descriptor.sizeBytes)) {
		addBridgeProductFilePrefixIssue(
			context,
			'File truncation must agree with payload and source byte counts.',
			['truncationKind'],
		);
	}
	if (descriptor.truncationKind === 'none') {
		if (descriptor.endsMidLine) {
			addBridgeProductFilePrefixIssue(context, 'An untruncated File payload cannot end mid-line.', [
				'endsMidLine',
			]);
		}
		if (
			descriptor.totalLineCount !== null &&
			descriptor.totalLineCount !== descriptor.payloadLineCount
		) {
			addBridgeProductFilePrefixIssue(
				context,
				'An untruncated File payload must equal the authoritative total line count.',
				['totalLineCount'],
			);
		}
		return;
	}
	if (descriptor.endsMidLine && descriptor.truncationKind === 'lineLimit') {
		addBridgeProductFilePrefixIssue(
			context,
			'A line-limited File payload must stop at a complete line terminator.',
			['endsMidLine'],
		);
	}
	if (
		(descriptor.truncationKind === 'lineLimit' || descriptor.truncationKind === 'both') &&
		descriptor.payloadLineCount !== contentDescriptor.window.maximumLines
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'Line-limited File payloads must fill the declared line window.',
			['payloadLineCount'],
		);
	}
	if (
		descriptor.truncationKind === 'lineLimit' &&
		(!descriptor.endsWithNewline || descriptor.endsMidLine)
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'A line-limited File payload must end with a newline.',
			['endsWithNewline'],
		);
	}
	if (
		(descriptor.truncationKind === 'byteLimit' || descriptor.truncationKind === 'both') &&
		descriptor.sizeBytes <= contentDescriptor.window.maximumBytes
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'Byte-limited File payloads require a source larger than the byte window.',
			['sizeBytes'],
		);
	}
	if (
		descriptor.truncationKind === 'byteLimit' &&
		descriptor.payloadLineCount >= contentDescriptor.window.maximumLines
	) {
		addBridgeProductFilePrefixIssue(
			context,
			'A byte-only File truncation cannot also fill the line window.',
			['payloadLineCount'],
		);
	}
}

function addBridgeProductFilePrefixIssue(
	context: z.RefinementCtx,
	message: string,
	path: readonly PropertyKey[],
): void {
	context.addIssue({ code: 'custom', message, path: [...path] });
}

const bridgeProductFileSourceAcceptedEventSchema = z
	.object({
		eventKind: z.literal('file.sourceAccepted'),
		source: bridgeProductFileSourceIdentitySchema,
	})
	.strict();

const bridgeProductFileTreeWindowEventSchema = z
	.object({
		eventKind: z.literal('file.treeWindow'),
		finalWindow: z.boolean(),
		lineage: bridgeProductFileMetadataLineageSchema,
		pathScope: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT)
			.readonly(),
		rows: z
			.array(bridgeProductFileTreeRowSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_TREE_WINDOW_ROW_COUNT)
			.readonly(),
		source: bridgeProductFileSourceIdentitySchema,
		startIndex: bridgeProductNonnegativeSequenceSchema,
		totalRowCount: bridgeProductNonnegativeSequenceSchema.nullable(),
	})
	.strict();

const bridgeProductFileTreeDeltaEventSchema = z
	.object({
		eventKind: z.literal('file.treeDelta'),
		operations: z
			.array(bridgeProductFileTreeOperationSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_OPERATION_COUNT)
			.readonly(),
		source: bridgeProductFileSourceIdentitySchema,
	})
	.strict()
	.superRefine((event, context): void => {
		const memberCount = event.operations.reduce(
			(count, operation) =>
				count +
				(operation.op === 'upsertRows'
					? operation.rows.length
					: Math.max(operation.rowIds.length, operation.paths.length)),
			0,
		);
		if (memberCount > BRIDGE_PRODUCT_MAXIMUM_FILE_METADATA_DELTA_MEMBER_COUNT) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata tree delta exceeds its aggregate member ceiling.',
				path: ['operations'],
			});
		}
	});

const bridgeProductFileStatusPatchEventSchema = z
	.object({
		eventKind: z.literal('file.statusPatch'),
		patch: bridgeProductFileStatusPatchSchema,
		source: bridgeProductFileSourceIdentitySchema,
	})
	.strict();

const bridgeProductFileDescriptorReadyEventSchema =
	bridgeProductFileDescriptorReadyPayloadSchema.safeExtend({
		eventKind: z.literal('file.descriptorReady'),
	});

const bridgeProductFileInvalidatedEventSchema = z
	.object({
		eventKind: z.literal('file.invalidated'),
		fileId: bridgeProductIdentifierSchema.nullable(),
		path: bridgeProductDisplayPathSchema,
		reason: z.enum([
			'filesystemEvent',
			'gitStatusChanged',
			'contentChanged',
			'sourceReset',
			'unknown',
		]),
		replacementDescriptor: bridgeProductFileDescriptorReadyPayloadSchema.nullable(),
		source: bridgeProductFileSourceIdentitySchema,
	})
	.strict();

export const bridgeProductFileMetadataEventSchema = z.discriminatedUnion('eventKind', [
	bridgeProductFileSourceAcceptedEventSchema,
	bridgeProductFileTreeWindowEventSchema,
	bridgeProductFileTreeDeltaEventSchema,
	bridgeProductFileStatusPatchEventSchema,
	bridgeProductFileDescriptorReadyEventSchema,
	bridgeProductFileInvalidatedEventSchema,
]);

function bridgeProductFileSourceIdentitiesEqual(
	left: BridgeProductFileSourceIdentity,
	right: BridgeProductFileSourceIdentity,
): boolean {
	return (
		left.repoId === right.repoId &&
		left.rootRevisionToken === right.rootRevisionToken &&
		left.sourceCursor === right.sourceCursor &&
		left.sourceId === right.sourceId &&
		left.subscriptionGeneration === right.subscriptionGeneration &&
		left.worktreeId === right.worktreeId
	);
}

export type BridgeProductSubscriptionRegistry = {
	readonly 'file.metadata': {
		readonly event: z.infer<typeof bridgeProductFileMetadataEventSchema>;
		readonly options: z.infer<typeof bridgeProductFileMetadataSubscriptionOptionsSchema>;
		readonly surface: 'file';
		readonly updateOptions: z.infer<
			typeof bridgeProductFileMetadataSubscriptionUpdateOptionsSchema
		>;
	};
	readonly 'review.metadata': {
		readonly event: z.infer<typeof bridgeProductReviewMetadataEventSchema>;
		readonly options: z.infer<typeof bridgeProductReviewMetadataSubscriptionOptionsSchema>;
		readonly surface: 'review';
		readonly updateOptions: z.infer<
			typeof bridgeProductReviewMetadataSubscriptionUpdateOptionsSchema
		>;
	};
};

export type BridgeProductSubscriptionKind = keyof BridgeProductSubscriptionRegistry;
export const bridgeProductSubscriptionKindSchema = z.enum(['file.metadata', 'review.metadata']);

const bridgeProductSurfaceBySubscriptionKind = {
	'file.metadata': 'file',
	'review.metadata': 'review',
} as const satisfies {
	readonly [TSubscriptionKind in BridgeProductSubscriptionKind]: BridgeProductSubscriptionRegistry[TSubscriptionKind]['surface'];
};

export function bridgeProductSurfaceForSubscriptionKind<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
>(
	subscriptionKind: TSubscriptionKind,
): BridgeProductSubscriptionRegistry[TSubscriptionKind]['surface'] {
	return bridgeProductSurfaceBySubscriptionKind[subscriptionKind];
}

export type BridgeProductSubscriptionOptions<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> = BridgeProductRegistryValue<BridgeProductSubscriptionRegistry, TSubscriptionKind, 'options'>;
export type BridgeProductSubscriptionEvent<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> = BridgeProductRegistryValue<BridgeProductSubscriptionRegistry, TSubscriptionKind, 'event'>;
export type BridgeProductSubscriptionUpdateOptions<
	TSubscriptionKind extends BridgeProductSubscriptionKind,
> = BridgeProductRegistryValue<
	BridgeProductSubscriptionRegistry,
	TSubscriptionKind,
	'updateOptions'
>;
export type BridgeProductSubscriptionInterestState = z.infer<
	typeof bridgeProductSubscriptionInterestStateSchema
>;

export function validateBridgeProductSubscriptionInterestState(
	state: BridgeProductSubscriptionInterestState,
): BridgeProductSubscriptionInterestState {
	const preflight = preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(state);
	if (preflight.status === 'exceedsMaximum') {
		throw new Error(
			`Bridge product canonical interest state cannot exceed ${preflight.maximumCanonicalByteLength} bytes.`,
		);
	}
	return bridgeProductSubscriptionInterestStateStructuralSchema.parse(state);
}

export const bridgeProductSubscriptionOpenSchema = z.discriminatedUnion('subscriptionKind', [
	z
		.object({
			source: bridgeProductFileSourceConfigurationSchema,
			subscriptionKind: z.literal('file.metadata'),
		})
		.strict(),
	z
		.object({
			subscriptionKind: z.literal('review.metadata'),
		})
		.strict(),
]);

const bridgeProductReviewMetadataInterestAdditionSchema = z
	.object({
		itemId: bridgeProductReviewInterestIdentitySchema,
		lane: bridgeProductDemandLaneSchema,
	})
	.strict();

const bridgeProductFileMetadataInterestAdditionSchema = z
	.object({
		lane: bridgeProductDemandLaneSchema,
		path: bridgeProductDisplayPathSchema,
	})
	.strict();

export const bridgeProductReviewMetadataInterestDeltaSchema = z
	.object({
		add: z
			.array(bridgeProductReviewMetadataInterestAdditionSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT)
			.readonly(),
		removeItemIds: z
			.array(bridgeProductReviewInterestIdentitySchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT)
			.readonly(),
		subscriptionKind: z.literal('review.metadata'),
	})
	.strict()
	.superRefine((delta, context): void => {
		const addedItemIds = delta.add.map((addition) => addition.itemId);
		const removedItemIds = delta.removeItemIds;
		validateDeltaCollection({
			addedValues: addedItemIds,
			context,
			path: ['add'],
			removedPath: ['removeItemIds'],
			removedValues: removedItemIds,
		});
	});

export const bridgeProductFileMetadataInterestDeltaSchema = z
	.object({
		add: z
			.array(bridgeProductFileMetadataInterestAdditionSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT)
			.readonly(),
		addPathScope: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT)
			.readonly(),
		removePathScope: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT)
			.readonly(),
		removePaths: z
			.array(bridgeProductDisplayPathSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT)
			.readonly(),
		subscriptionKind: z.literal('file.metadata'),
	})
	.strict()
	.superRefine((delta, context): void => {
		validateDeltaCollection({
			addedValues: delta.add.map((addition) => addition.path),
			context,
			path: ['add'],
			removedPath: ['removePaths'],
			removedValues: delta.removePaths,
		});
		validateDeltaCollection({
			addedValues: delta.addPathScope,
			context,
			path: ['addPathScope'],
			removedPath: ['removePathScope'],
			removedValues: delta.removePathScope,
		});
	});

export const bridgeProductSubscriptionInterestDeltaSchema = z.discriminatedUnion(
	'subscriptionKind',
	[bridgeProductFileMetadataInterestDeltaSchema, bridgeProductReviewMetadataInterestDeltaSchema],
);

export const bridgeProductFileMetadataSubscriptionDataSchema = z
	.object({
		event: bridgeProductFileMetadataEventSchema,
		subscriptionKind: z.literal('file.metadata'),
	})
	.strict();

export const bridgeProductReviewMetadataSubscriptionDataSchema = z
	.object({
		event: bridgeProductReviewMetadataEventSchema,
		subscriptionKind: z.literal('review.metadata'),
	})
	.strict();

export const bridgeProductSubscriptionDataSchema = z.discriminatedUnion('subscriptionKind', [
	bridgeProductFileMetadataSubscriptionDataSchema,
	bridgeProductReviewMetadataSubscriptionDataSchema,
]);

export type BridgeProductSubscriptionOpenWire = z.infer<typeof bridgeProductSubscriptionOpenSchema>;
export type BridgeProductSubscriptionInterestDeltaWire = z.infer<
	typeof bridgeProductSubscriptionInterestDeltaSchema
>;
export type BridgeProductSubscriptionDataWire = z.infer<typeof bridgeProductSubscriptionDataSchema>;
export type BridgeProductSubscriptionOpenRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<
		BridgeProductSubscriptionOpenWire['subscriptionKind'],
		BridgeProductSubscriptionKind
	>
>;
export type BridgeProductSubscriptionInterestDeltaRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<
		BridgeProductSubscriptionInterestDeltaWire['subscriptionKind'],
		BridgeProductSubscriptionKind
	>
>;
export type BridgeProductSubscriptionDataRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<
		BridgeProductSubscriptionDataWire['subscriptionKind'],
		BridgeProductSubscriptionKind
	>
>;

function validateDeltaCollection(props: {
	readonly addedValues: readonly string[];
	readonly context: z.RefinementCtx;
	readonly path: readonly (number | string)[];
	readonly removedPath: readonly (number | string)[];
	readonly removedValues: readonly string[];
}): void {
	const addedIdentityKeySet = bridgeProductExactUtf8IdentitySet(props.addedValues);
	const removedIdentityKeySet = bridgeProductExactUtf8IdentitySet(props.removedValues);
	if (addedIdentityKeySet.size !== props.addedValues.length) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta additions must be unique.',
			path: [...props.path],
		});
	}
	if (removedIdentityKeySet.size !== props.removedValues.length) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta removals must be unique.',
			path: [...props.removedPath],
		});
	}
	if ([...addedIdentityKeySet].some((identityKey) => removedIdentityKeySet.has(identityKey))) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta cannot add and remove the same member.',
			path: [...props.path],
		});
	}
	if (
		props.addedValues.length + props.removedValues.length >
		BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT
	) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta exceeds its aggregate item ceiling.',
			path: [...props.path],
		});
	}
}
