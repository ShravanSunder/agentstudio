import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

const commentColorTokenNames = [
	'surface',
	'foreground',
	'muted',
	'border',
	'divider',
	'hover',
	'active',
	'composer-bg',
	'destructive',
] as const;

describe('worktree annotation design-token contract', () => {
	test('registers every frozen comment context color as a Tailwind utility', async () => {
		const appCss = await readFile(new URL('../app/bridge-app.css', import.meta.url), 'utf8');
		const themeBlock = appCss.match(/@theme inline \{(?<body>[\s\S]*?)\n\}/u)?.groups?.['body'];

		expect(themeBlock).toBeDefined();
		for (const tokenName of commentColorTokenNames) {
			expect(themeBlock).toContain(`--color-comment-${tokenName}: var(--comment-${tokenName});`);
		}
	});
});
