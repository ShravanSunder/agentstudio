import { realpathSync } from 'node:fs';
import { basename } from 'node:path';

/**
 * The File viewer lists a worktree's files under the name of the worktree's
 * canonical root directory, as the dev host's multi-root file collection does.
 * Only File-surface keys take this form: File tree rows, File open/rendered/
 * selected paths, and File metadata descriptor paths. Review paths, dev URL
 * `path=` targets, and on-disk fixture paths stay worktree-relative.
 */
export function worktreeFileCollectionPath(worktreeRootPath: string, relativePath: string): string {
	return `${basename(realpathSync(worktreeRootPath))}/${relativePath}`;
}
