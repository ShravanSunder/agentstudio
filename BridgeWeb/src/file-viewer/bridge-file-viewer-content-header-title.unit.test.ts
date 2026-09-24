import { describe, expect, it } from 'vitest';

import { bridgeFileViewerContentHeaderTitle } from './bridge-file-viewer-content-header-title.js';

describe('bridgeFileViewerContentHeaderTitle', () => {
	it('shows only user-facing file context and never the transport source id', () => {
		const title = bridgeFileViewerContentHeaderTitle({
			selectedDocumentLocation: null,
			selectedPath: '.gitignore',
			sourceId: 'pane-companion-uuid-worktree-uuid-1',
		});

		expect(title).toBe('.gitignore');
		expect(title).not.toContain('pane-companion-uuid');
		expect(title).not.toContain('worktree-uuid');
	});

	it('titles an opened document by its real location, not its collection group path', () => {
		expect(
			bridgeFileViewerContentHeaderTitle({
				selectedDocumentLocation: '/private/tmp/notes.md',
				selectedPath: 'Open Files/notes.md',
				sourceId: 'collection-source-1',
			}),
		).toBe('/private/tmp/notes.md');
	});

	it('uses a neutral pending title before a file is selected', () => {
		expect(
			bridgeFileViewerContentHeaderTitle({
				selectedDocumentLocation: null,
				selectedPath: null,
				sourceId: 'pane-companion-uuid-worktree-uuid-1',
			}),
		).toBe('Source pending');
	});
});
