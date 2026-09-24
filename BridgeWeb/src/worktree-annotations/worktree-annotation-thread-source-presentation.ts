import type { BridgeProductWorktreeAnnotationSubject } from '../core/comm-worker/bridge-product-worktree-annotation-contracts.js';
import type { WorktreeAnnotationProjectionSnapshot } from './worktree-annotation-surface-client.js';

/** Where a thread is anchored: a file path and the descriptor identity of its source. */
export interface WorktreeAnnotationThreadSource {
	readonly path: string;
	readonly sourceIdentity: string;
}

/**
 * Maps a thread's stored source, read inside its session's subject, to the
 * path and descriptor identity the surface lists that file under, or null when
 * the surface does not list it.
 */
export type WorktreeAnnotationThreadSourcePresenter = (
	subject: BridgeProductWorktreeAnnotationSubject,
	storedSource: WorktreeAnnotationThreadSource,
) => WorktreeAnnotationThreadSource | null;

/**
 * Present a projection's threads under the surface's own keys.
 *
 * Stored annotation sources stay subject-scoped: a worktree-relative path and
 * the member's own descriptor identity, or a local document's name and its own
 * descriptor identity. A surface whose keys differ (the Files collection lists
 * each member under its group, each loose document under Open Files, and
 * prefixes their descriptor identities) receives every server and
 * command-confirmed thread already mapped, so no consumer compares a stored
 * value against a display key. A thread the surface does not list is withheld
 * rather than kept under a value that could equal some other file's key.
 */
export function presentWorktreeAnnotationThreadSources(
	snapshot: WorktreeAnnotationProjectionSnapshot,
	presentThreadSource: WorktreeAnnotationThreadSourcePresenter,
): WorktreeAnnotationProjectionSnapshot {
	return {
		...snapshot,
		commandConfirmedThreads: presentThreads(snapshot.commandConfirmedThreads, presentThreadSource),
		threads: presentThreads(snapshot.threads, presentThreadSource),
	};
}

function presentThreads<
	TThread extends {
		readonly context: WorktreeAnnotationThreadSource & {
			readonly subject: BridgeProductWorktreeAnnotationSubject;
		};
	},
>(
	threads: readonly TThread[],
	presentThreadSource: WorktreeAnnotationThreadSourcePresenter,
): readonly TThread[] {
	if (threads.length === 0) return threads;
	return threads.flatMap((thread): readonly TThread[] => {
		const presented = presentThreadSource(thread.context.subject, thread.context);
		return presented === null
			? []
			: [
					{
						...thread,
						context: {
							...thread.context,
							path: presented.path,
							sourceIdentity: presented.sourceIdentity,
						},
					},
				];
	});
}
