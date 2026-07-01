export interface BridgeReviewFrameAuthority {
	readonly paneId: string;
	readonly streamId: string;
}

export const bridgeReviewPaneIdAttribute = 'data-bridge-review-pane-id';
export const bridgeReviewStreamIdAttribute = 'data-bridge-review-stream-id';

export function readBridgeReviewFrameAuthority(): BridgeReviewFrameAuthority | null {
	const paneId = document.documentElement.getAttribute(bridgeReviewPaneIdAttribute);
	const streamId = document.documentElement.getAttribute(bridgeReviewStreamIdAttribute);
	return paneId === null || streamId === null || paneId.length === 0 || streamId.length === 0
		? null
		: { paneId, streamId };
}

export function refreshBridgeReviewFrameAuthority(authorityRef: {
	current: BridgeReviewFrameAuthority | null;
}): BridgeReviewFrameAuthority | null {
	if (authorityRef.current !== null) {
		return authorityRef.current;
	}
	const nextAuthority = readBridgeReviewFrameAuthority();
	if (nextAuthority !== null) {
		authorityRef.current = nextAuthority;
	}
	return authorityRef.current;
}
