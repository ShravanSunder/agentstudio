import { EventEmitter } from 'node:events';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { Readable } from 'node:stream';

import { encodeBridgeProductCapabilityHeader } from '../../src/core/comm-worker/bridge-product-session-contracts.js';
import type { BridgeProductDevCarrier } from './bridge-product-dev-carrier.js';

export interface TestProductAuthority {
	readonly capability: string;
	readonly paneSessionId: string;
	readonly workerInstanceId: string;
}

export function authorityForDelivery(
	delivery: ReturnType<BridgeProductDevCarrier['issueBootstrap']>,
): TestProductAuthority {
	return {
		capability: encodeBridgeProductCapabilityHeader(delivery.productCapability),
		paneSessionId: delivery.bootstrap.paneSessionId,
		workerInstanceId: delivery.bootstrap.workerInstanceId,
	};
}

export async function dispatchCommandToCarrier(props: {
	readonly authority: TestProductAuthority;
	readonly body: string;
	readonly carrier: BridgeProductDevCarrier;
}): Promise<{
	readonly request: ReturnType<typeof requestWithBodyProbe>;
	readonly response: TestServerResponse;
}> {
	const request = requestWithBodyProbe({
		body: props.body,
		capability: props.authority.capability,
	});
	const response = new TestServerResponse();
	await props.carrier.handleCommandRequest({
		request: request.request,
		response: response.response,
	});
	return { request, response };
}

export function requestWithBodyProbe(props: {
	readonly body: string;
	readonly capability: string;
	readonly contentType?: string | null;
}): {
	readonly bodyReadCount: () => number;
	readonly request: IncomingMessage;
} {
	let bodyReadCount = 0;
	const request = Readable.from(
		(async function* (): AsyncGenerator<Buffer> {
			bodyReadCount += 1;
			yield Buffer.from(props.body);
		})(),
	);
	Object.assign(request, {
		headers: {
			...(props.contentType === null
				? {}
				: { 'content-type': props.contentType ?? 'application/json' }),
			'x-agentstudio-bridge-product-capability': props.capability,
		},
		method: 'POST',
		url: '/command',
	});
	return {
		bodyReadCount: (): number => bodyReadCount,
		request: request as IncomingMessage,
	};
}

export class TestServerResponse extends EventEmitter {
	readonly #bodyChunks: Buffer[] = [];
	readonly #headers = new Map<string, string | number | readonly string[]>();
	destroyed = false;
	headersSent = false;
	statusCode = 200;

	get bodyText(): string {
		return Buffer.concat(this.#bodyChunks).toString('utf8');
	}

	get response(): ServerResponse {
		return this as unknown as ServerResponse;
	}

	setHeader(name: string, value: string | number | readonly string[]): this {
		this.#headers.set(name.toLowerCase(), value);
		return this;
	}

	end(chunk?: string | Uint8Array): this {
		if (chunk !== undefined) this.#bodyChunks.push(Buffer.from(chunk));
		this.headersSent = true;
		return this;
	}
}
