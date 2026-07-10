import { z } from 'zod';

import type { BridgeDemandLane } from '../models/bridge-demand-models.js';
import {
	type BridgeProductAssert,
	bridgeProductDemandLaneSchema,
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
	type BridgeProductRegistryValue,
	bridgeProductUnicodeScalarUtf8ByteLength,
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
	type BridgeProductTypeSetsEqual,
} from './bridge-product-contract-primitives.js';

export type BridgeProductDemandLaneParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<z.infer<typeof bridgeProductDemandLaneSchema>, BridgeDemandLane>
>;

const bridgeProductMaximumInterestGroupCount = 64;
export const BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_ITEM_COUNT = 10_000;
export const BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT = 40_000;

const bridgeProductReviewMetadataInterestSchema = z
	.object({
		itemIds: z
			.array(bridgeProductIdentifierSchema)
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
		if (new Set(itemIds).size !== itemIds.length) {
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
		if (new Set(interestPaths).size !== interestPaths.length) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata interest paths must be unique across demand lanes.',
				path: ['interests'],
			});
		}
		if (new Set(options.pathScope).size !== options.pathScope.length) {
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
		if (new Set(interestPaths).size !== interestPaths.length) {
			context.addIssue({
				code: 'custom',
				message: 'File metadata interest paths must be unique across demand lanes.',
				path: ['interests'],
			});
		}
		if (new Set(options.pathScope).size !== options.pathScope.length) {
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

export const bridgeProductFileSourceIdentitySchema = z
	.object({
		repoId: z.uuid(),
		rootRevisionToken: bridgeProductOpaqueReferenceSchema.nullable(),
		sourceCursor: bridgeProductOpaqueReferenceSchema,
		sourceId: bridgeProductIdentifierSchema,
		subscriptionGeneration: bridgeProductNonnegativeSequenceSchema,
		worktreeId: z.uuid(),
	})
	.strict();

export const bridgeProductReviewMetadataEventSchema = z
	.object({
		eventKind: z.literal('review.sourceAccepted'),
		generation: bridgeProductNonnegativeSequenceSchema,
		packageId: bridgeProductIdentifierSchema,
		revision: bridgeProductNonnegativeSequenceSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeProductFileMetadataEventSchema = z
	.object({
		eventKind: z.literal('file.sourceAccepted'),
		source: bridgeProductFileSourceIdentitySchema,
	})
	.strict();

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

export type BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight =
	| {
			readonly canonicalByteLength: number;
			readonly status: 'accepted';
			readonly visitedTextValueCount: number;
	  }
	| {
			readonly canonicalByteLengthLowerBound: number;
			readonly maximumCanonicalByteLength: number;
			readonly status: 'exceedsMaximum';
			readonly visitedTextValueCount: number;
	  };

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

export function preflightBridgeProductSubscriptionInterestStateCanonicalEncoding(
	state: BridgeProductSubscriptionInterestState,
): BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight {
	let canonicalByteLength = state.subscriptionKind === 'file.metadata' ? 10 : 6;
	let visitedTextValueCount = 0;
	const addTextValue = (
		value: string,
		perValueOverheadBytes: number,
	): BridgeProductSubscriptionInterestStateCanonicalEncodingPreflight | null => {
		const valueByteLength = bridgeProductUnicodeScalarUtf8ByteLength(value);
		if (valueByteLength === null) {
			throw new Error('Bridge product canonical interest-state preflight requires scalar text.');
		}
		canonicalByteLength += perValueOverheadBytes + valueByteLength;
		visitedTextValueCount += 1;
		if (canonicalByteLength <= BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES) {
			return null;
		}
		return {
			canonicalByteLengthLowerBound: canonicalByteLength,
			maximumCanonicalByteLength: BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_INTEREST_STATE_BYTES,
			status: 'exceedsMaximum',
			visitedTextValueCount,
		};
	};

	if (state.subscriptionKind === 'file.metadata') {
		for (const interest of state.interests) {
			for (const path of interest.paths) {
				const exceeded = addTextValue(path, 5);
				if (exceeded !== null) return exceeded;
			}
		}
		for (const path of state.pathScope) {
			const exceeded = addTextValue(path, 4);
			if (exceeded !== null) return exceeded;
		}
	} else {
		for (const interest of state.interests) {
			for (const itemId of interest.itemIds) {
				const exceeded = addTextValue(itemId, 5);
				if (exceeded !== null) return exceeded;
			}
		}
	}

	return {
		canonicalByteLength,
		status: 'accepted',
		visitedTextValueCount,
	};
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
		itemId: bridgeProductIdentifierSchema,
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
			.array(bridgeProductIdentifierSchema)
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

export type BridgeProductFileSourceIdentity = z.infer<typeof bridgeProductFileSourceIdentitySchema>;
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

export function bridgeProductSubscriptionInterestDeltaItemCount(
	delta: BridgeProductSubscriptionInterestDeltaWire,
): number {
	switch (delta.subscriptionKind) {
		case 'file.metadata':
			return (
				delta.add.length +
				delta.removePaths.length +
				delta.addPathScope.length +
				delta.removePathScope.length
			);
		case 'review.metadata':
			return delta.add.length + delta.removeItemIds.length;
	}
	throw new Error('Unsupported Bridge product subscription interest delta.');
}

function validateDeltaCollection(props: {
	readonly addedValues: readonly string[];
	readonly context: z.RefinementCtx;
	readonly path: readonly (number | string)[];
	readonly removedPath: readonly (number | string)[];
	readonly removedValues: readonly string[];
}): void {
	const addedValueSet = new Set(props.addedValues);
	const removedValueSet = new Set(props.removedValues);
	if (addedValueSet.size !== props.addedValues.length) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta additions must be unique.',
			path: [...props.path],
		});
	}
	if (removedValueSet.size !== props.removedValues.length) {
		props.context.addIssue({
			code: 'custom',
			message: 'Bridge product subscription delta removals must be unique.',
			path: [...props.removedPath],
		});
	}
	if ([...addedValueSet].some((value) => removedValueSet.has(value))) {
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
