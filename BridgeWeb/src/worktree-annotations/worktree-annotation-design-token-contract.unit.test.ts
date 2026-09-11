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
	'active-surface',
	'composer-bg',
	'destructive',
	'status-new',
	'status-pending',
] as const;

describe('worktree annotation design-token contract', () => {
	test('registers the complete annotation context as canonical Tailwind utilities', async () => {
		const appCss = await readFile(new URL('../app/bridge-app.css', import.meta.url), 'utf8');
		const themeBlock = appCss.match(/@theme inline \{(?<body>[\s\S]*?)\n\}/u)?.groups?.['body'];

		expect(themeBlock).toBeDefined();
		for (const tokenName of commentColorTokenNames) {
			expect(themeBlock).toContain(
				`--color-annotation-${tokenName}: var(--annotation-${tokenName});`,
			);
		}
	});
});
