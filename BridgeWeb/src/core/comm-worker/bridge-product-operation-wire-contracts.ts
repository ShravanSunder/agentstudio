import { z } from 'zod';

import {
	BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_SEQUENCE,
	BRIDGE_PRODUCT_WIRE_VERSION,
	bridgeProductIdentifierSchema,
	bridgeProductPositiveSequenceSchema,
	bridgeProductRequestErrorCodeSchema,
} from './bridge-product-contract-primitives.js';

const controlCorrelationShape = {
	paneSessionId: bridgeProductIdentifierSchema,
	requestId: bridgeProductIdentifierSchema,
	requestSequence: bridgeProductPositiveSequenceSchema.max(
		BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_SEQUENCE,
	),
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

export const bridgeProductOperationWaitKindSchema = z.enum(['ordinary', 'human']);
export const bridgeProductOperationSettlementSchema = z.enum([
	'succeeded',
	'refused',
	'failed',
	'outcomeUnknown',
	'cancelled',
]);

/** A sequenced control reply confirms admission, not the effect's result. */
export const bridgeProductOperationAdmittedResponseSchema = z
	.object({
		...controlCorrelationShape,
		kind: z.literal('operation.admitted'),
		operationId: bridgeProductIdentifierSchema,
		waitKind: bridgeProductOperationWaitKindSchema,
	})
	.strict();

/** Result reads are outside the sequenced admission chain. */
export const bridgeProductOperationResultRequestSchema = z
	.object({
		kind: z.literal('operation.result'),
		operationId: bridgeProductIdentifierSchema,
		paneSessionId: bridgeProductIdentifierSchema,
		wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
		workerInstanceId: bridgeProductIdentifierSchema,
	})
	.strict();

const presentResultSchema = z.custom<unknown>((value): boolean => value !== undefined);

export const bridgeProductOperationResultResponseSchema = z
	.object({
		failureCode: bridgeProductRequestErrorCodeSchema.nullable(),
		kind: z.literal('operation.result'),
		operationId: bridgeProductIdentifierSchema,
		outcome: bridgeProductOperationSettlementSchema,
		result: presentResultSchema,
	})
	.strict()
	.superRefine((response, context): void => {
		if (response.outcome !== 'succeeded' && response.result !== null) {
			context.addIssue({
				code: 'custom',
				message: 'A non-successful operation cannot carry a result.',
			});
		}
		if (
			response.outcome !== 'refused' &&
			response.outcome !== 'failed' &&
			response.failureCode !== null
		) {
			context.addIssue({
				code: 'custom',
				message: 'Only a refused or failed operation may carry a failure code.',
			});
		}
	});

/** The acknowledgement is an escape control and reserves no result slot. */
export const bridgeProductOperationResultAcknowledgementSchema = z
	.object({
		...controlCorrelationShape,
		kind: z.literal('operation.resultAcknowledgement'),
		operationId: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeProductOperationResultAcknowledgedResponseSchema = z
	.object({
		...controlCorrelationShape,
		kind: z.literal('operation.resultAcknowledged'),
		operationId: bridgeProductIdentifierSchema,
	})
	.strict();

export type BridgeProductOperationAdmittedResponse = z.infer<
	typeof bridgeProductOperationAdmittedResponseSchema
>;
export type BridgeProductOperationResultRequest = z.infer<
	typeof bridgeProductOperationResultRequestSchema
>;
export type BridgeProductOperationResultResponse = z.infer<
	typeof bridgeProductOperationResultResponseSchema
>;
export type BridgeProductOperationResultAcknowledgement = z.infer<
	typeof bridgeProductOperationResultAcknowledgementSchema
>;
export type BridgeProductOperationResultAcknowledgedResponse = z.infer<
	typeof bridgeProductOperationResultAcknowledgedResponseSchema
>;
