export type BridgeProductRequestRoute = 'command' | 'content' | 'stream';

export type BridgeProductRequestExecutor = (
	route: BridgeProductRequestRoute,
	requestInit: RequestInit,
) => Promise<Response>;
