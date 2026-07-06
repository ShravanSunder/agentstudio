import { describe, expect, test } from 'vitest';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import {
	makeBridgeContentHandle,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import {
	resolveBridgeMarkdownPreviewDecision,
	resolveBridgeMarkdownPreviewDecisionFromCodeViewItem,
} from './bridge-markdown-render-mode.js';

describe('bridge markdown render mode', () => {
	test('previews one-sided added markdown with a valid Bridge content resource URL', () => {
		const reviewPackage = makePackageWithItem(makeAddedMarkdownItem());
		const selectedItem = reviewPackage.itemsById['item-plan'];
		const head = selectedItem?.contentRoles.head;
		if (selectedItem === undefined || head === undefined || head === null) {
			throw new Error('expected markdown head handle');
		}

		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: selectedItem.itemId,
			resources: {
				head: makeContentResource(head, '# Plan\n\n```ts\nconst value = 1;\n```'),
			},
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				itemId: 'item-plan',
				role: 'head',
				sourcePath: 'docs/plans/bridge-plan.md',
				contentCacheKey: 'item-plan:head',
				contentHash: 'sha256:item-plan:head',
			},
		});
	});

	test('previews the head side of two-sided markdown diffs', () => {
		const modifiedMarkdownItem = makeAddedMarkdownItem({
			basePath: 'docs/plans/bridge-plan.md',
			changeKind: 'modified',
			contentRoles: {
				base: makeMarkdownHandle('item-plan', 'base'),
				head: makeMarkdownHandle('item-plan', 'head'),
				diff: null,
				file: null,
			},
		});
		const reviewPackage = makePackageWithItem(modifiedMarkdownItem);
		const base = modifiedMarkdownItem.contentRoles.base;
		const head = modifiedMarkdownItem.contentRoles.head;
		if (base === undefined || base === null || head === undefined || head === null) {
			throw new Error('expected markdown diff handles');
		}

		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: modifiedMarkdownItem.itemId,
			resources: {
				base: makeContentResource(base, '# Before'),
				head: makeContentResource(head, '# After'),
			},
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				itemId: 'item-plan',
				role: 'head',
				markdownText: '# After',
			},
		});
	});

	test('previews partially available modified markdown diffs from the loaded side', () => {
		const modifiedMarkdownItem = makeAddedMarkdownItem({
			basePath: 'docs/plans/bridge-plan.md',
			changeKind: 'modified',
			contentRoles: {
				base: makeMarkdownHandle('item-plan', 'base'),
				head: makeMarkdownHandle('item-plan', 'head'),
				diff: null,
				file: null,
			},
		});
		const reviewPackage = makePackageWithItem(modifiedMarkdownItem);
		const head = modifiedMarkdownItem.contentRoles.head;
		if (head === undefined || head === null) {
			throw new Error('expected markdown head handle');
		}

		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: modifiedMarkdownItem.itemId,
			resources: { head: makeContentResource(head, '# After') },
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				itemId: 'item-plan',
				role: 'head',
				markdownText: '# After',
			},
		});
	});

	test('uses the base path when a renamed markdown preview is loaded from base content', () => {
		const renamedMarkdownItem = makeAddedMarkdownItem({
			basePath: 'docs/plans/old-bridge-plan.md',
			headPath: 'docs/plans/new-bridge-plan.md',
			changeKind: 'renamed',
			contentRoles: {
				base: makeMarkdownHandle('item-plan', 'base'),
				head: makeMarkdownHandle('item-plan', 'head'),
				diff: null,
				file: null,
			},
		});
		const reviewPackage = makePackageWithItem(renamedMarkdownItem);
		const base = renamedMarkdownItem.contentRoles.base;
		if (base === undefined || base === null) {
			throw new Error('expected markdown base handle');
		}

		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: renamedMarkdownItem.itemId,
			resources: { base: makeContentResource(base, '# Before rename') },
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				itemId: 'item-plan',
				role: 'base',
				sourcePath: 'docs/plans/old-bridge-plan.md',
				markdownText: '# Before rename',
			},
		});
	});

	test('previews file markdown content', () => {
		const fileHandle = makeMarkdownHandle('item-plan', 'head');
		const fileMarkdownItem = makeAddedMarkdownItem({
			itemKind: 'file',
			changeKind: 'modified',
			basePath: 'docs/plans/bridge-plan.md',
			contentRoles: {
				base: null,
				head: null,
				diff: null,
				file: fileHandle,
			},
			cacheKey: fileHandle.cacheKey,
		});
		const reviewPackage = makePackageWithItem(fileMarkdownItem);

		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: fileMarkdownItem.itemId,
			resources: { file: makeContentResource(fileHandle, '# File plan') },
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				role: 'head',
				markdownText: '# File plan',
			},
		});
	});

	test('falls back when the selected content handle URL is malformed', () => {
		const item = makeAddedMarkdownItem({
			contentRoles: {
				base: null,
				head: {
					...makeMarkdownHandle('item-plan', 'head'),
					resourceUrl: 'agentstudio://resource/file/item-plan?epoch=1',
				},
				diff: null,
				file: null,
			},
		});
		const reviewPackage = makePackageWithItem(item);
		const head = item.contentRoles.head;
		if (head === undefined || head === null) {
			throw new Error('expected markdown head handle');
		}

		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: item.itemId,
			resources: { head: makeContentResource(head, '# Plan') },
		});

		expect(decision).toEqual({ kind: 'codeView', reason: 'invalidResourceUrl' });
	});

	test('falls back when selected markdown exceeds the preview budget', () => {
		const item = makeAddedMarkdownItem({
			sizeBytes: 6,
			contentRoles: {
				base: null,
				head: {
					...makeMarkdownHandle('item-plan', 'head'),
					sizeBytes: 6,
				},
				diff: null,
				file: null,
			},
		});
		const reviewPackage = makePackageWithItem(item);
		const head = item.contentRoles.head;
		if (head === undefined || head === null) {
			throw new Error('expected markdown head handle');
		}

		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: item.itemId,
			resources: { head: makeContentResource(head, '# Plan') },
			maxBytes: 5,
		});

		expect(decision).toEqual({ kind: 'codeView', reason: 'largeContent' });
	});

	test('previews one-sided worker diff markdown from the available side', () => {
		const reviewPackage = makePackageWithItem(makeAddedMarkdownItem());

		const decision = resolveBridgeMarkdownPreviewDecisionFromCodeViewItem({
			reviewPackage,
			selectedItemId: 'item-plan',
			selectedCodeViewItem: makeWorkerDiffCodeViewItem({
				additionLines: ['# Plan', '', 'body'],
				contentRoles: ['head'],
			}),
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				itemId: 'item-plan',
				role: 'head',
				sourcePath: 'docs/plans/bridge-plan.md',
				contentCacheKey: 'item-plan:head',
				contentHash: 'sha256:item-plan:head',
				markdownText: '# Plan\n\nbody',
			},
		});
	});

	test('previews partial worker diff markdown from the only loaded side', () => {
		const item = makeAddedMarkdownItem({
			basePath: 'docs/plans/bridge-plan.md',
			changeKind: 'modified',
			contentRoles: {
				base: makeMarkdownHandle('item-plan', 'base'),
				head: makeMarkdownHandle('item-plan', 'head'),
				diff: null,
				file: null,
			},
		});
		const reviewPackage = makePackageWithItem(item);

		const decision = resolveBridgeMarkdownPreviewDecisionFromCodeViewItem({
			reviewPackage,
			selectedItemId: 'item-plan',
			selectedCodeViewItem: makeWorkerDiffCodeViewItem({
				additionLines: ['# After'],
				contentRoles: ['head'],
			}),
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				itemId: 'item-plan',
				role: 'head',
				contentCacheKey: 'item-plan:head',
				contentHash: 'sha256:item-plan:head',
				markdownText: '# After',
			},
		});
	});

	test('rejects stale worker-selected items after a same-item package rollover', () => {
		const originalItem = makeAddedMarkdownItem();
		const changedHead = {
			...makeMarkdownHandle('item-plan', 'head'),
			cacheKey: 'item-plan:head:new',
			contentHash: 'sha256:item-plan:head:new',
		};
		const changedPackage = makePackageWithItem({
			...originalItem,
			contentRoles: {
				...originalItem.contentRoles,
				head: changedHead,
			},
			headContentHash: changedHead.contentHash,
			cacheKey: changedHead.cacheKey,
		});

		const decision = resolveBridgeMarkdownPreviewDecisionFromCodeViewItem({
			reviewPackage: changedPackage,
			selectedItemId: 'item-plan',
			selectedCodeViewItem: makeWorkerFileCodeViewItem({
				cacheKey: 'pierre-content:sha256:sha256:item-plan:head',
				contents: '# Old plan',
			}),
		});

		expect(decision).toEqual({ kind: 'codeView', reason: 'contentPending' });
	});

	test('uses current package path for same-hash file markdown rollover previews', () => {
		const currentPackage = makePackageWithItem(
			makeAddedMarkdownItem({
				headPath: 'docs/plans/renamed-bridge-plan.md',
			}),
		);

		const decision = resolveBridgeMarkdownPreviewDecisionFromCodeViewItem({
			reviewPackage: currentPackage,
			selectedItemId: 'item-plan',
			selectedCodeViewItem: makeWorkerFileCodeViewItem({
				cacheKey: 'pierre-content:fixture-preview:sha256:item-plan:head',
				contents: '# Renamed plan',
			}),
		});

		expect(decision).toMatchObject({
			kind: 'preview',
			source: {
				sourcePath: 'docs/plans/renamed-bridge-plan.md',
				markdownText: '# Renamed plan',
			},
		});
	});
});

function makePackageWithItem(item: BridgeReviewItemDescriptor): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	return {
		...basePackage,
		orderedItemIds: [item.itemId],
		itemsById: { [item.itemId]: item },
		summary: {
			filesChanged: 1,
			additions: item.additions,
			deletions: item.deletions,
			visibleFileCount: 1,
			hiddenFileCount: 0,
		},
	};
}

function makeAddedMarkdownItem(
	overrides: Partial<BridgeReviewItemDescriptor> = {},
): BridgeReviewItemDescriptor {
	const head = makeMarkdownHandle('item-plan', 'head');
	return {
		itemId: 'item-plan',
		itemKind: 'diff',
		itemVersion: 1,
		basePath: null,
		headPath: 'docs/plans/bridge-plan.md',
		changeKind: 'added',
		fileClass: 'docs',
		language: 'markdown',
		extension: 'md',
		sizeBytes: head.sizeBytes,
		baseContentHash: null,
		headContentHash: head.contentHash,
		contentHashAlgorithm: 'sha256',
		additions: 4,
		deletions: 0,
		isHiddenByDefault: false,
		hiddenReason: null,
		reviewPriority: 'normal',
		contentRoles: { base: null, head, diff: null, file: null },
		cacheKey: head.cacheKey,
		provenance: {
			paneIds: [],
			agentSessionIds: [],
			promptIds: [],
			operationIds: [],
			sourceKinds: [],
		},
		annotationSummary: { threadCount: 0, unresolvedThreadCount: 0, commentCount: 0 },
		reviewState: 'unreviewed',
		collapsed: false,
		...overrides,
	};
}

function makeMarkdownHandle(itemId: string, role: 'base' | 'head'): BridgeContentHandle {
	return {
		...makeBridgeContentHandle(itemId, role),
		mimeType: 'text/markdown',
		language: 'markdown',
		sizeBytes: 128,
	};
}

function makeContentResource(handle: BridgeContentHandle, text: string): BridgeContentResource {
	return {
		handle,
		readText: (): string => text,
	};
}

function makeWorkerFileCodeViewItem(props: {
	readonly cacheKey?: string;
	readonly contents: string;
}): BridgeMainCodeViewItem {
	const cacheKey = props.cacheKey ?? 'pierre-content:fixture-preview:sha256:item-plan:head';
	return {
		id: 'item-plan',
		type: 'file',
		file: {
			name: 'docs/plans/bridge-plan.md',
			contents: props.contents,
			lang: 'markdown',
			cacheKey,
		},
		version: 2,
		bridgeMetadata: {
			itemId: 'item-plan',
			displayPath: 'docs/plans/bridge-plan.md',
			contentState: 'hydrated',
			contentRoles: ['head'],
			cacheKey,
			lineCount: props.contents.split('\n').length,
		},
	};
}

function makeWorkerDiffCodeViewItem(props: {
	readonly additionLines: readonly string[];
	readonly contentRoles: readonly ('base' | 'head')[];
}): BridgeMainCodeViewItem {
	const cacheKey = 'pierre-content:empty|pierre-content:fixture-preview:sha256:item-plan:head';
	return {
		id: 'item-plan',
		type: 'diff',
		fileDiff: {
			name: 'docs/plans/bridge-plan.md',
			type: 'new',
			hunks: [],
			splitLineCount: props.additionLines.length,
			unifiedLineCount: props.additionLines.length,
			isPartial: false,
			deletionLines: [],
			additionLines: props.additionLines,
			cacheKey,
		},
		version: 2,
		bridgeMetadata: {
			itemId: 'item-plan',
			displayPath: 'docs/plans/bridge-plan.md',
			contentState: 'hydrated',
			contentRoles: props.contentRoles,
			cacheKey,
			lineCount: props.additionLines.length,
		},
	};
}
