import {
	BridgeProductResponseSizeLimitError,
	readBridgeProductControlResponseBytes,
} from './bridge-product-command-post.js';
import { bridgeProductOperationResultAcknowledgementSchema } from './bridge-product-operation-wire-contracts.js';
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
		const parsed = bridgeProductControlResponseSchema.safeParse(
			parseBridgeProductStrictJSON(bytes),
		);
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
