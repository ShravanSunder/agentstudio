import { uuidv7 } from 'uuidv7';

import { BridgeIncrementalSha256 } from './bridge-incremental-sha256.js';

const operationIdentityEncoder = new TextEncoder();

/**
 * Mints one owner-local UUIDv7 and returns only its scrubbed wire projection.
 * The raw identity never leaves this synchronous admission boundary.
 */
export function mintBridgeOperationCorrelationId(): string {
	const operationIdentity = uuidv7();
	const digest = new BridgeIncrementalSha256();
	digest.update(operationIdentityEncoder.encode(operationIdentity));
	return digest.digestHex();
}
