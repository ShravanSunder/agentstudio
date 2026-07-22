import type { BridgeReviewDelta } from '../../foundation/review-package/bridge-review-delta.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package.js';
import * as mockedBackendSupport from './bridge-viewer-mocked-backend-support.js';

export type BridgeViewerBrowserFixtureClass =
	| 'small-mixed'
	| 'medium-agentstudio'
	| 'large-diffshub';
export type BridgeViewerMockedBackendDeliveryMode = 'full-load' | 'streaming-append';
export type BridgeViewerLargeFixtureItemPlacement = 'near-start' | 'after-fillers';

export interface BridgeViewerBrowserFixture {
	readonly reviewPackage: BridgeReviewPackage;
	readonly contentByHandleId: ReadonlyMap<string, string>;
	readonly streamingAppendDelta: BridgeReviewDelta;
	readonly metadata: {
		readonly fixtureId: string;
		readonly fixtureClass: BridgeViewerBrowserFixtureClass;
		readonly deliveryMode: BridgeViewerMockedBackendDeliveryMode;
		readonly itemCount: number;
		readonly pathCount: number;
		readonly diffLineCount: number;
		readonly packageBytes: number;
		readonly fixtureChecksum: string;
		readonly changeKindCounts: Readonly<Record<BridgeFileChangeKind, number>>;
		readonly fileClassCounts: Readonly<Record<BridgeFileClass, number>>;
		readonly selectedLargeFileLineCount: number;
		readonly addedFullContentTargetCount: number;
	};
	readonly expected: {
		readonly initialPath: string;
		readonly initialText: string;
		readonly initialHeadHandleId: string;
		readonly secondPath: string;
		readonly secondText: string;
		readonly addedPath: string;
		readonly addedText: string;
		readonly addedHeadHandleId: string;
		readonly hunkPath: string;
		readonly hunkExpandedText: string;
		readonly docsPath: string;
		readonly docsMarkdownText: string;
		readonly docsMarkdownHeading: string;
		readonly searchText: string;
		readonly searchPath: string;
		readonly testFilterPath: string;
		readonly testFilterText: string;
		readonly largePath: string;
		readonly largeText: string;
		readonly largeHeadHandleId: string;
		readonly secondHeadHandleId: string;
		readonly appendedPath: string;
		readonly appendedText: string;
		readonly appendedHeadHandleId: string;
	};
}

export function makeBridgeViewerBrowserFixture(
	props: {
		readonly fixtureClass?: BridgeViewerBrowserFixtureClass;
		readonly largeItemPlacement?: BridgeViewerLargeFixtureItemPlacement;
	} = {},
): BridgeViewerBrowserFixture {
	const fixtureClass = props.fixtureClass ?? 'small-mixed';
	const largeItemPlacement = props.largeItemPlacement ?? 'near-start';
	const basePackage = makeBridgeReviewPackage();
	const sourceItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-source-a',
		path: 'Sources/BridgeViewer/Alpha.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const secondItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-source-b',
		path: 'Sources/BridgeViewer/Beta.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const addedItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-added-source',
		path: 'Sources/BridgeViewer/NewPanel.ts',
		itemKind: 'file',
		changeKind: 'added',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const docsItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-docs-plan',
		path: 'docs/plans/bridge-viewer-browser.md',
		changeKind: 'added',
		fileClass: 'docs',
		language: 'markdown',
		extension: 'md',
	});
	const largeItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-large-diff',
		path: 'large/browser/huge-diff.ts',
		itemKind: 'file',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const hunkedItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-hunked-diff',
		path: 'Sources/BridgeViewer/HunkedContext.ts',
		changeKind: 'modified',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const appendedItem = mockedBackendSupport.makeBrowserFixtureItem({
		itemId: 'browser-streaming-append',
		path: 'streaming/append/NewStreamingPanel.ts',
		changeKind: 'added',
		fileClass: 'source',
		language: 'typescript',
		extension: 'ts',
	});
	const fillerItems = Array.from(
		{ length: mockedBackendSupport.fillerItemCountForFixtureClass(fixtureClass) },
		(_value: unknown, index: number) =>
			mockedBackendSupport.makeBrowserFillerItem({ fixtureClass, index }),
	);
	const leadingItems = [sourceItem, secondItem, addedItem, docsItem];
	const items =
		largeItemPlacement === 'after-fillers'
			? [...leadingItems, hunkedItem, ...fillerItems, largeItem]
			: [...leadingItems, largeItem, hunkedItem, ...fillerItems];
	const contentByHandleId = new Map<string, string>();

	mockedBackendSupport.addContent(contentByHandleId, sourceItem, {
		base: "export const selectedFile = 'alpha base';\n",
		head: "export const selectedFile = 'alpha head visible';\n",
	});
	mockedBackendSupport.addContent(contentByHandleId, secondItem, {
		base: "export const selectedFile = 'beta base';\n",
		head: "export const selectedFile = 'beta selected content';\n",
	});
	mockedBackendSupport.addContent(contentByHandleId, addedItem, {
		head: [
			'export function renderAddedPanel(): string {',
			"\treturn 'full added file content';",
			'}',
			'',
		].join('\n'),
	});
	mockedBackendSupport.addContent(contentByHandleId, docsItem, {
		head: '# Browser fixture\n\n```ts\nconst fixture = true;\n```\n',
	});
	mockedBackendSupport.addContent(contentByHandleId, largeItem, {
		base: mockedBackendSupport.largeBrowserDiffText('base'),
		head: mockedBackendSupport.largeBrowserDiffText('head'),
	});
	mockedBackendSupport.addContent(contentByHandleId, hunkedItem, {
		base: mockedBackendSupport.hunkedBrowserDiffText('base'),
		head: mockedBackendSupport.hunkedBrowserDiffText('head'),
	});
	mockedBackendSupport.addContent(contentByHandleId, appendedItem, {
		head: [
			'export function renderStreamingPanel(): string {',
			"\treturn 'streaming appended file content';",
			'}',
			'',
		].join('\n'),
	});

	for (const item of fillerItems) {
		mockedBackendSupport.addContent(contentByHandleId, item, {
			base: `export const filler${item.itemId} = 'base';\n`,
			head: `export const filler${item.itemId} = 'head';\n`,
		});
	}
	const sizedItems = items.map(
		(item): BridgeReviewItemDescriptor =>
			mockedBackendSupport.reviewItemWithContentSizes({ item, contentByHandleId }),
	);
	const sizedAppendedItem = mockedBackendSupport.reviewItemWithContentSizes({
		item: appendedItem,
		contentByHandleId,
	});

	const reviewPackage: BridgeReviewPackage = {
		...basePackage,
		packageId: `browser-mode-${fixtureClass}`,
		reviewGeneration: 338,
		revision: 1,
		orderedItemIds: sizedItems.map((item): string => item.itemId),
		itemsById: Object.fromEntries(sizedItems.map((item) => [item.itemId, item])),
		query: {
			...basePackage.query,
			pathScope: [],
		},
		summary: {
			filesChanged: sizedItems.length,
			additions: sizedItems.reduce((total, item): number => total + item.additions, 0),
			deletions: sizedItems.reduce((total, item): number => total + item.deletions, 0),
			visibleFileCount: sizedItems.length,
			hiddenFileCount: 0,
		},
		filterState: {
			...basePackage.filterState,
			showLargeFiles: true,
		},
	};

	const packageBytes = new TextEncoder().encode(JSON.stringify(reviewPackage)).byteLength;
	const selectedLargeFileLineCount = mockedBackendSupport.selectedLargeContentLineCount(
		contentByHandleId,
		largeItem,
	);
	const addedFullContentTargetCount = items.filter((item: BridgeReviewItemDescriptor): boolean => {
		const headHandle = item.contentRoles.head ?? null;
		return (
			item.changeKind === 'added' &&
			headHandle !== null &&
			mockedBackendSupport.lineCount(contentByHandleId.get(headHandle.handleId)) > 2
		);
	}).length;
	const streamingAppendDelta: BridgeReviewDelta = {
		packageId: reviewPackage.packageId,
		reviewGeneration: reviewPackage.reviewGeneration,
		revision: reviewPackage.revision + 1,
		operations: {
			addItems: [sizedAppendedItem],
			updateItems: [],
			removeItems: [],
			moveItems: [...reviewPackage.orderedItemIds, appendedItem.itemId],
			updateGroups: null,
			updateSummary: {
				filesChanged: reviewPackage.summary.filesChanged + 1,
				additions: reviewPackage.summary.additions + appendedItem.additions,
				deletions: reviewPackage.summary.deletions + appendedItem.deletions,
				visibleFileCount: reviewPackage.summary.visibleFileCount + 1,
				hiddenFileCount: reviewPackage.summary.hiddenFileCount,
			},
			invalidateContent: [],
		},
	};
	const fixtureChecksum = [
		reviewPackage.packageId,
		fixtureClass,
		sizedItems.length.toString(),
		contentByHandleId.size.toString(),
		packageBytes.toString(),
	].join(':');

	return {
		reviewPackage,
		streamingAppendDelta,
		metadata: {
			fixtureId: reviewPackage.packageId,
			fixtureClass,
			deliveryMode: 'full-load',
			itemCount: items.length,
			pathCount: new Set(
				items.flatMap((item): readonly string[] =>
					[item.basePath, item.headPath].filter(
						(path: string | null | undefined): path is string =>
							path !== null && path !== undefined,
					),
				),
			).size,
			diffLineCount: [...contentByHandleId.values()].reduce(
				(total: number, content: string): number => total + content.split('\n').length,
				0,
			),
			packageBytes,
			fixtureChecksum,
			changeKindCounts: mockedBackendSupport.countChangeKinds(items),
			fileClassCounts: mockedBackendSupport.countFileClasses(items),
			selectedLargeFileLineCount,
			addedFullContentTargetCount,
		},
		contentByHandleId,
		expected: {
			initialPath: 'Sources/BridgeViewer/Alpha.ts',
			initialText: "export const selectedFile = 'alpha head visible';",
			initialHeadHandleId: mockedBackendSupport.requiredHandleId(
				sourceItem.contentRoles.head,
				'initial head',
			),
			secondPath: 'Sources/BridgeViewer/Beta.ts',
			secondText: "export const selectedFile = 'beta selected content';",
			addedPath: 'Sources/BridgeViewer/NewPanel.ts',
			addedText: "return 'full added file content';",
			addedHeadHandleId: mockedBackendSupport.requiredHandleId(
				addedItem.contentRoles.head,
				'added head',
			),
			hunkPath: 'Sources/BridgeViewer/HunkedContext.ts',
			hunkExpandedText: "export const stableContextLine0025 = 'same';",
			docsPath: 'docs/plans/bridge-viewer-browser.md',
			docsMarkdownText: '# Browser fixture',
			docsMarkdownHeading: 'Browser fixture',
			searchText: 'Hunked',
			searchPath: 'Sources/BridgeViewer/HunkedContext.ts',
			testFilterPath: 'tree/module-00/file-007.ts',
			testFilterText: "export const fillerbrowser-filler-small-mixed-007 = 'head';",
			largePath: 'large/browser/huge-diff.ts',
			largeText: "export const generatedLine0000 = 'head';",
			largeHeadHandleId: mockedBackendSupport.requiredHandleId(
				largeItem.contentRoles.head,
				'large head',
			),
			secondHeadHandleId: mockedBackendSupport.requiredHandleId(
				secondItem.contentRoles.head,
				'second head',
			),
			appendedPath: 'streaming/append/NewStreamingPanel.ts',
			appendedText: "return 'streaming appended file content';",
			appendedHeadHandleId: mockedBackendSupport.requiredHandleId(
				appendedItem.contentRoles.head,
				'appended head',
			),
		},
	};
}
