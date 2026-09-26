import type { Page, Response } from 'playwright';

import {
	bridgeProductAdmissionResponseSchema,
	bridgeProductOperationResultResponseSchema,
} from '../../src/core/comm-worker/bridge-product-operation-wire-contracts.js';

export interface SettledProductCallResponse {
	readonly operationId: string;
	readonly requestSequence: number;
	readonly response: Response;
	readonly result: unknown;
}

/** Installs before the user action and correlates the admission with its result. */
export function waitForProductCallSettlement(
	page: Page,
	matchesCall: (response: Response) => boolean | Promise<boolean>,
	signal?: AbortSignal,
): Promise<SettledProductCallResponse> {
	return new Promise<SettledProductCallResponse>((resolve, reject): void => {
		let admission: { readonly operationId: string; readonly requestSequence: number } | null = null;
		const resultsByOperationId = new Map<
			string,
			{
				readonly parsed: ReturnType<typeof bridgeProductOperationResultResponseSchema.parse>;
				readonly response: Response;
			}
		>();
		let finished = false;
		const cleanup = (): void => {
			page.off('response', onResponse);
			page.off('close', onClose);
			signal?.removeEventListener('abort', onAbort);
		};
		const fail = (error: unknown): void => {
			if (finished) return;
			finished = true;
			cleanup();
			reject(error);
		};
		const finishIfReady = (): void => {
			if (finished || admission === null) return;
			const settlement = resultsByOperationId.get(admission.operationId);
			if (settlement === undefined) return;
			finished = true;
			cleanup();
			if (settlement.parsed.outcome !== 'succeeded') {
				reject(new Error(`Product call settled as ${settlement.parsed.outcome}.`));
				return;
			}
			resolve({
				operationId: admission.operationId,
				requestSequence: admission.requestSequence,
				response: settlement.response,
				result: settlement.parsed.result,
			});
		};
		const inspect = async (response: Response): Promise<void> => {
			const request = response.request();
			if (
				request.method() !== 'POST' ||
				new URL(request.url()).pathname !== '/__bridge-product/command'
			)
				return;
			const requestBody: unknown = request.postDataJSON();
			if (admission === null && (await matchesCall(response))) {
				const parsed = bridgeProductAdmissionResponseSchema.parse(await response.json());
				if (parsed.kind !== 'operation.admitted') {
					throw new Error(`Product call admission was refused with ${parsed.code}.`);
				}
				admission = {
					operationId: parsed.operationId,
					requestSequence: parsed.requestSequence,
				};
				finishIfReady();
				return;
			}
			if (!isRecord(requestBody) || requestBody['kind'] !== 'operation.result') return;
			const parsed = bridgeProductOperationResultResponseSchema.parse(await response.json());
			if (parsed.operationId !== requestBody['operationId']) {
				throw new Error('Product result response does not match its request.');
			}
			resultsByOperationId.set(parsed.operationId, { parsed, response });
			finishIfReady();
		};
		const onResponse = (response: Response): void => {
			void inspect(response).catch(fail);
		};
		const onClose = (): void => fail(new Error('Page closed before product call settlement.'));
		const onAbort = (): void =>
			fail(signal?.reason ?? new Error('Product call observation cancelled.'));
		page.on('response', onResponse);
		page.on('close', onClose);
		if (signal?.aborted) onAbort();
		else signal?.addEventListener('abort', onAbort, { once: true });
	});
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
