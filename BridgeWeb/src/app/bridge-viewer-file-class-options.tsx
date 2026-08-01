import { FolderIcon } from 'lucide-react';
import type { ReactNode } from 'react';

import type { BridgeFileClass } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeViewerFacetMenuOption } from './bridge-viewer-filter-menu.js';

export type BridgeViewerFileTreeClass = Exclude<BridgeFileClass, 'binary'>;

const bridgeViewerFileClasses: readonly BridgeFileClass[] = [
	'source',
	'test',
	'docs',
	'config',
	'generated',
	'vendor',
	'binary',
	'large',
	'fixture',
	'unknown',
];

export const bridgeViewerFileClassOptions: readonly BridgeViewerFacetMenuOption<
	BridgeFileClass | 'all'
>[] = [
	{ value: 'all', label: 'All file types', description: 'Show every classified file', icon: '*' },
	...bridgeViewerFileClasses.map(
		(fileClass: BridgeFileClass): BridgeViewerFacetMenuOption<BridgeFileClass | 'all'> => ({
			value: fileClass,
			label: sentenceCase(fileClass),
			description: descriptionForFileClass(fileClass),
			icon: bridgeViewerFileClassIcon(fileClass),
		}),
	),
];

export const bridgeViewerFileTreeClassOptions: readonly BridgeViewerFacetMenuOption<
	BridgeViewerFileTreeClass | 'all'
>[] = bridgeViewerFileClassOptions.filter(
	(option): option is BridgeViewerFacetMenuOption<BridgeViewerFileTreeClass | 'all'> =>
		option.value !== 'binary',
);

export function bridgeViewerFileClassIcon(fileClass: BridgeFileClass | 'all'): ReactNode {
	if (fileClass === 'all') {
		return '*';
	}
	if (fileClass === 'docs') {
		return <FolderIcon aria-hidden="true" className="size-3.5" />;
	}
	return fileClass.slice(0, 1).toUpperCase();
}

function sentenceCase(value: string): string {
	return value.length === 0 ? value : `${value.slice(0, 1).toUpperCase()}${value.slice(1)}`;
}

function descriptionForFileClass(fileClass: BridgeFileClass): string {
	switch (fileClass) {
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
		case 'binary':
			return 'Binary files and non-text assets';
		case 'large':
			return 'Files at least 1 MB according to native metadata';
		case 'fixture':
			return 'Files under fixture data trees';
		case 'unknown':
			return 'Files without a matching path or size classification';
	}
	return assertNeverBridgeFileClass(fileClass);
}

function assertNeverBridgeFileClass(fileClass: never): never {
	throw new Error(`Unsupported Bridge file class: ${String(fileClass)}`);
}
