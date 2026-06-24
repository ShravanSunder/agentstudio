import {
	makeBridgeContentHandle,
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../../foundation/review-package/bridge-review-package-test-support.js';
import type {
	BridgeContentHandle,
	BridgeContentRole,
	BridgeFileChangeKind,
	BridgeFileClass,
	BridgeFileReviewState,
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
	BridgeReviewPriority,
} from '../../foundation/review-package/bridge-review-package.js';

interface FixtureItemProps {
	readonly itemId: string;
	readonly basePath: string | null;
	readonly headPath: string | null;
	readonly changeKind: BridgeFileChangeKind;
	readonly fileClass: BridgeFileClass;
	readonly reviewPriority?: BridgeReviewPriority;
	readonly reviewState?: BridgeFileReviewState;
	readonly extension?: string | null;
	readonly language?: string | null;
	readonly isHiddenByDefault?: boolean;
	readonly hiddenReason?: string | null;
	readonly roles?: readonly BridgeContentRole[];
	readonly isBinary?: boolean;
}

export function makeBridgeViewerProjectionFixture(): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const items = [
		makeFixtureItem({
			itemId: 'source-high',
			basePath: 'Sources/App/Core.swift',
			headPath: 'Sources/App/Core.swift',
			changeKind: 'modified',
			fileClass: 'source',
			reviewPriority: 'high',
		}),
		makeFixtureItem({
			itemId: 'source-normal',
			basePath: 'Sources/App/View.swift',
			headPath: 'Sources/App/View.swift',
			changeKind: 'modified',
			fileClass: 'source',
		}),
		makeFixtureItem({
			itemId: 'test-view',
			basePath: 'Tests/App/ViewTests.swift',
			headPath: 'Tests/App/ViewTests.swift',
			changeKind: 'modified',
			fileClass: 'test',
		}),
		makeFixtureItem({
			itemId: 'docs-plan',
			basePath: 'docs/plans/2026-bridge-plan.md',
			headPath: 'docs/plans/2026-bridge-plan.md',
			changeKind: 'modified',
			fileClass: 'docs',
			extension: 'md',
			language: 'markdown',
		}),
		makeFixtureItem({
			itemId: 'renamed-source',
			basePath: 'Sources/OldName.swift',
			headPath: 'Sources/NewName.swift',
			changeKind: 'renamed',
			fileClass: 'source',
			reviewState: 'viewed',
		}),
		makeFixtureItem({
			itemId: 'deleted-source',
			basePath: 'Sources/Removed.swift',
			headPath: null,
			changeKind: 'deleted',
			fileClass: 'source',
			reviewState: 'viewed',
			roles: ['base'],
		}),
		makeFixtureItem({
			itemId: 'duplicate-display',
			basePath: 'Sources/App/View.swift',
			headPath: 'Sources/App/View.swift',
			changeKind: 'copied',
			fileClass: 'source',
			reviewState: 'viewed',
		}),
		makeFixtureItem({
			itemId: 'hidden-binary',
			basePath: null,
			headPath: 'Assets/logo.png',
			changeKind: 'added',
			fileClass: 'binary',
			extension: 'png',
			language: null,
			isHiddenByDefault: true,
			hiddenReason: 'binary',
			roles: ['head'],
			isBinary: true,
		}),
	];

	return {
		...basePackage,
		orderedItemIds: items.map((item: BridgeReviewItemDescriptor): string => item.itemId),
		itemsById: Object.fromEntries(
			items.map(
				(item: BridgeReviewItemDescriptor): readonly [string, BridgeReviewItemDescriptor] => [
					item.itemId,
					item,
				],
			),
		),
		summary: {
			filesChanged: items.length,
			additions: items.reduce(
				(total: number, item: BridgeReviewItemDescriptor): number => total + item.additions,
				0,
			),
			deletions: items.reduce(
				(total: number, item: BridgeReviewItemDescriptor): number => total + item.deletions,
				0,
			),
			visibleFileCount: items.length - 1,
			hiddenFileCount: 1,
		},
		query: {
			...basePackage.query,
			pathScope: [],
		},
	};
}

function makeFixtureItem(props: FixtureItemProps): BridgeReviewItemDescriptor {
	const path = props.headPath ?? props.basePath ?? props.itemId;
	const baseItem = makeBridgeReviewItem({ itemId: props.itemId, path });
	const roles = props.roles ?? ['base', 'head'];
	const base = roles.includes('base')
		? makeFixtureHandle(props.itemId, 'base', props.isBinary ?? false)
		: null;
	const head = roles.includes('head')
		? makeFixtureHandle(props.itemId, 'head', props.isBinary ?? false)
		: null;

	return {
		...baseItem,
		itemId: props.itemId,
		basePath: props.basePath,
		headPath: props.headPath,
		changeKind: props.changeKind,
		fileClass: props.fileClass,
		language: props.language ?? baseItem.language ?? null,
		extension: props.extension ?? baseItem.extension ?? null,
		baseContentHash: base?.contentHash ?? null,
		headContentHash: head?.contentHash ?? null,
		additions: props.changeKind === 'deleted' ? 0 : 3,
		deletions: props.changeKind === 'added' ? 0 : 2,
		isHiddenByDefault: props.isHiddenByDefault ?? false,
		hiddenReason: props.hiddenReason ?? null,
		reviewPriority: props.reviewPriority ?? 'normal',
		contentRoles: { base, head, diff: null, file: null },
		cacheKey: `${props.itemId}:${roles.join('|')}`,
		reviewState: props.reviewState ?? 'unreviewed',
	};
}

function makeFixtureHandle(
	itemId: string,
	role: 'base' | 'head',
	isBinary: boolean,
): BridgeContentHandle {
	const handle = makeBridgeContentHandle(itemId, role);

	return {
		...handle,
		isBinary,
		mimeType: isBinary ? 'image/png' : handle.mimeType,
		language: isBinary ? null : (handle.language ?? null),
	};
}
