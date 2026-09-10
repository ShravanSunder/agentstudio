import { readFile } from 'node:fs/promises';

import { expect, test } from 'vitest';

test('keeps the customized Tailwind scale equal to native AppStyles typography conventions', async () => {
	const [native, css] = await Promise.all([
		readFile(
			new URL('../../../Sources/AgentStudio/Infrastructure/AppStyles.swift', import.meta.url),
			'utf8',
		),
		readFile(new URL('../app/bridge-app.css', import.meta.url), 'utf8'),
	]);
	const roles = [
		['textXxs', '2xs'],
		['textXs', 'xs'],
		['textSm', 'sm'],
		['textBase', 'base'],
		['textLg', 'lg'],
		['textXl', 'xl'],
		['text2xl', '2xl'],
	] as const;
	for (const [nativeName, webName] of roles) {
		const nativeValue = native.match(new RegExp(`static let ${nativeName}: CGFloat = (\\d+)`))?.[1];
		const webValue = css.match(new RegExp(`--text-${webName}: (\\d+)px`))?.[1];
		expect(nativeValue, nativeName).toBeDefined();
		expect(webValue, webName).toBe(nativeValue);
	}
});
