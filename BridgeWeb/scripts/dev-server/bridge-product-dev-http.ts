import { Buffer } from 'node:buffer';
import type { IncomingMessage, ServerResponse } from 'node:http';

import {
	BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
} from '../../src/core/comm-worker/bridge-product-contract-primitives.js';

const capabilityHeaderKey = BRIDGE_PRODUCT_CAPABILITY_HEADER_NAME.toLowerCase();
const capabilityPattern = /^[A-Za-z0-9_-]{43}$/u;

export class BridgeProductDevRequestBodyTooLargeError extends Error {}

export interface BridgeProductDevWritableResponse {
	readonly destroyed: boolean;
	end(): void;
	off(eventName: 'close' | 'drain', listener: () => void): this;
	once(eventName: 'close' | 'drain', listener: () => void): this;
	write(bytes: Uint8Array): boolean;
}

export function bridgeProductDevCapabilityFromRequest(request: IncomingMessage): string | null {
	const value = request.headers[capabilityHeaderKey];
	if (typeof value !== 'string' || !capabilityPattern.test(value)) return null;
	const decoded = Buffer.from(value.replaceAll('-', '+').replaceAll('_', '/'), 'base64');
	return decoded.byteLength === 32 ? value : null;
}

export async function readBridgeProductDevBoundedRequestBody(
	request: IncomingMessage,
): Promise<Uint8Array> {
	const chunks: Buffer[] = [];
	let byteLength = 0;
	for await (const rawChunk of request) {
		const chunk = Buffer.isBuffer(rawChunk) ? rawChunk : Buffer.from(rawChunk);
		byteLength += chunk.byteLength;
		if (byteLength > BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES) {
			throw new BridgeProductDevRequestBodyTooLargeError();
		}
		chunks.push(chunk);
	}
	return Buffer.concat(chunks, byteLength);
}

export function requireBridgeProductDevPost(props: {
	readonly request: IncomingMessage;
	readonly response: ServerResponse;
}): boolean {
	if (props.request.method === 'POST') return true;
	writeBridgeProductDevError(props.response, 405, 'Method Not Allowed');
	return false;
}

export async function writeBridgeProductDevResponseChunk(
	response: BridgeProductDevWritableResponse,
	bytes: Uint8Array,
): Promise<void> {
	if (response.destroyed) throw new Error('Bridge product dev response was aborted.');
	if (response.write(bytes)) return;
	await new Promise<void>((resolve, reject): void => {
		const cleanup = (): void => {
			response.off('close', handleClose);
			response.off('drain', handleDrain);
		};
		const handleClose = (): void => {
			cleanup();
			reject(new Error('Bridge product dev response closed during backpressure.'));
		};
		const handleDrain = (): void => {
			cleanup();
			resolve();
		};
		response.once('close', handleClose);
		response.once('drain', handleDrain);
	});
}

export function encodeBridgeProductDevJSON(value: unknown): Uint8Array {
	return new TextEncoder().encode(JSON.stringify(value));
}

export function writeBridgeProductDevJSONBytes(response: ServerResponse, bytes: Uint8Array): void {
	response.statusCode = 200;
	response.setHeader('Content-Type', 'application/json; charset=utf-8');
	response.end(bytes);
}

export function writeBridgeProductDevError(
	response: ServerResponse,
	statusCode: number,
	message: string,
): void {
	if (response.headersSent) return;
	response.statusCode = statusCode;
	response.setHeader('Content-Type', 'text/plain; charset=utf-8');
	response.end(message);
}

export function bridgeProductDevRequestFailureStatus(error: unknown): number {
	return error instanceof BridgeProductDevRequestBodyTooLargeError ? 413 : 400;
}

export function bridgeProductDevSafeErrorMessage(error: unknown): string {
	return error instanceof BridgeProductDevRequestBodyTooLargeError
		? 'Payload Too Large'
		: error instanceof Error
			? error.message
			: 'Invalid Bridge product request';
}
