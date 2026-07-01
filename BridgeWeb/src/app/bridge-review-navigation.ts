import type { WorktreeFileDescriptor } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type {
	BridgeViewerNavigationCommand,
	BridgeViewerSource,
} from './bridge-viewer-navigation-models.js';

export function bridgeReviewNavigationCommandForWorktreeDescriptor(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly reviewSource?: Extract<BridgeViewerSource, { readonly sourceKind: 'reviewComparison' }>;
}): BridgeViewerNavigationCommand {
	const reviewSource =
		props.reviewSource ??
		defaultReviewSourceForWorktreeDescriptor({
			descriptor: props.descriptor,
		});
	return {
		commandId: [
			'bridge',
			'worktree',
			'review',
			'file',
			props.descriptor.sourceIdentity.sourceId,
			props.descriptor.fileId,
			props.descriptor.contentHash ?? props.descriptor.contentHandle,
		].join(':'),
		commandKind: 'activateTarget',
		context: 'review',
		restoreMemory: true,
		source: reviewSource,
		target: {
			targetKind: 'file',
			comparisonId: reviewSource.comparisonId,
			fileRef: {
				sourceId: reviewSource.sourceId,
				path: props.descriptor.path,
			},
			version: 'current',
		},
	};
}

function defaultReviewSourceForWorktreeDescriptor(props: {
	readonly descriptor: WorktreeFileDescriptor;
}): Extract<BridgeViewerSource, { readonly sourceKind: 'reviewComparison' }> {
	return {
		sourceKind: 'reviewComparison',
		sourceId: `${props.descriptor.sourceIdentity.sourceId}:review`,
		comparisonId: `worktree:${props.descriptor.sourceIdentity.worktreeId}:${props.descriptor.sourceIdentity.subscriptionGeneration}`,
	};
}
