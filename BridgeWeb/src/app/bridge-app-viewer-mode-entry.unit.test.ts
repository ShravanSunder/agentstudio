import { existsSync, readFileSync } from 'node:fs';

import { describe, expect, test } from 'vitest';

interface SourceFileSnapshot {
	readonly exists: boolean;
	readonly source: string;
}

describe('BridgeApp viewer mode entries', () => {
	test('keeps the File entry independent from Review application modules', () => {
		// Arrange
		const fileEntry = readOptionalSource('./bridge-app-file-viewer-mode-entry.ts');

		// Act
		const forbiddenReviewDependencies = [
			'bridge-app-review-viewer-mode',
			'review-viewer-shell',
		] as const;
		const retainedReviewDependencies = forbiddenReviewDependencies.filter((dependency): boolean =>
			fileEntry.source.includes(dependency),
		);

		// Assert
		expect(fileEntry.exists).toBe(true);
		expect(fileEntry.source).toContain("from './bridge-app-file-viewer-mode.js'");
		expect(fileEntry.source).toContain('modeComponent: BridgeFileViewerMode');
		expect(retainedReviewDependencies).toEqual([]);
	});

	test('makes the Review mode and shell one resolved application entry', () => {
		// Arrange
		const reviewEntry = readOptionalSource('./bridge-app-review-viewer-mode-entry.ts');

		// Act
		const requiredEntryDependencies = [
			"from '../review-viewer/shell/review-viewer-shell.js'",
			"from './bridge-app-review-viewer-mode.js'",
			'modeComponent: BridgeReviewViewerMode',
			'shellBarrierComponent: ReviewViewerShell',
		] as const;
		const missingEntryDependencies = requiredEntryDependencies.filter(
			(dependency): boolean => !reviewEntry.source.includes(dependency),
		);

		// Assert
		expect(reviewEntry.exists).toBe(true);
		expect(missingEntryDependencies).toEqual([]);
	});

	test('keeps mode entries free of runtime and transport ownership', () => {
		// Arrange
		const entrySources = [
			readOptionalSource('./bridge-app-file-viewer-mode-entry.ts'),
			readOptionalSource('./bridge-app-review-viewer-mode-entry.ts'),
		];

		// Act
		const forbiddenOwnershipTokens = [
			'createBridgePaneRuntime',
			'bridge-pane-runtime',
			'bridge-comm-worker',
			'BridgePaneSurfaceClient',
		] as const;
		const violations = entrySources.flatMap((entry, entryIndex): readonly string[] =>
			forbiddenOwnershipTokens
				.filter((token): boolean => entry.source.includes(token))
				.map((token): string => `entry ${entryIndex}: ${token}`),
		);

		// Assert
		expect(violations).toEqual([]);
	});
});

function readOptionalSource(relativePath: string): SourceFileSnapshot {
	const sourceUrl = new URL(relativePath, import.meta.url);
	return {
		exists: existsSync(sourceUrl),
		source: existsSync(sourceUrl) ? readFileSync(sourceUrl, 'utf8') : '',
	};
}
