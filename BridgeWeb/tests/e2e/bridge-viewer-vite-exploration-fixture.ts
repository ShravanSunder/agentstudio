import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import { createBridgeViewerViteProductFixture } from './bridge-viewer-vite-product-fixture.ts';

export async function createBridgeViewerExplorationFixture(): Promise<
	Awaited<ReturnType<typeof createBridgeViewerViteProductFixture>> & {
		readonly markdownPaths: readonly string[];
		readonly editMarkdown: () => Promise<void>;
		readonly addMarkdown: () => Promise<string>;
	}
> {
	const fixture = await createBridgeViewerViteProductFixture();
	const markdownPaths = ['README.md', 'docs/guide.md', 'docs/diagram.md', 'docs/UPPERCASE.MD'];
	let revision = 1;
	try {
		await mkdir(join(fixture.oracle.worktreeRoot, 'docs'), { recursive: true });
		await Promise.all(
			markdownPaths.map(async (path): Promise<void> => {
				await writeFile(join(fixture.oracle.worktreeRoot, path), markdownBody(path, revision));
			}),
		);
		return {
			...fixture,
			markdownPaths,
			editMarkdown: async (): Promise<void> => {
				revision += 1;
				await writeFile(
					join(fixture.oracle.worktreeRoot, 'docs/guide.md'),
					markdownBody('docs/guide.md', revision),
				);
			},
			addMarkdown: async (): Promise<string> => {
				const path = 'docs/new-during-session.md';
				await writeFile(join(fixture.oracle.worktreeRoot, path), markdownBody(path, revision));
				return path;
			},
		};
	} catch (error: unknown) {
		await fixture.dispose();
		throw error;
	}
}

function markdownBody(path: string, revision: number): string {
	return [
		`# Exploration ${path}`,
		'',
		`Document revision ${revision}.`,
		'',
		...Array.from(
			{ length: path === 'docs/guide.md' ? 80 : 4 },
			(_, index): string =>
				`## Section ${index + 1}\n\nStable paragraph ${index + 1}. The reader should keep their position during updates.\n`,
		),
		'```mermaid',
		'flowchart LR',
		'Backend --> Worker --> Viewer',
		'```',
		'',
	].join('\n');
}
