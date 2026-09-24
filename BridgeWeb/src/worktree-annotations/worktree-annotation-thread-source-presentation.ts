import type { WorktreeAnnotationProjectionSnapshot } from './worktree-annotation-surface-client.js';

/** Where a thread is anchored: a file path and the descriptor identity of its source. */
export interface WorktreeAnnotationThreadSource {
	readonly path: string;
	readonly sourceIdentity: string;
}

/**
 * Maps a thread's stored worktree-relative source to the path and descriptor
 * identity the surface lists that file under, or null when the surface does
 * not list it.
 */
export type WorktreeAnnotationThreadSourcePresenter = (
	worktreeId: string,
	storedSource: WorktreeAnnotationThreadSource,
) => WorktreeAnnotationThreadSource | null;

/**
 * Present a projection's threads under the surface's own keys.
 *
 * Stored annotation sources stay worktree-scoped: a worktree-relative path and
 * the member's own descriptor identity. A surface whose keys differ (the Files
 * collection lists each member under its group and prefixes its descriptor
 * identities) receives every server and command-confirmed thread already
 * mapped, so no consumer compares a worktree-scoped value against a display
 * key. A thread the surface does not list is withheld rather than kept under a
 * value that could equal some other file's key.
 */
export function presentWorktreeAnnotationThreadSources(
	snapshot: WorktreeAnnotationProjectionSnapshot,
	presentThreadSource: WorktreeAnnotationThreadSourcePresenter,
): WorktreeAnnotationProjectionSnapshot {
	const worktreeId = snapshot.worktreeId;
	return {
		...snapshot,
		commandConfirmedThreads: presentThreads(
			snapshot.commandConfirmedThreads,
			worktreeId,
			presentThreadSource,
		),
		threads: presentThreads(snapshot.threads, worktreeId, presentThreadSource),
	};
}

function presentThreads<TThread extends { readonly context: WorktreeAnnotationThreadSource }>(
	threads: readonly TThread[],
	worktreeId: string | null,
	presentThreadSource: WorktreeAnnotationThreadSourcePresenter,
): readonly TThread[] {
	if (threads.length === 0) return threads;
	if (worktreeId === null) return [];
	return threads.flatMap((thread): readonly TThread[] => {
		const presented = presentThreadSource(worktreeId, thread.context);
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
