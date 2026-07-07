import { createBridgeResourceDescriptorRegistry } from '../core/resources/bridge-resource-registry.js';
import { applyWorktreeFileProtocolFrame } from '../features/worktree-file/materialization/worktree-file-materializer.js';
import type { WorktreeFileProtocolFrame } from '../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	defaultPaneId,
	type WorktreeFileRuntimeFrameApplier,
	type WorktreeFileRuntimeFrameApplyResult,
} from './bridge-file-viewer-state.js';

export function createBridgeFileViewerFrameApplier(): WorktreeFileRuntimeFrameApplier {
	const registry = createBridgeResourceDescriptorRegistry({
		allowedResourceKindsByProtocol: {
			'worktree-file': new Set(['worktree.fileContent', 'worktree.fileRange']),
		},
	});
	return {
		applyFrame(frame: WorktreeFileProtocolFrame): WorktreeFileRuntimeFrameApplyResult {
			const materializeResult = applyWorktreeFileProtocolFrame({
				frame,
				paneId: defaultPaneId,
				registry,
			});
			if (!materializeResult.ok) {
				return materializeResult;
			}
			return {
				ok: true,
				deltaKind: materializeResult.delta.kind,
			};
		},
	};
}
