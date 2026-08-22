import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
} from './bridge-product-contract-primitives.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT,
	bridgeProductReviewPreDeliveryPresentationClassSchema,
} from './bridge-product-review-metadata-contracts.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';
import {
	bridgeWorkerEpochSchema,
	bridgeWorkerMainToServerBaseSchema,
	bridgeWorkerRequestIdSchema,
	bridgeWorkerSequenceSchema,
	bridgeWorkerServerToMainBaseSchema,
} from './bridge-worker-wire-base-contracts.js';

export const BRIDGE_WORKER_REVIEW_AFFECTED_STABLE_FILE_IDENTITY_LIMIT =
	BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT;

export const bridgeWorkerReviewPreDeliveryPresentationClassSchema =
	bridgeProductReviewPreDeliveryPresentationClassSchema;

export const bridgeWorkerReviewPublicationIdentitySchema = z
	.object({
		packageId: bridgeProductIdentifierSchema,
		publicationId: bridgeProductReviewPublicationIdSchema,
		reviewGeneration: bridgeProductNonnegativeSequenceSchema,
		revision: bridgeProductNonnegativeSequenceSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeWorkerReviewPublicationInstallAdmitCommandSchema =
	bridgeWorkerMainToServerBaseSchema
		.extend({
			command: z.literal('reviewPublicationInstallAdmit'),
			expectedDisplayedPublicationId: bridgeProductReviewPublicationIdSchema.nullable(),
			candidatePublicationId: bridgeProductReviewPublicationIdSchema,
		})
		.strict();

export const bridgeWorkerReviewPublicationInstalledCommandSchema =
	bridgeWorkerMainToServerBaseSchema
		.extend({
			command: z.literal('reviewPublicationInstalled'),
			packageId: bridgeProductIdentifierSchema,
			publicationId: bridgeProductReviewPublicationIdSchema,
			reviewGeneration: bridgeProductNonnegativeSequenceSchema,
			revision: bridgeProductNonnegativeSequenceSchema,
			sourceIdentity: bridgeProductIdentifierSchema,
		})
		.strict();

export const bridgeWorkerReviewCandidateReadyEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('reviewCandidateReady'),
		surface: z.literal('review'),
		epoch: bridgeWorkerEpochSchema,
		sequence: bridgeWorkerSequenceSchema,
		publicationId: bridgeProductReviewPublicationIdSchema,
		packageId: bridgeProductIdentifierSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
		reviewGeneration: bridgeProductNonnegativeSequenceSchema,
		revision: bridgeProductNonnegativeSequenceSchema,
		preDeliveryPresentationClass: bridgeWorkerReviewPreDeliveryPresentationClassSchema,
		affectedStableFileIdentities: z
			.array(bridgeProductIdentifierSchema)
			.max(BRIDGE_WORKER_REVIEW_AFFECTED_STABLE_FILE_IDENTITY_LIMIT)
			.readonly(),
	})
	.strict()
	.superRefine((event, context): void => {
		if (
			new Set(event.affectedStableFileIdentities).size !== event.affectedStableFileIdentities.length
		) {
			context.addIssue({
				code: 'custom',
				message: 'Affected stable file identities must be unique.',
				path: ['affectedStableFileIdentities'],
			});
		}
	});

export const bridgeWorkerReviewPublicationInstallAdmissionEventSchema =
	bridgeWorkerServerToMainBaseSchema
		.extend({
			kind: z.literal('reviewPublicationInstallAdmission'),
			requestId: bridgeWorkerRequestIdSchema,
			candidatePublicationId: bridgeProductReviewPublicationIdSchema,
			status: z.enum(['admitted', 'rejected']),
		})
		.strict();

export type BridgeWorkerReviewPreDeliveryPresentationClass = z.infer<
	typeof bridgeWorkerReviewPreDeliveryPresentationClassSchema
>;
export type BridgeWorkerReviewPublicationIdentity = z.infer<
	typeof bridgeWorkerReviewPublicationIdentitySchema
>;
export type BridgeWorkerReviewPublicationInstallAdmitCommand = z.infer<
	typeof bridgeWorkerReviewPublicationInstallAdmitCommandSchema
>;
export type BridgeWorkerReviewPublicationInstalledCommand = z.infer<
	typeof bridgeWorkerReviewPublicationInstalledCommandSchema
>;
export type BridgeWorkerReviewCandidateReadyEvent = z.infer<
	typeof bridgeWorkerReviewCandidateReadyEventSchema
>;
export type BridgeWorkerReviewPublicationInstallAdmissionEvent = z.infer<
	typeof bridgeWorkerReviewPublicationInstallAdmissionEventSchema
>;
