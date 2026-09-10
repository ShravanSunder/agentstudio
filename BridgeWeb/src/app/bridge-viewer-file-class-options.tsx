import {
	BookOpenIcon,
	DatabaseIcon,
	FileCodeIcon,
	FileCogIcon,
	FileQuestionMarkIcon,
	FilesIcon,
	FlaskConicalIcon,
	PackageIcon,
	SettingsIcon,
} from 'lucide-react';
import type { ReactNode } from 'react';

import type { BridgeFileClass } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeViewerFacetMenuOption } from './bridge-viewer-filter-menu.js';

export type BridgeViewerFileCategory = Exclude<BridgeFileClass, 'binary' | 'large'>;

const bridgeViewerFileCategories: readonly BridgeViewerFileCategory[] = [
	'source',
	'test',
	'docs',
	'config',
	'fixture',
];

export const bridgeViewerFileCategoryOptions: readonly BridgeViewerFacetMenuOption<
	BridgeViewerFileCategory | 'all'
>[] = [
	{
		value: 'all',
		label: 'All',
		description: 'Show every supported category',
		icon: bridgeViewerFileCategoryIcon('all'),
	},
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
	switch (fileCategory) {
		case 'all':
			return <FilesIcon aria-hidden="true" />;
		case 'source':
			return <FileCodeIcon aria-hidden="true" />;
		case 'test':
			return <FlaskConicalIcon aria-hidden="true" />;
		case 'docs':
			return <BookOpenIcon aria-hidden="true" />;
		case 'config':
			return <SettingsIcon aria-hidden="true" />;
		case 'generated':
			return <FileCogIcon aria-hidden="true" />;
		case 'vendor':
			return <PackageIcon aria-hidden="true" />;
		case 'fixture':
			return <DatabaseIcon aria-hidden="true" />;
		case 'unknown':
			return <FileQuestionMarkIcon aria-hidden="true" />;
	}
	return assertNeverBridgeViewerFileCategory(fileCategory);
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
			return 'Dependencies / build';
		case 'fixture':
			return 'Test data';
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
