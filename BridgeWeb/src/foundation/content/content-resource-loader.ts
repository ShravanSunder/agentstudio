import type { BridgeContentHandle } from '../review-package/bridge-review-package.js';

export interface BridgeContentResource {
	readonly handle: BridgeContentHandle;
	readonly text: string;
}

export interface BridgeContentFetch {
	(url: string, init?: RequestInit): Promise<Response>;
}

export async function loadBridgeContentResource(
	handle: BridgeContentHandle,
	fetchContent: BridgeContentFetch = fetch,
): Promise<BridgeContentResource> {
	const response = await fetchContent(handle.resourceUrl);
	if (!response.ok) {
		throw new Error(`Bridge content request failed: ${response.status}`);
	}
	return {
		handle,
		text: await response.text(),
	};
}
