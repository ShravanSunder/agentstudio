import { basename } from 'node:path';

/**
 * The File viewer lists a worktree's files under the worktree folder's name,
 * as the app's multi-root file collection does. Review paths and product URL
 * `path=` targets stay worktree-relative.
 */
export function bridgeViewerViteFileCollectionPath(
	worktreeRoot: string,
	relativePath: string,
): string {
	return `${basename(worktreeRoot)}/${relativePath}`;
}
