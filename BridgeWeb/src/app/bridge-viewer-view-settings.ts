export interface BridgeFilesViewSettings {
	readonly lineNumbers: boolean;
	readonly wordWrap: boolean;
}

export type BridgeReviewChangeIndicators = 'bars' | 'symbols' | 'none';

export type BridgeReviewDiffLayout = 'split' | 'unified';

export interface BridgeReviewViewSettings {
	readonly changeBackgrounds: boolean;
	readonly changeIndicators: BridgeReviewChangeIndicators;
	readonly diffLayout: BridgeReviewDiffLayout;
	readonly lineNumbers: boolean;
	readonly wordWrap: boolean;
}
