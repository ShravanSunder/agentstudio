import {
	BridgeProductResponseSizeLimitError,
	readBridgeProductControlResponseBytes,
} from './bridge-product-command-post.js';
import {
	bridgeProductOperationResultAckRefusedResponseSchema,
	bridgeProductOperationResultAcknowledgementSchema,
} from './bridge-product-operation-wire-contracts.js';
import { bridgeProductControlResponseSchema } from './bridge-product-session-contracts.js';
import {
	BridgeProductStrictJSONError,
	parseBridgeProductStrictJSON,
} from './bridge-product-strict-json.js';
import type { BridgeWorkerAckAttemptOutcome } from './bridge-worker-contracts.js';

export async function bridgeProductAckHTTPFailureOutcome(
	response: Response,
	acknowledgement: ReturnType<typeof bridgeProductOperationResultAcknowledgementSchema.parse>,
): Promise<BridgeWorkerAckAttemptOutcome> {
	if (response.status < 400 || response.status >= 500) {
		return { kind: 'httpStatus', code: response.status };
	}
	if (response.body === null) return { kind: 'httpStatus', code: response.status };
	try {
		const bytes = await readBridgeProductControlResponseBytes(response);
		if (bytes.byteLength === 0) return { kind: 'httpStatus', code: response.status };
		const body = parseBridgeProductStrictJSON(bytes);
		const refusal = bridgeProductOperationResultAckRefusedResponseSchema.safeParse(body);
		if (refusal.success) {
			if (
				refusal.data.requestId !== acknowledgement.requestId ||
				refusal.data.requestSequence !== acknowledgement.requestSequence ||
				refusal.data.paneSessionId !== acknowledgement.paneSessionId ||
				refusal.data.workerInstanceId !== acknowledgement.workerInstanceId ||
				refusal.data.operationId !== acknowledgement.operationId
			)
				return { kind: 'identityMismatch' };
			return { kind: 'nativeRefusal', refusalKind: refusal.data.refusalKind };
		}
		const parsed = bridgeProductControlResponseSchema.safeParse(body);
		if (!parsed.success) return { kind: 'parseFailure' };
		if (
			parsed.data.requestId !== acknowledgement.requestId ||
			parsed.data.requestSequence !== acknowledgement.requestSequence ||
			parsed.data.paneSessionId !== acknowledgement.paneSessionId ||
			parsed.data.workerInstanceId !== acknowledgement.workerInstanceId
		)
			return { kind: 'identityMismatch' };
		return parsed.data.kind === 'request.error'
			? { kind: 'nativeRefusal', refusalKind: parsed.data.code }
			: { kind: 'httpStatus', code: response.status };
	} catch (error: unknown) {
		if (error instanceof BridgeProductResponseSizeLimitError) return { kind: 'responseSizeLimit' };
		return error instanceof BridgeProductStrictJSONError
			? { kind: 'parseFailure' }
			: { kind: 'transportFailure' };
	}
}
