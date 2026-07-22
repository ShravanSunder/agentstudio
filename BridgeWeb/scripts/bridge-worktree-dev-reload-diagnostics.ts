export function parseBridgeWorktreeDevReloadIntegerList(props: {
	readonly label: string;
	readonly text: string;
}): readonly number[] {
	if (props.text.length === 0) {
		return [];
	}
	if (!/^\d+(,\d+)*$/u.test(props.text)) {
		throw new Error(
			`Expected strict nonnegative integer ${props.label} list, got ${JSON.stringify(props.text)}`,
		);
	}
	return props.text
		.split(',')
		.map((token) => parseBridgeWorktreeDevReloadIntegerToken({ label: props.label, token }));
}

export function parseBridgeWorktreeDevReloadIntegerToken(props: {
	readonly label: string;
	readonly token: string;
}): number {
	if (!/^\d+$/u.test(props.token)) {
		throw new Error(
			`Expected strict nonnegative integer ${props.label} token, got ${JSON.stringify(
				props.token,
			)}`,
		);
	}
	const value = Number(props.token);
	if (!Number.isSafeInteger(value)) {
		throw new Error(
			`Expected safe integer ${props.label} token, got ${JSON.stringify(props.token)}`,
		);
	}
	return value;
}

export function parseBridgeWorktreeDevReloadStringList(text: string): readonly string[] {
	return text.length === 0 ? [] : text.split(',').filter((token) => token.length > 0);
}

export function bridgeWorktreeDevFileContentRouteUsesOrigin(props: {
	readonly expectedOrigin: string;
	readonly url: string;
}): boolean {
	const parsedUrl = parseBridgeWorktreeDevUrl(props.url);
	return (
		parsedUrl !== null &&
		parsedUrl.origin === props.expectedOrigin &&
		parsedUrl.pathname === '/__bridge-product/content'
	);
}

export interface BridgeWorktreeDevFileContentRouteRequest {
	readonly contentRequestId: string;
	readonly descriptorId: string;
	readonly leaseId: string;
	readonly url: string;
}

export function parseBridgeWorktreeDevFileContentRouteRequest(props: {
	readonly expectedOrigin: string;
	readonly method: string;
	readonly postData: string | null;
	readonly url: string;
}): BridgeWorktreeDevFileContentRouteRequest | null {
	if (
		props.method !== 'POST' ||
		props.postData === null ||
		!bridgeWorktreeDevFileContentRouteUsesOrigin(props)
	) {
		return null;
	}
	let requestBody: unknown;
	try {
		requestBody = JSON.parse(props.postData) as unknown;
	} catch {
		return null;
	}
	const parsedRequest = bridgeProductContentRequestSchema.safeParse(requestBody);
	if (!parsedRequest.success || parsedRequest.data.contentKind !== 'file.content') return null;
	return {
		contentRequestId: parsedRequest.data.contentRequestId,
		descriptorId: parsedRequest.data.descriptor.descriptorId,
		leaseId: parsedRequest.data.leaseId,
		url: props.url,
	};
}

export function bridgeWorktreeDevFileContentRouteMatchesDescriptor(props: {
	readonly expectedDescriptorId: string;
	readonly expectedOrigin: string;
	readonly method: string;
	readonly postData: string | null;
	readonly url: string;
}): boolean {
	return (
		parseBridgeWorktreeDevFileContentRouteRequest(props)?.descriptorId ===
		props.expectedDescriptorId
	);
}

function parseBridgeWorktreeDevUrl(url: string): URL | null {
	try {
		return new URL(url);
	} catch {
		return null;
	}
}
import { bridgeProductContentRequestSchema } from '../src/core/comm-worker/bridge-product-content-contracts.js';
