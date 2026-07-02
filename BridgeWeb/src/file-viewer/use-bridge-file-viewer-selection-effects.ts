import { useEffect, type MutableRefObject } from 'react';

import type { BridgeViewerNavigationCommand } from '../app/bridge-viewer-navigation-models.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileDescriptorRequest,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import { canFetchWorktreeFileDescriptorContent } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	descriptorRequestForFirstFileTreeRow,
	descriptorRequestForTreePath,
	fileViewerNavigationTargetPath,
	findLatestDescriptorForOpenFile,
	worktreeFileDescriptorRequestsMatch,
	type BridgeFileViewerOpenState,
	type BridgeFileViewerRenderState,
} from './bridge-file-viewer-state.js';

interface UseBridgeFileViewerSelectionEffectsProps {
	readonly appliedNavigationCommandIdRef: MutableRefObject<string | null>;
	readonly autoOpenInitialFile: boolean;
	readonly isActive: boolean;
	readonly navigationCommand: BridgeViewerNavigationCommand | undefined;
	readonly openFile: (descriptor: WorktreeFileDescriptor) => Promise<void>;
	readonly openFileRequestIdRef: MutableRefObject<number>;
	readonly openFileState: BridgeFileViewerOpenState;
	readonly pendingSelectedDescriptorRequestRef: MutableRefObject<WorktreeFileDescriptorRequest | null>;
	readonly pendingStaleRefreshDescriptorRequestKeyRef: MutableRefObject<string | null>;
	readonly renderState: BridgeFileViewerRenderState;
	readonly requestFileDescriptor: (request: WorktreeFileDescriptorRequest) => void;
	readonly requestFileDescriptorForDemand: (request: WorktreeFileDescriptorRequest) => void;
}

export function useBridgeFileViewerSelectionEffects(
	props: UseBridgeFileViewerSelectionEffectsProps,
): void {
	const {
		appliedNavigationCommandIdRef,
		autoOpenInitialFile,
		isActive,
		navigationCommand,
		openFile,
		openFileRequestIdRef,
		openFileState,
		pendingSelectedDescriptorRequestRef,
		pendingStaleRefreshDescriptorRequestKeyRef,
		renderState,
		requestFileDescriptor,
		requestFileDescriptorForDemand,
	} = props;
	const navigationTargetPath = fileViewerNavigationTargetPath(navigationCommand);

	useEffect((): void => {
		if (!isActive || !autoOpenInitialFile || openFileState.status !== 'idle') {
			return;
		}
		if (navigationTargetPath !== null) {
			return;
		}
		if (pendingSelectedDescriptorRequestRef.current !== null) {
			return;
		}
		const initialDescriptor = renderState.descriptors.find((descriptor) =>
			canFetchWorktreeFileDescriptorContent(descriptor),
		);
		if (initialDescriptor !== undefined) {
			void openFile(initialDescriptor);
			return;
		}
		const initialDescriptorRequest = descriptorRequestForFirstFileTreeRow({
			sourceIdentity: renderState.sourceIdentity,
			treeRows: renderState.treeRows,
		});
		if (initialDescriptorRequest !== null) {
			requestFileDescriptor(initialDescriptorRequest);
		}
	}, [
		autoOpenInitialFile,
		isActive,
		navigationTargetPath,
		openFile,
		openFileState.status,
		openFileRequestIdRef,
		pendingSelectedDescriptorRequestRef,
		renderState.descriptors,
		renderState.sourceIdentity,
		renderState.treeRows,
		requestFileDescriptor,
	]);

	useEffect((): void => {
		if (!isActive || openFileState.status !== 'stale') {
			pendingStaleRefreshDescriptorRequestKeyRef.current = null;
			return;
		}
		const latestDescriptor = findLatestDescriptorForOpenFile({
			descriptor: openFileState.descriptor,
			renderState,
		});
		if (latestDescriptor !== null) {
			pendingStaleRefreshDescriptorRequestKeyRef.current = null;
			return;
		}
		const descriptorRequest = descriptorRequestForTreePath({
			lane: 'foreground',
			path: openFileState.path,
			sourceIdentity: renderState.sourceIdentity,
			treeRows: renderState.treeRows,
		});
		if (descriptorRequest === null) {
			return;
		}
		const requestKey = `${descriptorRequest.sourceIdentity.sourceId}:${descriptorRequest.sourceIdentity.sourceCursor}:${descriptorRequest.fileId}:${descriptorRequest.path}`;
		if (pendingStaleRefreshDescriptorRequestKeyRef.current === requestKey) {
			return;
		}
		pendingStaleRefreshDescriptorRequestKeyRef.current = requestKey;
		requestFileDescriptorForDemand(descriptorRequest);
	}, [
		openFileState,
		isActive,
		pendingStaleRefreshDescriptorRequestKeyRef,
		renderState,
		requestFileDescriptorForDemand,
	]);

	useEffect((): void => {
		if (!isActive || navigationCommand === undefined || navigationTargetPath === null) {
			return;
		}
		if (appliedNavigationCommandIdRef.current === navigationCommand.commandId) {
			return;
		}
		const targetDescriptor = renderState.descriptors.find(
			(descriptor) =>
				descriptor.path === navigationTargetPath &&
				canFetchWorktreeFileDescriptorContent(descriptor),
		);
		if (targetDescriptor === undefined) {
			const descriptorRequest = descriptorRequestForTreePath({
				lane: 'foreground',
				path: navigationTargetPath,
				sourceIdentity: renderState.sourceIdentity,
				treeRows: renderState.treeRows,
			});
			if (
				descriptorRequest !== null &&
				!worktreeFileDescriptorRequestsMatch(
					pendingSelectedDescriptorRequestRef.current,
					descriptorRequest,
				)
			) {
				requestFileDescriptor(descriptorRequest);
			}
			return;
		}
		appliedNavigationCommandIdRef.current = navigationCommand.commandId;
		void openFile(targetDescriptor);
	}, [
		appliedNavigationCommandIdRef,
		isActive,
		navigationTargetPath,
		navigationCommand,
		openFile,
		pendingSelectedDescriptorRequestRef,
		renderState.descriptors,
		renderState.sourceIdentity,
		renderState.treeRows,
		requestFileDescriptor,
	]);
}
