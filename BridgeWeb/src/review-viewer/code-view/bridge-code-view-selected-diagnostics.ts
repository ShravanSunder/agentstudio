import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgeContentRole } from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeCodeViewContentFacts } from './bridge-code-view-materialization.js';
import type { BridgeCodeViewMaterializationDiagnostic } from './bridge-code-view-panel-support.js';

interface SelectedContentSummary {
	readonly cacheKeyCount: number;
	readonly characterCount: number;
	readonly lineCount: number;
}

export interface SelectedContentDiagnostics {
	readonly cacheKeys: string;
	readonly roleCount: number;
	readonly roleNames: string;
	readonly state: 'none' | 'pending' | 'ready';
	readonly summary: SelectedContentSummary;
}

const selectedContentRoleOrder: readonly BridgeContentRole[] = ['base', 'head', 'diff', 'file'];

export function selectedContentStateForPanel(props: {
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
	readonly selectedItemId: string | null;
}): 'none' | 'pending' | 'ready' {
	if (props.selectedItemId === null) {
		return 'none';
	}
	return props.selectedCodeViewItem === null || props.selectedCodeViewItem === undefined
		? 'pending'
		: 'ready';
}

export function selectedContentRoleNamesForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentFacts | null | undefined;
}): string {
	if (props.selectedContentResources === null || props.selectedContentResources === undefined) {
		return '';
	}
	return selectedContentRoleOrder
		.filter((role): boolean => props.selectedContentResources?.[role] !== undefined)
		.join(',');
}

export function selectedContentCacheKeysForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentFacts | null | undefined;
}): string {
	if (props.selectedContentResources === null || props.selectedContentResources === undefined) {
		return '';
	}
	const cacheKeys: string[] = [];
	for (const role of selectedContentRoleOrder) {
		const resource = props.selectedContentResources[role];
		if (resource !== undefined) {
			cacheKeys.push(`${role}:${resource.cacheKey}`);
		}
	}
	return cacheKeys.join(',');
}

export function selectedContentSummaryForPanel(props: {
	readonly selectedContentResources: BridgeCodeViewContentFacts | null | undefined;
}): SelectedContentSummary {
	if (props.selectedContentResources === null || props.selectedContentResources === undefined) {
		return {
			cacheKeyCount: 0,
			characterCount: 0,
			lineCount: 0,
		};
	}

	const resources = Object.values(props.selectedContentResources).filter(
		(resource): resource is NonNullable<typeof resource> => resource !== undefined,
	);
	return {
		cacheKeyCount: new Set(resources.map((resource): string => resource.cacheKey)).size,
		characterCount: resources.reduce(
			(totalCharacters, resource): number =>
				totalCharacters + (resource.byteLength ?? resource.sizeBytes),
			0,
		),
		lineCount: 0,
	};
}

export function selectedContentDiagnosticsForPanel(props: {
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
	readonly selectedItemId: string | null;
}): SelectedContentDiagnostics {
	const selectedCodeViewItem = props.selectedCodeViewItem;
	const contentRoles = selectedCodeViewItem?.bridgeMetadata.contentRoles ?? [];
	const cacheKeyEntries =
		selectedCodeViewItem === null || selectedCodeViewItem === undefined
			? []
			: selectedContentCacheKeyEntriesForCodeViewItem(selectedCodeViewItem);
	return {
		cacheKeys: cacheKeyEntries.join(','),
		roleCount: contentRoles.length,
		roleNames: contentRoles.join(','),
		state: selectedContentStateForPanel({
			selectedCodeViewItem,
			selectedItemId: props.selectedItemId,
		}),
		summary: {
			cacheKeyCount: cacheKeyEntries.length,
			characterCount:
				selectedCodeViewItem === null || selectedCodeViewItem === undefined
					? 0
					: characterCountForSelectedCodeViewItem(selectedCodeViewItem),
			lineCount:
				selectedCodeViewItem === null || selectedCodeViewItem === undefined
					? 0
					: lineCountForSelectedCodeViewItem(selectedCodeViewItem),
		},
	};
}

export function selectedMaterializationDiagnosticForPanel(props: {
	readonly materializationDiagnostic: BridgeCodeViewMaterializationDiagnostic;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
}): BridgeCodeViewMaterializationDiagnostic {
	const selectedCodeViewItem = props.selectedCodeViewItem;
	if (
		selectedCodeViewItem === null ||
		selectedCodeViewItem === undefined ||
		props.materializationDiagnostic.updateResult !== 'not-run'
	) {
		return props.materializationDiagnostic;
	}
	return materializationDiagnosticForWorkerPreparedCodeViewItem(selectedCodeViewItem);
}

function selectedContentCacheKeyEntriesForCodeViewItem(
	item: BridgeMainCodeViewItem,
): readonly string[] {
	const cacheKeyParts = item.bridgeMetadata.cacheKey.split('|');
	return item.bridgeMetadata.contentRoles.map((role): string => {
		return `${role}:${cacheKeyForWorkerPreparedRole({
			cacheKey: item.bridgeMetadata.cacheKey,
			cacheKeyParts,
			role,
		})}`;
	});
}

function cacheKeyForWorkerPreparedRole(props: {
	readonly cacheKey: string;
	readonly cacheKeyParts: readonly string[];
	readonly role: BridgeContentRole;
}): string {
	switch (props.role) {
		case 'base':
			return props.cacheKeyParts[0] ?? props.cacheKey;
		case 'head':
			return props.cacheKeyParts[1] ?? props.cacheKey;
		case 'diff':
		case 'file':
			return props.cacheKey;
	}
	return props.cacheKey;
}

function characterCountForSelectedCodeViewItem(item: BridgeMainCodeViewItem): number {
	const metadataLineCount = item.bridgeMetadata.lineCount ?? 0;
	if (item.type === 'file') {
		return Math.max(item.file.contents.length, metadataLineCount);
	}
	const changedLineCharacterCount = [
		...item.fileDiff.additionLines,
		...item.fileDiff.deletionLines,
	].reduce((totalCharacters, line): number => totalCharacters + line.length, 0);
	return Math.max(changedLineCharacterCount, metadataLineCount);
}

function lineCountForSelectedCodeViewItem(item: BridgeMainCodeViewItem): number {
	if (item.type === 'file') {
		return item.file.contents.length === 0 ? 0 : item.file.contents.split('\n').length;
	}
	return item.fileDiff.additionLines.length + item.fileDiff.deletionLines.length;
}

function materializationDiagnosticForWorkerPreparedCodeViewItem(
	item: BridgeMainCodeViewItem,
): BridgeCodeViewMaterializationDiagnostic {
	if (item.type === 'diff') {
		return {
			updateResult: 'updated',
			itemType: item.type,
			itemVersion: item.version ?? 0,
			modelContentState: item.bridgeMetadata.contentState,
			modelItemVersion: item.version ?? 0,
			additionLineCount: item.fileDiff.additionLines.length,
			deletionLineCount: item.fileDiff.deletionLines.length,
			fileLineCount: 0,
			durationMilliseconds: 0,
		};
	}
	return {
		updateResult: 'updated',
		itemType: item.type,
		itemVersion: item.version ?? 0,
		modelContentState: item.bridgeMetadata.contentState,
		modelItemVersion: item.version ?? 0,
		additionLineCount: 0,
		deletionLineCount: 0,
		fileLineCount: item.bridgeMetadata.lineCount ?? 0,
		durationMilliseconds: 0,
	};
}
