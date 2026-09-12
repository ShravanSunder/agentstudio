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

const bridgeWorkerReviewAffectedStableFileIdentitiesSchema = z
	.array(bridgeProductIdentifierSchema)
	.max(BRIDGE_WORKER_REVIEW_AFFECTED_STABLE_FILE_IDENTITY_LIMIT)
	.readonly()
	.superRefine((identities, context): void => {
		if (new Set(identities).size === identities.length) return;
		context.addIssue({
			code: 'custom',
			message: 'Affected stable file identities must be unique.',
		});
	});

export const bridgeWorkerReviewCandidateStartDispositionSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('replacement') }).strict(),
	z
		.object({
			affectedStableFileIdentities: bridgeWorkerReviewAffectedStableFileIdentitiesSchema,
			kind: z.literal('sameSource'),
			presentationClass: bridgeWorkerReviewPreDeliveryPresentationClassSchema,
		})
		.strict()
		.superRefine((disposition, context): void => {
			if (
				disposition.presentationClass.kind === 'promoted' &&
				disposition.presentationClass.reason === 'unknown' &&
				disposition.affectedStableFileIdentities.length !== 0
			) {
				context.addIssue({
					code: 'custom',
					message: 'Unknown Review affectedness must remain symbolic.',
					path: ['affectedStableFileIdentities'],
				});
			}
		}),
]);

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
	})
	.strict();

export const bridgeWorkerReviewCandidateStartedEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		...bridgeWorkerReviewPublicationIdentitySchema.shape,
		disposition: bridgeWorkerReviewCandidateStartDispositionSchema,
		epoch: bridgeWorkerEpochSchema,
		kind: z.literal('reviewCandidateStarted'),
		sequence: bridgeWorkerSequenceSchema,
		surface: z.literal('review'),
	})
	.strict();

export const bridgeWorkerReviewCandidateFailedEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		...bridgeWorkerReviewPublicationIdentitySchema.shape,
		epoch: bridgeWorkerEpochSchema,
		kind: z.literal('reviewCandidateFailed'),
		retryable: z.boolean(),
		sequence: bridgeWorkerSequenceSchema,
		surface: z.literal('review'),
	})
	.strict();

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
export type BridgeWorkerReviewCandidateStartDisposition = z.infer<
	typeof bridgeWorkerReviewCandidateStartDispositionSchema
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
export type BridgeWorkerReviewCandidateStartedEvent = z.infer<
	typeof bridgeWorkerReviewCandidateStartedEventSchema
>;
export type BridgeWorkerReviewCandidateFailedEvent = z.infer<
	typeof bridgeWorkerReviewCandidateFailedEventSchema
>;
export type BridgeWorkerReviewPublicationInstallAdmissionEvent = z.infer<
	typeof bridgeWorkerReviewPublicationInstallAdmissionEventSchema
>;
