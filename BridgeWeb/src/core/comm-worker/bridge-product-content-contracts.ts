import { z } from 'zod';

import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_WIRE_VERSION,
	type BridgeProductAssert,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
	bridgeProductPositiveSequenceSchema,
	type BridgeProductRegistryValue,
	bridgeProductRequestErrorCodeSchema,
	type BridgeProductRequestErrorCode,
	bridgeProductResetReasonSchema,
	type BridgeProductResetReason,
	bridgeProductSafeMessageSchema,
	bridgeProductSha256Schema,
	type BridgeProductTypeSetsEqual,
} from './bridge-product-contract-primitives.js';
import {
	bridgeProductFileSourceIdentitySchema,
	type BridgeProductFileSourceIdentity,
} from './bridge-product-file-contracts.js';
import { bridgeProductReviewContentRoleSchema } from './bridge-product-review-primitives.js';

const bridgeProductDeclaredByteLengthSchema = bridgeProductNonnegativeSequenceSchema.max(
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
);
const bridgeProductContentSequenceSchema = bridgeProductPositiveSequenceSchema.max(0xff_ff_ff_ff);

export const BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES = 512 * 1024;

export const bridgeProductReviewContentDigestSchema = z.discriminatedUnion('authority', [
	z
		.object({
			algorithm: z.literal('sha256'),
			authority: z.literal('authoritative'),
			value: bridgeProductSha256Schema,
		})
		.strict(),
	z
		.object({
			algorithm: bridgeProductOpaqueReferenceSchema,
			authority: z.literal('provisional'),
			value: bridgeProductOpaqueReferenceSchema,
		})
		.strict(),
]);

export const bridgeProductReviewContentSourceDescriptorSchema = z
	.object({
		contentDigest: bridgeProductReviewContentDigestSchema,
		contentKind: z.literal('review.content'),
		descriptorId: bridgeProductIdentifierSchema,
		encoding: z.literal('utf-8').nullable(),
		endpointId: bridgeProductIdentifierSchema,
		handleId: bridgeProductIdentifierSchema,
		isBinary: z.boolean(),
		itemId: bridgeProductIdentifierSchema,
		language: bridgeProductOpaqueReferenceSchema.nullable(),
		mimeType: bridgeProductOpaqueReferenceSchema,
		packageId: bridgeProductIdentifierSchema,
		reviewGeneration: bridgeProductNonnegativeSequenceSchema,
		role: bridgeProductReviewContentRoleSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
		wholeByteLength: bridgeProductNonnegativeSequenceSchema.nullable(),
	})
	.strict()
	.superRefine((source, context): void => {
		if (source.isBinary === (source.encoding !== null)) {
			context.addIssue({
				code: 'custom',
				message: 'Review content encoding must be UTF-8 exactly when the source is text.',
				path: ['encoding'],
			});
		}
	});

const bridgeProductReviewContentWindowSchema = z
	.object({
		kind: z.literal('byteRange'),
		maximumBytes: bridgeProductPositiveSequenceSchema.max(
			BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
		),
		startByte: bridgeProductNonnegativeSequenceSchema,
	})
	.strict();

export const bridgeProductReviewContentDescriptorSchema = z
	.object({
		...bridgeProductReviewContentSourceDescriptorSchema.shape,
		contentKind: z.literal('review.content'),
		declaredByteLength: bridgeProductDeclaredByteLengthSchema.nullable(),
		encoding: z.literal('utf-8'),
		expectedSha256: bridgeProductSha256Schema.nullable(),
		isBinary: z.literal(false),
		maximumBytes: bridgeProductPositiveSequenceSchema.max(
			BRIDGE_PRODUCT_MAXIMUM_REVIEW_CONTENT_RANGE_BYTES,
		),
		window: bridgeProductReviewContentWindowSchema,
	})
	.strict()
	.superRefine((descriptor, context): void => {
		if (
			descriptor.declaredByteLength !== null &&
			descriptor.declaredByteLength > descriptor.maximumBytes
		) {
			context.addIssue({
				code: 'custom',
				message: 'Review declared range length exceeds its maximum.',
				path: ['declaredByteLength'],
			});
		}
		if (descriptor.window.maximumBytes !== descriptor.maximumBytes) {
			context.addIssue({
				code: 'custom',
				message: 'Review content range must equal its request maximum.',
				path: ['window', 'maximumBytes'],
			});
		}
		if (
			descriptor.wholeByteLength !== null &&
			descriptor.window.startByte > descriptor.wholeByteLength
		) {
			context.addIssue({
				code: 'custom',
				message: 'Review content range cannot begin beyond the known whole-source length.',
				path: ['window', 'startByte'],
			});
		}
		if (
			descriptor.wholeByteLength !== null &&
			descriptor.declaredByteLength !== null &&
			descriptor.window.startByte + descriptor.declaredByteLength > descriptor.wholeByteLength
		) {
			context.addIssue({
				code: 'custom',
				message: 'Review declared range exceeds the known whole-source length.',
				path: ['declaredByteLength'],
			});
		}
	});

export const bridgeProductFileContentDescriptorSchema = z
	.object({
		contentKind: z.literal('file.content'),
		declaredByteLength: bridgeProductDeclaredByteLengthSchema,
		descriptorId: bridgeProductIdentifierSchema,
		encoding: z.literal('utf-8'),
		expectedSha256: bridgeProductSha256Schema,
		fileId: bridgeProductIdentifierSchema,
		maximumBytes: bridgeProductPositiveSequenceSchema.max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
		source: bridgeProductFileSourceIdentitySchema,
		window: z
			.object({
				kind: z.literal('prefix'),
				maximumBytes: bridgeProductPositiveSequenceSchema.max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
				maximumLines: bridgeProductPositiveSequenceSchema.max(10_000),
				startByte: z.literal(0),
			})
			.strict(),
	})
	.strict()
	.superRefine((descriptor, context): void => {
		if (descriptor.declaredByteLength > descriptor.maximumBytes) {
			context.addIssue({
				code: 'custom',
				message: 'File declared content length exceeds its maximum.',
				path: ['declaredByteLength'],
			});
		}
		if (descriptor.window.maximumBytes !== descriptor.maximumBytes) {
			context.addIssue({
				code: 'custom',
				message: 'File content window must equal its request maximum.',
				path: ['window', 'maximumBytes'],
			});
		}
	});

export const bridgeProductContentDescriptorSchema = z.discriminatedUnion('contentKind', [
	bridgeProductFileContentDescriptorSchema,
	bridgeProductReviewContentDescriptorSchema,
]);

export const bridgeProductFileContentIdentitySchema = z
	.object({
		contentKind: z.literal('file.content'),
		descriptorId: bridgeProductIdentifierSchema,
		fileId: bridgeProductIdentifierSchema,
		source: bridgeProductFileSourceIdentitySchema,
		window: z
			.object({
				kind: z.literal('prefix'),
				maximumBytes: bridgeProductPositiveSequenceSchema.max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
				maximumLines: bridgeProductPositiveSequenceSchema.max(10_000),
				startByte: z.literal(0),
			})
			.strict(),
	})
	.strict();

export const bridgeProductReviewContentIdentitySchema = z
	.object({
		contentDigest: bridgeProductReviewContentDigestSchema,
		contentKind: z.literal('review.content'),
		descriptorId: bridgeProductIdentifierSchema,
		endpointId: bridgeProductIdentifierSchema,
		handleId: bridgeProductIdentifierSchema,
		itemId: bridgeProductIdentifierSchema,
		packageId: bridgeProductIdentifierSchema,
		reviewGeneration: bridgeProductNonnegativeSequenceSchema,
		role: bridgeProductReviewContentRoleSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
		wholeByteLength: bridgeProductNonnegativeSequenceSchema.nullable(),
		window: bridgeProductReviewContentWindowSchema,
	})
	.strict();

export const bridgeProductContentIdentitySchema = z.discriminatedUnion('contentKind', [
	bridgeProductFileContentIdentitySchema,
	bridgeProductReviewContentIdentitySchema,
]);

export type BridgeProductFileContentDescriptor = z.infer<
	typeof bridgeProductFileContentDescriptorSchema
>;
export type BridgeProductFileContentIdentity = z.infer<
	typeof bridgeProductFileContentIdentitySchema
>;
export type BridgeProductReviewContentSourceDescriptor = z.infer<
	typeof bridgeProductReviewContentSourceDescriptorSchema
>;
export type BridgeProductReviewContentDescriptor = z.infer<
	typeof bridgeProductReviewContentDescriptorSchema
>;
export type BridgeProductReviewContentIdentity = z.infer<
	typeof bridgeProductReviewContentIdentitySchema
>;
export type { BridgeProductFileSourceIdentity };

type BridgeProductFileContentTerminal =
	| {
			readonly bytes: ArrayBuffer;
			readonly contentKind: 'file.content';
			readonly descriptorId: string;
			readonly endOfSource: boolean;
			readonly kind: 'complete';
			readonly observedSha256: string;
	  }
	| {
			readonly code: BridgeProductRequestErrorCode;
			readonly contentKind: 'file.content';
			readonly descriptorId: string;
			readonly kind: 'error';
			readonly retryable: boolean;
			readonly safeMessage: string | null;
	  }
	| {
			readonly contentKind: 'file.content';
			readonly descriptorId: string;
			readonly kind: 'reset';
			readonly reason: BridgeProductResetReason;
			readonly retryable: true;
	  };

type BridgeProductReviewContentTerminal =
	| {
			readonly bytes: ArrayBuffer;
			readonly contentKind: 'review.content';
			readonly descriptorId: string;
			readonly endOfSource: boolean;
			readonly kind: 'complete';
			readonly observedSha256: string;
	  }
	| {
			readonly code: BridgeProductRequestErrorCode;
			readonly contentKind: 'review.content';
			readonly descriptorId: string;
			readonly kind: 'error';
			readonly retryable: boolean;
			readonly safeMessage: string | null;
	  }
	| {
			readonly contentKind: 'review.content';
			readonly descriptorId: string;
			readonly kind: 'reset';
			readonly reason: BridgeProductResetReason;
			readonly retryable: true;
	  };

export type BridgeProductContentRegistry = {
	readonly 'file.content': {
		readonly descriptor: BridgeProductFileContentDescriptor;
		readonly identity: BridgeProductFileContentIdentity;
		readonly surface: 'file';
		readonly terminal: BridgeProductFileContentTerminal;
	};
	readonly 'review.content': {
		readonly descriptor: BridgeProductReviewContentDescriptor;
		readonly identity: BridgeProductReviewContentIdentity;
		readonly surface: 'review';
		readonly terminal: BridgeProductReviewContentTerminal;
	};
};

export type BridgeProductContentKind = keyof BridgeProductContentRegistry;
export type BridgeProductContentDescriptor<TContentKind extends BridgeProductContentKind> =
	BridgeProductRegistryValue<BridgeProductContentRegistry, TContentKind, 'descriptor'>;
export type BridgeProductContentIdentity<TContentKind extends BridgeProductContentKind> =
	BridgeProductRegistryValue<BridgeProductContentRegistry, TContentKind, 'identity'>;

const bridgeProductSurfaceByContentKind = {
	'file.content': 'file',
	'review.content': 'review',
} as const satisfies {
	readonly [TContentKind in BridgeProductContentKind]: BridgeProductContentRegistry[TContentKind]['surface'];
};

export function bridgeProductSurfaceForContentKind<TContentKind extends BridgeProductContentKind>(
	contentKind: TContentKind,
): BridgeProductContentRegistry[TContentKind]['surface'] {
	return bridgeProductSurfaceByContentKind[contentKind];
}

const bridgeProductContentRequestBaseShape = {
	contentRequestId: bridgeProductIdentifierSchema,
	kind: z.literal('content.open'),
	leaseId: bridgeProductIdentifierSchema,
	paneSessionId: bridgeProductIdentifierSchema,
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

export const bridgeProductContentRequestSchema = z.discriminatedUnion('contentKind', [
	z
		.object({
			...bridgeProductContentRequestBaseShape,
			contentKind: z.literal('file.content'),
			descriptor: bridgeProductFileContentDescriptorSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductContentRequestBaseShape,
			contentKind: z.literal('review.content'),
			descriptor: bridgeProductReviewContentDescriptorSchema,
		})
		.strict(),
]);

const bridgeProductContentAcceptedBodyShape = {
	contentRequestId: bridgeProductIdentifierSchema,
	identity: bridgeProductContentIdentitySchema,
	leaseId: bridgeProductIdentifierSchema,
	paneSessionId: bridgeProductIdentifierSchema,
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

export const bridgeProductContentAcceptedBodySchema = z
	.object({
		...bridgeProductContentAcceptedBodyShape,
		declaredByteLength: bridgeProductDeclaredByteLengthSchema.nullable(),
		expectedSha256: bridgeProductSha256Schema.nullable(),
		maximumBytes: bridgeProductPositiveSequenceSchema.max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
	})
	.strict()
	.superRefine((header, context): void => {
		if (header.maximumBytes !== header.identity.window.maximumBytes) {
			context.addIssue({
				code: 'custom',
				message: 'Accepted content maximum must match its identity window.',
				path: ['maximumBytes'],
			});
		}
		if (header.declaredByteLength !== null && header.declaredByteLength > header.maximumBytes) {
			context.addIssue({
				code: 'custom',
				message: 'Accepted content declaration exceeds its maximum.',
				path: ['declaredByteLength'],
			});
		}
	});

export const bridgeProductContentAcceptedHeaderSchema = z
	.object({
		...bridgeProductContentAcceptedBodyShape,
		contentSequence: z.literal(0),
		declaredByteLength: bridgeProductDeclaredByteLengthSchema.nullable(),
		expectedSha256: bridgeProductSha256Schema.nullable(),
		kind: z.literal('content.accepted'),
		maximumBytes: bridgeProductPositiveSequenceSchema.max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
	})
	.strict()
	.superRefine((header, context): void => {
		if (header.maximumBytes !== header.identity.window.maximumBytes) {
			context.addIssue({
				code: 'custom',
				message: 'Accepted content maximum must match its identity window.',
				path: ['maximumBytes'],
			});
		}
		if (header.declaredByteLength !== null && header.declaredByteLength > header.maximumBytes) {
			context.addIssue({
				code: 'custom',
				message: 'Accepted content declaration exceeds its maximum.',
				path: ['declaredByteLength'],
			});
		}
	});

export const bridgeProductContentDataHeaderSchema = z
	.object({
		contentSequence: bridgeProductContentSequenceSchema,
		kind: z.literal('content.data'),
		offsetBytes: bridgeProductNonnegativeSequenceSchema.max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
	})
	.strict();

export const bridgeProductContentEndBodySchema = z
	.object({
		endOfSource: z.boolean(),
		observedByteLength: bridgeProductNonnegativeSequenceSchema.max(
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
		),
		observedSha256: bridgeProductSha256Schema,
	})
	.strict();

export const bridgeProductContentEndHeaderSchema = bridgeProductContentEndBodySchema.safeExtend({
	contentSequence: bridgeProductContentSequenceSchema,
	kind: z.literal('content.end'),
});

export const bridgeProductContentErrorBodySchema = z
	.object({
		code: bridgeProductRequestErrorCodeSchema,
		retryable: z.boolean(),
		safeMessage: bridgeProductSafeMessageSchema.nullable(),
	})
	.strict();

export const bridgeProductContentErrorHeaderSchema = bridgeProductContentErrorBodySchema.safeExtend(
	{
		contentSequence: bridgeProductContentSequenceSchema,
		kind: z.literal('content.error'),
	},
);

export const bridgeProductContentResetBodySchema = z
	.object({
		reason: bridgeProductResetReasonSchema,
	})
	.strict();

export const bridgeProductContentResetHeaderSchema = bridgeProductContentResetBodySchema.safeExtend(
	{
		contentSequence: bridgeProductContentSequenceSchema,
		kind: z.literal('content.reset'),
	},
);

export const bridgeProductContentHeaderSchema = z.discriminatedUnion('kind', [
	bridgeProductContentAcceptedHeaderSchema,
	bridgeProductContentDataHeaderSchema,
	bridgeProductContentEndHeaderSchema,
	bridgeProductContentErrorHeaderSchema,
	bridgeProductContentResetHeaderSchema,
]);

export type BridgeProductContentRequest = z.infer<typeof bridgeProductContentRequestSchema>;
export type BridgeProductContentRequestFor<TContentKind extends BridgeProductContentKind> = Extract<
	BridgeProductContentRequest,
	{ readonly contentKind: TContentKind }
>;
export type BridgeProductContentHeader = z.infer<typeof bridgeProductContentHeaderSchema>;
export type BridgeProductContentRequestRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<BridgeProductContentRequest['contentKind'], BridgeProductContentKind>
>;
export type BridgeProductContentHeaderRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<
		z.infer<typeof bridgeProductContentAcceptedHeaderSchema>['identity']['contentKind'],
		BridgeProductContentKind
	>
>;
export type BridgeProductContentFrame = {
	readonly header: BridgeProductContentHeader;
	readonly payload: Uint8Array;
};

export type BridgeProductContentHeaderFor<TContentKind extends BridgeProductContentKind> =
	| (z.infer<typeof bridgeProductContentAcceptedHeaderSchema> & {
			readonly identity: BridgeProductContentIdentity<TContentKind>;
	  })
	| Exclude<BridgeProductContentHeader, { readonly kind: 'content.accepted' }>;
export type BridgeProductContentFrameFor<TContentKind extends BridgeProductContentKind> = {
	readonly header: BridgeProductContentHeaderFor<TContentKind>;
	readonly payload: Uint8Array;
};
export type BridgeProductContentTerminal<TContentKind extends BridgeProductContentKind> =
	BridgeProductRegistryValue<BridgeProductContentRegistry, TContentKind, 'terminal'>;

export function bridgeProductContentIdentityFromDescriptor(
	descriptor: BridgeProductFileContentDescriptor,
): BridgeProductFileContentIdentity;
export function bridgeProductContentIdentityFromDescriptor(
	descriptor: BridgeProductReviewContentDescriptor,
): BridgeProductReviewContentIdentity;
export function bridgeProductContentIdentityFromDescriptor(
	descriptor: BridgeProductFileContentDescriptor | BridgeProductReviewContentDescriptor,
): BridgeProductFileContentIdentity | BridgeProductReviewContentIdentity;
export function bridgeProductContentIdentityFromDescriptor(
	descriptor: BridgeProductFileContentDescriptor | BridgeProductReviewContentDescriptor,
): BridgeProductFileContentIdentity | BridgeProductReviewContentIdentity {
	switch (descriptor.contentKind) {
		case 'file.content':
			return {
				contentKind: descriptor.contentKind,
				descriptorId: descriptor.descriptorId,
				fileId: descriptor.fileId,
				source: descriptor.source,
				window: descriptor.window,
			};
		case 'review.content':
			return {
				contentDigest: descriptor.contentDigest,
				contentKind: descriptor.contentKind,
				descriptorId: descriptor.descriptorId,
				endpointId: descriptor.endpointId,
				handleId: descriptor.handleId,
				itemId: descriptor.itemId,
				packageId: descriptor.packageId,
				reviewGeneration: descriptor.reviewGeneration,
				role: descriptor.role,
				sourceIdentity: descriptor.sourceIdentity,
				wholeByteLength: descriptor.wholeByteLength,
				window: descriptor.window,
			};
	}
	throw new Error('Unsupported Bridge product content descriptor.');
}
