import type { ReactElement } from 'react';

export function WorktreeFileApp(): ReactElement {
	return (
		<main className="bridge-worktree-file-app" data-testid="worktree-file-app">
			<section className="bridge-worktree-file-tree" data-testid="worktree-file-tree" />
			<section className="bridge-worktree-file-content" data-testid="worktree-file-content" />
		</main>
	);
}
