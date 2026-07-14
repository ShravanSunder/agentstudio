export interface BridgeContentFetch {
	(url: string, init?: RequestInit): Promise<Response>;
}
