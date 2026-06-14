import type { BridgeContentHandle } from '../review-package/bridge-review-package.js';

export interface CachedReviewContent {
	readonly handle: BridgeContentHandle;
	readonly text: string;
}

export class ReviewContentCache {
	private readonly maxEntries: number;
	private readonly contentByHandleId = new Map<string, CachedReviewContent>();

	constructor(maxEntries: number) {
		this.maxEntries = Math.max(1, maxEntries);
	}

	get(handleId: string): CachedReviewContent | undefined {
		const value = this.contentByHandleId.get(handleId);
		if (value === undefined) {
			return undefined;
		}
		this.contentByHandleId.delete(handleId);
		this.contentByHandleId.set(handleId, value);
		return value;
	}

	set(content: CachedReviewContent): void {
		this.contentByHandleId.delete(content.handle.handleId);
		this.contentByHandleId.set(content.handle.handleId, content);
		while (this.contentByHandleId.size > this.maxEntries) {
			const oldestHandleId = this.contentByHandleId.keys().next().value;
			if (typeof oldestHandleId !== 'string') {
				return;
			}
			this.contentByHandleId.delete(oldestHandleId);
		}
	}

	clear(): void {
		this.contentByHandleId.clear();
	}
}
