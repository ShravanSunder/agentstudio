/** Optimistic stale policy (user requirement, 2026-07-02): when the open
 * file's content changes underneath the viewer, apply the update silently —
 * a "Content changed / Refresh" prompt is justified only when the user has
 * something to lose on the old content, i.e. an open comment box or a
 * partially-entered comment draft. */
export interface BridgeFileViewerStaleRefreshPolicyProps {
	readonly hasActiveCommentDraft: boolean;
}

export function shouldSuppressStaleOpenFileNotice(
	props: BridgeFileViewerStaleRefreshPolicyProps,
): boolean {
	return !props.hasActiveCommentDraft;
}

/** Pierre comments are not integrated yet, so no surface can host a draft;
 * when comment anchoring lands this becomes a live per-file predicate and
 * the stale prompt re-enables itself for files with drafts. */
export const bridgeFileViewerHasActiveCommentDraft = false;
