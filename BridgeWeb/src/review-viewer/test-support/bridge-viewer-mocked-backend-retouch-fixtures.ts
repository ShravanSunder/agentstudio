import type { BridgeReviewDelta } from '../../foundation/review-package/bridge-review-delta.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import {
	makeBridgeViewerBrowserFixture,
	type BridgeViewerBrowserFixture,
} from './bridge-viewer-mocked-backend-fixture.js';
import * as mockedBackendSupport from './bridge-viewer-mocked-backend-support.js';

export function makeBridgeViewerContentUnavailableFixture(): BridgeViewerBrowserFixture {
	const fixture = makeBridgeViewerBrowserFixture();
	const secondItem = fixture.reviewPackage.itemsById['browser-source-b'];
	const secondHeadHandle = secondItem?.contentRoles.head ?? null;
	if (secondItem === undefined || secondHeadHandle === null) {
		throw new Error('expected content-unavailable fixture second item head handle');
	}
	const isolatedSecondHeadHandleId = `${secondHeadHandle.handleId}-failure-content-unavailable`;
	const isolatedSecondHeadHandle = {
		...secondHeadHandle,
		handleId: isolatedSecondHeadHandleId,
		cacheKey: `${secondHeadHandle.cacheKey}:failure-content-unavailable`,
		contentHash: `${secondHeadHandle.contentHash}:failure-content-unavailable`,
	};
	const isolatedSecondItem = {
		...secondItem,
		contentRoles: {
			...secondItem.contentRoles,
			head: isolatedSecondHeadHandle,
		},
		cacheKey: `${secondItem.cacheKey}|failure-content-unavailable`,
	};
	const contentByHandleId = new Map(fixture.contentByHandleId);
	const secondHeadContent = fixture.contentByHandleId.get(secondHeadHandle.handleId);
	if (secondHeadContent !== undefined) {
		contentByHandleId.set(isolatedSecondHeadHandle.handleId, secondHeadContent);
	}
	return {
		...fixture,
		contentByHandleId,
		reviewPackage: {
			...fixture.reviewPackage,
			itemsById: {
				...fixture.reviewPackage.itemsById,
				[isolatedSecondItem.itemId]: isolatedSecondItem,
			},
		},
		expected: {
			...fixture.expected,
			secondHeadHandleId: isolatedSecondHeadHandle.handleId,
		},
	};
}

export interface BridgeViewerContentRevisionFixture extends BridgeViewerBrowserFixture {
	// A follow-up snapshot that bumps only the package revision (extent-fact / path churn) without
	// touching any content identity. The content-validity gate must keep already-loaded content.
	readonly bareRevisionPackage: BridgeReviewPackage;
	// A follow-up snapshot where the initially selected file's head handle carries a fresher
	// contentHash and body. The gate must invalidate the loaded content and reload the new body.
	readonly revisedContentPackage: BridgeReviewPackage;
	readonly revisedInitialText: string;
	readonly initialHeadHandleId: string;
}

export interface BridgeViewerDescriptorRetouchFixture extends BridgeViewerBrowserFixture {
	readonly changedHashRetouchDelta: BridgeReviewDelta;
	readonly changedHeadContentHash: string;
	readonly changedHeadHandleId: string;
	readonly changedHeadText: string;
	readonly initialHeadHandleId: string;
	readonly metadataOnlyRetouchDelta: BridgeReviewDelta;
}

// Content-addressed content-validity gate proof surface: the initially selected file (Alpha) can be
// re-delivered as a benign revision bump (must keep loaded content) or with a genuinely fresher head
// contentHash (must invalidate + reload). See makeReviewItemContentResourcesKey.
export function makeBridgeViewerContentRevisionFixture(): BridgeViewerContentRevisionFixture {
	const fixture = makeBridgeViewerBrowserFixture();
	const sourceItem = fixture.reviewPackage.itemsById['browser-source-a'];
	const sourceHeadHandle = sourceItem?.contentRoles.head ?? null;
	if (sourceItem === undefined || sourceHeadHandle === null) {
		throw new Error('expected content-revision fixture source item head handle');
	}
	const revisedInitialBody = "export const selectedFile = 'alpha head REVISED';\n";
	const revisedHeadHandleId = `${sourceHeadHandle.handleId}-revised`;
	const revisedHeadHandle = {
		...sourceHeadHandle,
		handleId: revisedHeadHandleId,
		contentHash: `${sourceHeadHandle.contentHash}:revised`,
		cacheKey: `${sourceHeadHandle.cacheKey}:revised`,
	};
	const contentByHandleId = new Map(fixture.contentByHandleId);
	contentByHandleId.set(revisedHeadHandleId, revisedInitialBody);
	const revisedSourceItem = mockedBackendSupport.reviewItemWithContentSizes({
		item: {
			...sourceItem,
			itemVersion: sourceItem.itemVersion + 1,
			headContentHash: revisedHeadHandle.contentHash,
			contentRoles: { ...sourceItem.contentRoles, head: revisedHeadHandle },
			cacheKey: `${sourceItem.cacheKey}:revised`,
		},
		contentByHandleId,
	});
	const bareRevisionPackage: BridgeReviewPackage = {
		...fixture.reviewPackage,
		revision: fixture.reviewPackage.revision + 1,
	};
	const revisedContentPackage: BridgeReviewPackage = {
		...fixture.reviewPackage,
		revision: fixture.reviewPackage.revision + 2,
		itemsById: {
			...fixture.reviewPackage.itemsById,
			[revisedSourceItem.itemId]: revisedSourceItem,
		},
	};
	return {
		...fixture,
		contentByHandleId,
		bareRevisionPackage,
		revisedContentPackage,
		revisedInitialText: "export const selectedFile = 'alpha head REVISED';",
		initialHeadHandleId: sourceHeadHandle.handleId,
	};
}

export function makeBridgeViewerDescriptorRetouchFixture(): BridgeViewerDescriptorRetouchFixture {
	const fixture = makeBridgeViewerBrowserFixture();
	const sourceItemId = fixture.reviewPackage.orderedItemIds[0];
	if (sourceItemId === undefined) {
		throw new Error('expected descriptor retouch source item');
	}
	const sourceItem = fixture.reviewPackage.itemsById[sourceItemId];
	const sourceHeadHandle = sourceItem?.contentRoles.head ?? null;
	if (sourceItem === undefined || sourceHeadHandle === null) {
		throw new Error('expected descriptor retouch source item head handle');
	}
	const changedHeadText = "export const selectedFile = 'alpha head CHANGED';";
	const changedHeadBody = `${changedHeadText}\n`;
	const changedHeadContentHash = `${sourceHeadHandle.contentHash}:CHANGED`;
	const changedHeadHandleId = `${sourceHeadHandle.handleId}-changed-hash`;
	const changedHeadHandle = {
		...sourceHeadHandle,
		handleId: changedHeadHandleId,
		contentHash: changedHeadContentHash,
		cacheKey: `${sourceHeadHandle.cacheKey}:CHANGED`,
	};
	const contentByHandleId = new Map(fixture.contentByHandleId);
	contentByHandleId.set(changedHeadHandleId, changedHeadBody);
	const metadataOnlyRetouchItem = mockedBackendSupport.reviewItemWithContentSizes({
		item: {
			...sourceItem,
			itemVersion: sourceItem.itemVersion + 1,
		},
		contentByHandleId,
	});
	const changedHashRetouchItem = mockedBackendSupport.reviewItemWithContentSizes({
		item: {
			...sourceItem,
			itemVersion: sourceItem.itemVersion + 2,
			headContentHash: changedHeadContentHash,
			contentRoles: {
				...sourceItem.contentRoles,
				head: changedHeadHandle,
			},
			cacheKey: `${sourceItem.cacheKey}:CHANGED`,
		},
		contentByHandleId,
	});
	const metadataOnlyRetouchDelta: BridgeReviewDelta = {
		packageId: fixture.reviewPackage.packageId,
		reviewGeneration: fixture.reviewPackage.reviewGeneration,
		revision: fixture.reviewPackage.revision + 1,
		operations: {
			addItems: [],
			updateItems: [metadataOnlyRetouchItem],
			removeItems: [],
			moveItems: [],
			updateGroups: null,
			updateSummary: null,
			invalidateContent: [],
		},
	};
	const changedHashRetouchDelta: BridgeReviewDelta = {
		packageId: fixture.reviewPackage.packageId,
		reviewGeneration: fixture.reviewPackage.reviewGeneration,
		revision: fixture.reviewPackage.revision + 2,
		operations: {
			addItems: [],
			updateItems: [changedHashRetouchItem],
			removeItems: [],
			moveItems: [],
			updateGroups: null,
			updateSummary: null,
			invalidateContent: [sourceHeadHandle.handleId],
		},
	};
	return {
		...fixture,
		changedHashRetouchDelta,
		changedHeadContentHash,
		changedHeadHandleId,
		changedHeadText,
		contentByHandleId,
		initialHeadHandleId: sourceHeadHandle.handleId,
		metadataOnlyRetouchDelta,
	};
}
