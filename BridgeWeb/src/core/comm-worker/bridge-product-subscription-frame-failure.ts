import {
	bridgeProductRequestErrorCodeSchema,
	type BridgeProductRequestErrorCode,
} from './bridge-product-contract-primitives.js';

export type BridgeProductSubscriptionControlFailureCode =
	`subscription_control_${BridgeProductRequestErrorCode}`;

const subscriptionControlFailureCodes = bridgeProductRequestErrorCodeSchema.options.map(
	(code): BridgeProductSubscriptionControlFailureCode => `subscription_control_${code}`,
);

export const bridgeProductSubscriptionFrameFailureCodes = [
	...subscriptionControlFailureCodes,
	'subscription_local_schema_rejection',
	'subscription_control_http_rejection',
	'subscription_control_response_mismatch',
	'subscription_control_body_exceeded',
	'subscription_local_open_mismatch',
	'subscription_local_operation_failed',
	'subscription_post_terminal',
	'subscription_identity_mismatch',
	'subscription_sequence_mismatch',
	'subscription_acceptance_required',
	'subscription_duplicate_acceptance',
	'subscription_interest_mismatch',
	'subscription_generation_mismatch',
	'subscription_payload_invalid',
	'subscription_queue_rejected',
] as const;

export type BridgeProductSubscriptionFrameFailureCode =
	(typeof bridgeProductSubscriptionFrameFailureCodes)[number];

/** Closed, payload-free reasons shared by subscription validation and diagnostics. */
export class BridgeProductSubscriptionFrameFailure extends Error {
	constructor(
		readonly routeFailureCode: BridgeProductSubscriptionFrameFailureCode,
		message: string,
	) {
		super(message);
		this.name = 'BridgeProductSubscriptionFrameFailure';
	}
}

/** Classify local failures without exposing payload-bearing parser error text. */
export function bridgeProductSubscriptionOperationFailureCode(
	error: unknown,
): BridgeProductSubscriptionFrameFailureCode {
	if (error instanceof BridgeProductSubscriptionFrameFailure) return error.routeFailureCode;
	if (!(error instanceof Error)) return 'subscription_local_operation_failed';
	if (error.name === 'ZodError') return 'subscription_local_schema_rejection';
	if (/^Bridge product control request failed with status [0-9]+\.$/u.test(error.message))
		return 'subscription_control_http_rejection';
	if (error.message.includes('exceeds the encoded body limit'))
		return 'subscription_control_body_exceeded';
	if (error.message === 'Bridge product subscription open control and stream facts disagree.')
		return 'subscription_local_open_mismatch';
	if (error.message.includes('does not match its') || error.message.includes('did not return'))
		return 'subscription_control_response_mismatch';
	return 'subscription_local_operation_failed';
}
