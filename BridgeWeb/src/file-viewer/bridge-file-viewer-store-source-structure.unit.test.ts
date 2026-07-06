import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Bridge file viewer store source structure', () => {
	test('keeps File View off direct Zustand subscriptions after direct store removal', () => {
		const forbiddenTokens = [
			"from 'zustand",
			'from "zustand',
			'useStore(',
			'useStoreWithEqualityFn(',
			'createStore(',
			'createWithEqualityFn(',
			'subscribeWithSelector',
		];
		const violations = readFileViewerProductionSources().flatMap((entry): readonly string[] =>
			forbiddenTokens
				.filter((token): boolean => entry.source.includes(token))
				.map((token): string => `${entry.relativePath}: ${token}`),
		);

		expect(violations).toEqual([]);
	});
});

interface SourceFileEntry {
	readonly relativePath: string;
	readonly source: string;
}

function readFileViewerProductionSources(): readonly SourceFileEntry[] {
	const sourceDirectory = fileURLToPath(new URL('../', import.meta.url));
	const fileViewerSources = readSourceFilesInDirectory({
		absoluteDirectory: join(sourceDirectory, 'file-viewer'),
		relativeDirectory: 'file-viewer',
	});
	const appFileViewerSources = readSourceFilesInDirectory({
		absoluteDirectory: join(sourceDirectory, 'app'),
		relativeDirectory: 'app',
	}).filter((entry): boolean => entry.relativePath.includes('file-viewer'));
	return [...fileViewerSources, ...appFileViewerSources];
}

function readSourceFilesInDirectory(props: {
	readonly absoluteDirectory: string;
	readonly relativeDirectory: string;
}): readonly SourceFileEntry[] {
	return readdirSync(props.absoluteDirectory, { withFileTypes: true }).flatMap((entry) => {
		const relativePath =
			props.relativeDirectory.length === 0
				? entry.name
				: `${props.relativeDirectory}/${entry.name}`;
		const absolutePath = join(props.absoluteDirectory, entry.name);
		if (entry.isDirectory()) {
			return readSourceFilesInDirectory({
				absoluteDirectory: absolutePath,
				relativeDirectory: relativePath,
			});
		}
		if (
			!entry.isFile() ||
			(!entry.name.endsWith('.ts') && !entry.name.endsWith('.tsx')) ||
			entry.name.includes('.test.') ||
			entry.name.includes('.browser.')
		) {
			return [];
		}
		return [
			{
				relativePath,
				source: readFileSync(absolutePath, 'utf8'),
			},
		];
	});
}
