import { z } from 'zod';

import { bridgeWorkerAnnotationProjectionSnapshotSchema } from './bridge-comm-worker-annotation-projection-decoder.js';
import { bridgeProductWorktreeAnnotationOperationSchema } from './bridge-product-call-contracts.js';
import { bridgeProductIdentifierSchema } from './bridge-product-contract-primitives.js';
import { bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema } from './bridge-product-worktree-annotation-contracts.js';
import {
	bridgeProductAnnotationOutputContentDescriptorSchema,
	bridgeProductWorktreeAnnotationOutputInspectRequestSchema,
} from './bridge-product-worktree-annotation-output-contracts.js';
import {
	bridgeWorkerInteractionSurfaceSchema,
	bridgeWorkerMainToServerBaseSchema,
	bridgeWorkerRequestIdSchema,
	bridgeWorkerServerToMainBaseSchema,
} from './bridge-worker-wire-base-contracts.js';

export const bridgeWorkerAnnotationCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('annotationCommand'),
		operation: bridgeProductWorktreeAnnotationOperationSchema,
		surface: bridgeWorkerInteractionSurfaceSchema,
	})
	.strict();

export const bridgeWorkerAnnotationOutputInspectCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		attemptId: bridgeProductWorktreeAnnotationOutputInspectRequestSchema.shape.attemptId,
		command: z.literal('annotationOutputInspect'),
		surface: bridgeWorkerInteractionSurfaceSchema,
	})
	.strict();

export const bridgeWorkerAnnotationProjectionRetryCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('annotationProjectionRetry'),
		surface: bridgeWorkerInteractionSurfaceSchema,
	})
	.strict();

export const bridgeWorkerAnnotationCommandAcceptedEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('annotationCommandAccepted'),
		outcome: bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema.optional(),
		productRequestId: bridgeProductIdentifierSchema,
		requestId: bridgeWorkerRequestIdSchema,
		surface: bridgeWorkerInteractionSurfaceSchema,
	})
	.strict();

export const bridgeWorkerAnnotationProjectionConvergenceEventSchema =
	bridgeWorkerServerToMainBaseSchema
		.extend({
			kind: z.literal('annotationProjectionConvergence'),
			state: z.discriminatedUnion('kind', [
				z.object({ kind: z.literal('refreshing') }).strict(),
				z.object({ kind: z.literal('unavailable'), retryable: z.boolean() }).strict(),
				z
					.object({
						kind: z.literal('ready'),
						snapshot: bridgeWorkerAnnotationProjectionSnapshotSchema,
					})
					.strict(),
			]),
			surface: bridgeWorkerInteractionSurfaceSchema,
		})
		.strict();

const bridgeWorkerArrayBufferSchema = z.custom<ArrayBuffer>(
	(value): value is ArrayBuffer => value instanceof ArrayBuffer,
	'Annotation output exact bytes must be an ArrayBuffer.',
);

export const bridgeWorkerAnnotationOutputInspectionEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		descriptor: bridgeProductAnnotationOutputContentDescriptorSchema,
		exactBytes: bridgeWorkerArrayBufferSchema,
		kind: z.literal('annotationOutputInspection'),
		requestId: bridgeWorkerRequestIdSchema,
		surface: bridgeWorkerInteractionSurfaceSchema,
	})
	.strict()
	.superRefine((event, context): void => {
		const expectedProductSurface = event.surface === 'fileView' ? 'file' : 'review';
		if (event.descriptor.surface !== expectedProductSurface) {
			context.addIssue({
				code: 'custom',
				message: 'Annotation output inspection descriptor must match its worker surface.',
				path: ['descriptor', 'surface'],
			});
		}
		if (event.exactBytes.byteLength !== event.descriptor.declaredByteLength) {
			context.addIssue({
				code: 'custom',
				message: 'Annotation output inspection bytes must match the descriptor length.',
				path: ['exactBytes'],
			});
		}
		const transferDescriptor = event.transferDescriptors[0];
		if (
			event.transferDescriptors.length !== 1 ||
			transferDescriptor?.messageKind !== event.kind ||
			transferDescriptor.mode !== 'transfer' ||
			transferDescriptor.byteLength !== event.exactBytes.byteLength ||
			transferDescriptor.fieldPath.length !== 1 ||
			transferDescriptor.fieldPath[0] !== 'exactBytes'
		) {
			context.addIssue({
				code: 'custom',
				message: 'Annotation output inspection must transfer only its declared exact bytes.',
				path: ['transferDescriptors'],
			});
		}
	});

export type BridgeWorkerAnnotationCommand = z.infer<typeof bridgeWorkerAnnotationCommandSchema>;
export type BridgeWorkerAnnotationOutputInspectCommand = z.infer<
	typeof bridgeWorkerAnnotationOutputInspectCommandSchema
>;
export type BridgeWorkerAnnotationProjectionRetryCommand = z.infer<
	typeof bridgeWorkerAnnotationProjectionRetryCommandSchema
>;
export type BridgeWorkerAnnotationOutputInspectionEvent = z.infer<
	typeof bridgeWorkerAnnotationOutputInspectionEventSchema
>;
export type BridgeWorkerAnnotationCommandAcceptedEvent = z.infer<
	typeof bridgeWorkerAnnotationCommandAcceptedEventSchema
>;
export type BridgeWorkerAnnotationProjectionConvergenceEvent = z.infer<
	typeof bridgeWorkerAnnotationProjectionConvergenceEventSchema
>;
