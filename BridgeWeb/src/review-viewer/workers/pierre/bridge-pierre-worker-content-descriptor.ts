export interface BridgePierreContentIdentity {
	readonly contentHash: string;
	readonly contentHashAlgorithm: string;
}

export function bridgePierreContentDescriptorCacheKey(props: BridgePierreContentIdentity): string {
	return ['pierre-content', props.contentHashAlgorithm, props.contentHash].join(':');
}
