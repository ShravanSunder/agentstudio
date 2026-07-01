import type {
	BridgeAttachedResourceDescriptor,
	BridgeDescriptorRef,
} from '../../../core/models/bridge-resource-descriptor.js';
import type { BridgeResourceDescriptorRegistry } from '../../../core/resources/bridge-resource-registry.js';
import type {
	WorktreeFileDescriptor,
	WorktreeFileInvalidation,
	WorktreeFileProtocolFrame,
	WorktreeFileSurfaceSourceIdentity,
	WorktreeTreeOperation,
	WorktreeTreeVirtualizedSizeFacts,
} from '../models/worktree-file-protocol-models.js';
import { worktreeFileProtocolFrameSchema } from '../models/worktree-file-protocol-models.js';

export type WorktreeFileMaterializerDelta =
	| {
			readonly kind: 'snapshot';
			readonly source: WorktreeFileSurfaceSourceIdentity;
			readonly treeSizeFacts?: WorktreeTreeVirtualizedSizeFacts;
	  }
	| {
			readonly kind: 'treeWindow';
			readonly treeSizeFacts?: WorktreeTreeVirtualizedSizeFacts;
	  }
	| {
			readonly kind: 'treeDelta';
			readonly operations: readonly WorktreeTreeOperation[];
	  }
	| {
			readonly kind: 'statusPatch';
			readonly patch: WorktreeFileProtocolFrame extends infer _TFrame
				? Extract<
						WorktreeFileProtocolFrame,
						{ readonly frameKind: 'worktree.statusPatch' }
					>['patch']
				: never;
	  }
	| {
			readonly kind: 'fileDescriptor';
			readonly descriptor: WorktreeFileDescriptor;
			readonly contentDescriptorRef: BridgeDescriptorRef;
	  }
	| {
			readonly kind: 'fileInvalidated';
			readonly invalidation: WorktreeFileInvalidation;
	  }
	| {
			readonly kind: 'reset';
			readonly reason:
				| 'sourceChanged'
				| 'subscriptionReset'
				| 'providerRestart'
				| 'authorityChanged';
			readonly source?: WorktreeFileSurfaceSourceIdentity;
			readonly replacementDescriptorRef?: BridgeDescriptorRef;
	  };

export type ApplyWorktreeFileProtocolFrameResult =
	| {
			readonly ok: true;
			readonly delta: WorktreeFileMaterializerDelta;
	  }
	| {
			readonly ok: false;
			readonly reason: 'invalid_frame' | 'descriptor_rejected' | 'unsupported_frame';
	  };

export interface ApplyWorktreeFileProtocolFrameProps {
	readonly frame: WorktreeFileProtocolFrame;
	readonly paneId: string;
	readonly registry: BridgeResourceDescriptorRegistry;
}

export function applyWorktreeFileProtocolFrame(
	props: ApplyWorktreeFileProtocolFrameProps,
): ApplyWorktreeFileProtocolFrameResult {
	const parsedFrame = worktreeFileProtocolFrameSchema.safeParse(props.frame);
	if (!parsedFrame.success) {
		return { ok: false, reason: 'invalid_frame' };
	}
	const frame = parsedFrame.data;
	switch (frame.frameKind) {
		case 'worktree.snapshot':
			return applySnapshotFrame({ frame, registry: props.registry });
		case 'worktree.treeWindow':
			return {
				ok: true,
				delta: {
					kind: 'treeWindow',
					...(frame.treeSizeFacts === undefined ? {} : { treeSizeFacts: frame.treeSizeFacts }),
				},
			};
		case 'worktree.treeDelta':
			return {
				ok: true,
				delta: {
					kind: 'treeDelta',
					operations: frame.operations,
				},
			};
		case 'worktree.statusPatch':
			return {
				ok: true,
				delta: {
					kind: 'statusPatch',
					patch: frame.patch,
				},
			};
		case 'worktree.fileDescriptor':
			return applySingleDescriptorFrame({
				registry: props.registry,
				attachedDescriptor: frame.descriptor.contentDescriptor,
				makeDelta: (descriptorRef): WorktreeFileMaterializerDelta => ({
					kind: 'fileDescriptor',
					descriptor: frame.descriptor,
					contentDescriptorRef: descriptorRef,
				}),
			});
		case 'worktree.fileInvalidated':
			return {
				ok: true,
				delta: {
					kind: 'fileInvalidated',
					invalidation: frame.invalidation,
				},
			};
		case 'worktree.reset': {
			if (frame.source !== undefined) {
				props.registry.resetIdentity({
					paneId: props.paneId,
					protocol: 'worktree-file',
					sourceId: frame.source.sourceId,
				});
			}
			if (frame.replacementDescriptor === undefined) {
				return {
					ok: true,
					delta: {
						kind: 'reset',
						reason: frame.reason,
						...(frame.source === undefined ? {} : { source: frame.source }),
					},
				};
			}
			const replacementRegisterResult = props.registry.register(frame.replacementDescriptor);
			if (!replacementRegisterResult.ok) {
				return { ok: false, reason: 'descriptor_rejected' };
			}
			return {
				ok: true,
				delta: {
					kind: 'reset',
					reason: frame.reason,
					...(frame.source === undefined ? {} : { source: frame.source }),
					replacementDescriptorRef: frame.replacementDescriptor.ref,
				},
			};
		}
	}
	return { ok: false, reason: 'unsupported_frame' };
}

function applySnapshotFrame(props: {
	readonly frame: Extract<WorktreeFileProtocolFrame, { readonly frameKind: 'worktree.snapshot' }>;
	readonly registry: BridgeResourceDescriptorRegistry;
}): ApplyWorktreeFileProtocolFrameResult {
	return {
		ok: true,
		delta: {
			kind: 'snapshot',
			source: props.frame.source,
			...(props.frame.treeSizeFacts === undefined
				? {}
				: { treeSizeFacts: props.frame.treeSizeFacts }),
		},
	};
}

function applySingleDescriptorFrame(props: {
	readonly registry: BridgeResourceDescriptorRegistry;
	readonly attachedDescriptor: BridgeAttachedResourceDescriptor;
	readonly makeDelta: (descriptorRef: BridgeDescriptorRef) => WorktreeFileMaterializerDelta;
}): ApplyWorktreeFileProtocolFrameResult {
	const registerResult = props.registry.register(props.attachedDescriptor);
	if (!registerResult.ok) {
		return { ok: false, reason: 'descriptor_rejected' };
	}
	return {
		ok: true,
		delta: props.makeDelta(props.attachedDescriptor.ref),
	};
}
