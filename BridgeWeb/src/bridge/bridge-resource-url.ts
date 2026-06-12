export interface BridgeContentResourceUrl {
	readonly handleId: string;
	readonly generation: number;
}

export function parseBridgeContentResourceUrl(
	resourceUrl: string,
): BridgeContentResourceUrl | null {
	let parsedUrl: URL;
	try {
		parsedUrl = new URL(resourceUrl);
	} catch {
		return null;
	}
	if (parsedUrl.protocol !== 'agentstudio:' || parsedUrl.hostname !== 'resource') {
		return null;
	}
	const pathSegments = parsedUrl.pathname
		.split('/')
		.filter((segment: string): boolean => segment.length > 0);
	const generation = Number(parsedUrl.searchParams.get('generation'));
	if (pathSegments.length !== 2 || pathSegments[0] !== 'content' || !Number.isInteger(generation)) {
		return null;
	}
	const handleId = pathSegments[1];
	if (handleId === undefined || handleId.length === 0 || generation < 0) {
		return null;
	}
	return { handleId, generation };
}
