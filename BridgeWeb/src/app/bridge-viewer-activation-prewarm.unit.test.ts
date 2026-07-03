import { describe, expect, test, vi } from 'vitest';

import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	bridgePierrePrewarmLanguagesForReviewPackage,
	bridgeViewerActivationPrewarm,
	type BridgeViewerActivationPrewarmState,
} from './bridge-viewer-activation-prewarm.js';

describe('Bridge viewer activation prewarm', () => {
	test('fires one Pierre worker prewarm per active viewer mode activation', () => {
		const prewarm = vi.fn<() => void>();
		const state: BridgeViewerActivationPrewarmState = { prewarmedModes: new Set() };

		bridgeViewerActivationPrewarm({
			activeViewerMode: 'review',
			prewarm,
			state,
		});
		bridgeViewerActivationPrewarm({
			activeViewerMode: 'review',
			prewarm,
			state,
		});
		bridgeViewerActivationPrewarm({
			activeViewerMode: 'file',
			prewarm,
			state,
		});

		expect(prewarm).toHaveBeenCalledTimes(2);
		expect(prewarm.mock.calls).toEqual([
			[{ languages: ['typescript', 'tsx', 'swift', 'markdown', 'json', 'yaml'] }],
			[{ languages: ['typescript', 'tsx', 'swift', 'markdown', 'json', 'yaml'] }],
		]);
	});

	test('chooses dominant review package languages before falling back to static grammars', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const tsItem = {
			...makeBridgeReviewItem({
				itemId: 'item-ts',
				path: 'BridgeWeb/src/app.ts',
			}),
			language: 'typescript',
			extension: 'ts',
		};
		const markdownItem = {
			...makeBridgeReviewItem({
				itemId: 'item-md',
				path: 'docs/plan.md',
			}),
			fileClass: 'docs' as const,
			language: 'markdown',
			extension: 'md',
		};

		expect(
			bridgePierrePrewarmLanguagesForReviewPackage({
				...reviewPackage,
				orderedItemIds: ['item-ts', 'item-md', 'item-source'],
				itemsById: {
					...reviewPackage.itemsById,
					[tsItem.itemId]: tsItem,
					[markdownItem.itemId]: markdownItem,
				},
			}),
		).toEqual(['typescript', 'swift', 'markdown']);
	});

	test('prewarms supported review package languages and skips plaintext fallbacks', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const packageJsonItem = {
			...makeBridgeReviewItem({
				itemId: 'item-package-json',
				path: 'package.json',
			}),
			language: 'json',
			extension: 'json',
		};
		const miseTomlItem = {
			...makeBridgeReviewItem({
				itemId: 'item-mise-toml',
				path: '.mise.toml',
			}),
			fileClass: 'config' as const,
			language: 'toml',
			extension: 'toml',
		};
		const gitignoreItem = {
			...makeBridgeReviewItem({
				itemId: 'item-gitignore',
				path: '.gitignore',
			}),
			fileClass: 'config' as const,
			language: 'gitignore',
			extension: '',
		};

		expect(
			bridgePierrePrewarmLanguagesForReviewPackage({
				...reviewPackage,
				orderedItemIds: ['item-mise-toml', 'item-package-json', 'item-gitignore'],
				itemsById: {
					[packageJsonItem.itemId]: packageJsonItem,
					[miseTomlItem.itemId]: miseTomlItem,
					[gitignoreItem.itemId]: gitignoreItem,
				},
			}),
		).toEqual(['json', 'toml']);
	});
});
