import { useEffect, useRef } from 'react';

import type { WorktreeAnnotationNavigationController } from '../worktree-annotations/worktree-annotation-navigation.js';
import { fileCollectionDisplayPath } from './bridge-file-collection-display-path.js';
import type { BridgeFileViewerAppProps } from './bridge-file-viewer-app-props.js';
import type {
	BridgeFileViewerDisplayModel,
	BridgeFileViewerSelection,
} from './bridge-file-viewer-display-model.js';
import type { BridgeFileViewerSelectionGateOutcome } from './bridge-file-viewer-selection-gate.js';

type BridgeFileViewerNavigationCommand = NonNullable<BridgeFileViewerAppProps['navigationCommand']>;

export interface UseBridgeFileViewerProgrammaticSelectionProps {
	readonly annotationNavigation: WorktreeAnnotationNavigationController | null;
	readonly autoOpenInitialFile: boolean;
	readonly displayModel: Pick<
		BridgeFileViewerDisplayModel,
		'acceptedQueryKey' | 'firstFileRow' | 'memberGroups' | 'treeComplete' | 'treeRowByPath'
	>;
	/** The query the viewer currently asks for, and whether it filters rows. */
	readonly query: { readonly isUnfiltered: boolean; readonly key: string };
	/** Clear the filter and search so every listed row is projected again. */
	readonly revealAllRows: () => void;
	/** Settle a native navigation whose target the unfiltered tree does not list. */
	readonly reportNativeNavigationNotListed: (command: BridgeFileViewerNavigationCommand) => void;
	readonly isActive: boolean;
	readonly isNavigationCommandStillEligible: (
		command: BridgeFileViewerNavigationCommand,
	) => boolean;
	readonly navigationCommand: BridgeFileViewerNavigationCommand | undefined;
	/** Receives each native file navigation as it enters the selection gate. */
	readonly trackNativeNavigation: (
		command: BridgeFileViewerNavigationCommand,
		selection: BridgeFileViewerSelection,
		outcome: Promise<BridgeFileViewerSelectionGateOutcome>,
	) => void;
	readonly openPathCommand: BridgeFileViewerAppProps['openPathCommand'];
	readonly projectionExclusionClearedSelectionRef: { readonly current: boolean };
	readonly selectFile: (
		selection: BridgeFileViewerSelection,
		source: 'programmatic' | 'user',
	) => Promise<BridgeFileViewerSelectionGateOutcome>;
	readonly selection: BridgeFileViewerSelection | null;
}

/**
 * Applies the viewer's programmatic selections in priority order: a Review
 * "Open in Files" location, then a native file navigation command, then the
 * optional first-file auto open. Each is applied once per command identity and
 * goes through the same editor-preparation gate as a tree click.
 *
 * A native navigation never stays pending: when its row is hidden by the
 * current filter or search, the viewer reveals every row (the same reveal the
 * annotation navigation uses) and applies it once the unfiltered projection is
 * accepted; if the complete, unfiltered tree still has no such file, it
 * settles as not listed.
 */
export function useBridgeFileViewerProgrammaticSelection(
	props: UseBridgeFileViewerProgrammaticSelectionProps,
): void {
	const {
		annotationNavigation,
		autoOpenInitialFile,
		displayModel,
		isActive,
		isNavigationCommandStillEligible,
		navigationCommand,
		openPathCommand,
		projectionExclusionClearedSelectionRef,
		query,
		reportNativeNavigationNotListed,
		revealAllRows,
		selectFile,
		selection,
		trackNativeNavigation,
	} = props;
	const appliedOpenPathCommandIdRef = useRef<number | null>(null);
	const appliedNavigationApplicationKeyRef = useRef<string | null>(null);
	useEffect((): void => {
		if (!isActive) {
			return;
		}
		if (
			openPathCommand !== undefined &&
			appliedOpenPathCommandIdRef.current !== openPathCommand.commandId
		) {
			const displayPath = fileCollectionDisplayPath(
				displayModel.memberGroups,
				openPathCommand.location.worktreeId,
				openPathCommand.location.relativePath,
			);
			const row = displayPath === null ? undefined : displayModel.treeRowByPath.get(displayPath);
			if (row?.fileId !== null && row?.fileId !== undefined && !row.isDirectory) {
				appliedOpenPathCommandIdRef.current = openPathCommand.commandId;
				void selectFile({ fileId: row.fileId, path: row.path }, 'programmatic');
			}
			return;
		}
		const navigationApplicationKey = bridgeFileViewerNavigationApplicationKey(navigationCommand);
		if (
			navigationCommand !== undefined &&
			appliedNavigationApplicationKeyRef.current !== navigationApplicationKey
		) {
			if (!isNavigationCommandStillEligible(navigationCommand)) return;
			const row = displayModel.treeRowByPath.get(navigationCommand.target.path);
			if (row?.fileId !== null && row?.fileId !== undefined && !row.isDirectory) {
				appliedNavigationApplicationKeyRef.current = navigationApplicationKey;
				const nextSelection = { fileId: row.fileId, path: row.path };
				trackNativeNavigation(
					navigationCommand,
					nextSelection,
					selectFile(nextSelection, 'programmatic'),
				);
				return;
			}
			if (!query.isUnfiltered) {
				revealAllRows();
				return;
			}
			// Only the committed initial tree proves a row absent. A File status is
			// no such proof: a collection forwards member status while it is
			// still enumerating.
			if (!displayModel.treeComplete || displayModel.acceptedQueryKey !== query.key) return;
			appliedNavigationApplicationKeyRef.current = navigationApplicationKey;
			reportNativeNavigationNotListed(navigationCommand);
			return;
		}
		if (
			annotationNavigation?.request != null ||
			!autoOpenInitialFile ||
			selection !== null ||
			projectionExclusionClearedSelectionRef.current
		) {
			return;
		}
		const firstFileRow = displayModel.firstFileRow;
		if (firstFileRow?.fileId !== null && firstFileRow?.fileId !== undefined) {
			void selectFile({ fileId: firstFileRow.fileId, path: firstFileRow.path }, 'programmatic');
		}
	}, [
		annotationNavigation,
		autoOpenInitialFile,
		displayModel.acceptedQueryKey,
		displayModel.memberGroups,
		displayModel.treeComplete,
		displayModel.treeRowByPath,
		displayModel.firstFileRow,
		isActive,
		isNavigationCommandStillEligible,
		navigationCommand,
		openPathCommand,
		projectionExclusionClearedSelectionRef,
		query,
		reportNativeNavigationNotListed,
		revealAllRows,
		selectFile,
		selection,
		trackNativeNavigation,
	]);
}

function bridgeFileViewerNavigationApplicationKey(
	navigationCommand: BridgeFileViewerNavigationCommand | undefined,
): string | null {
	if (navigationCommand === undefined) return null;
	return [
		navigationCommand.commandId,
		navigationCommand.bindingRevision,
		navigationCommand.source.sourceId,
		navigationCommand.source.subscriptionGeneration,
	].join('\u0000');
}
