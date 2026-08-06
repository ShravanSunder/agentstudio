import { FolderIcon } from 'lucide-react';
import type { ReactNode } from 'react';

import type { BridgeFileClass } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeViewerFacetMenuOption } from './bridge-viewer-filter-menu.js';

export type BridgeViewerFileCategory = Exclude<BridgeFileClass, 'binary' | 'large'>;

const bridgeViewerFileCategories: readonly BridgeViewerFileCategory[] = [
	'source',
	'test',
	'docs',
	'config',
	'generated',
	'vendor',
	'fixture',
	'unknown',
];

export const bridgeViewerFileCategoryOptions: readonly BridgeViewerFacetMenuOption<
	BridgeViewerFileCategory | 'all'
>[] = [
	{ value: 'all', label: 'All', description: 'Show every supported category', icon: '*' },
	...bridgeViewerFileCategories.map(
		(
			fileCategory: BridgeViewerFileCategory,
		): BridgeViewerFacetMenuOption<BridgeViewerFileCategory | 'all'> => ({
			value: fileCategory,
			label: labelForFileCategory(fileCategory),
			description: descriptionForFileCategory(fileCategory),
			icon: bridgeViewerFileCategoryIcon(fileCategory),
		}),
	),
];

export function bridgeViewerFileCategoryIcon(
	fileCategory: BridgeViewerFileCategory | 'all',
): ReactNode {
	if (fileCategory === 'all') {
		return '*';
	}
	if (fileCategory === 'docs') {
		return <FolderIcon aria-hidden="true" className="size-3.5" />;
	}
	return fileCategory.slice(0, 1).toUpperCase();
}

function labelForFileCategory(fileCategory: BridgeViewerFileCategory): string {
	switch (fileCategory) {
		case 'source':
			return 'Source code';
		case 'test':
			return 'Tests';
		case 'docs':
			return 'Documentation';
		case 'config':
			return 'Configuration';
		case 'generated':
			return 'Generated';
		case 'vendor':
			return 'Dependencies and build output';
		case 'fixture':
			return 'Fixtures';
		case 'unknown':
			return 'Other';
	}
	return assertNeverBridgeViewerFileCategory(fileCategory);
}

function descriptionForFileCategory(fileCategory: BridgeViewerFileCategory): string {
	switch (fileCategory) {
		case 'source':
			return 'Swift, TypeScript, JavaScript, and CSS implementation files';
		case 'test':
			return 'Files in test trees and .test or .spec test sources';
		case 'docs':
			return 'Markdown files and files under documentation trees';
		case 'config':
			return 'Recognized package, build, and tool configuration files';
		case 'generated':
			return 'Files under generated trees or with a generated Swift suffix';
		case 'vendor':
			return 'Files under dependency, vendor, build, or DerivedData trees';
		case 'fixture':
			return 'Files under fixture data trees';
		case 'unknown':
			return 'Files without a matching path or size classification';
	}
	return assertNeverBridgeViewerFileCategory(fileCategory);
}

function assertNeverBridgeViewerFileCategory(fileCategory: never): never {
	throw new Error(`Unsupported Bridge file category: ${String(fileCategory)}`);
}
