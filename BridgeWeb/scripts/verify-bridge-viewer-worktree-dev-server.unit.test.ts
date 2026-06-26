import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import {
	buildReviewContentRouteDeltaProof,
	normalizeReviewTreeSearchQuery,
	reviewContentRouteDeltaSatisfied,
	reviewRenderedSelectionSatisfied,
} from './verify-bridge-viewer-worktree-review-proof.ts';

const verifierSourceUrl = new URL('./verify-bridge-viewer-worktree-dev-server.ts', import.meta.url);

describe('worktree dev-server verifier Review interaction contract', () => {
	test('uses visible Pierre tree search interaction for Review selection proof', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).not.toContain('__bridge_select_review_item');
		expect(verifierSource).not.toContain('document.dispatchEvent');
		expect(verifierSource).toContain('clickReviewTreeFilePathViaSearch');
		expect(verifierSource).toContain('[data-testid="bridge-review-trees-panel"]');
		expect(verifierSource).toContain('[data-file-tree-search-input]');
	});

	test('normalizes Review tree search query while preserving clicked row path proof', () => {
		expect(normalizeReviewTreeSearchQuery('Sources/AgentStudio/AtomRegistry.swift')).toBe(
			'sources/agentstudio/atomregistry.swift',
		);
	});

	test('does not count pre-click Review content routes as click proof', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-other-head',
			],
			beforeHitCount: 2,
			expectedItemId: 'worktree-review-missing-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(false);
		expect(proof.matchingPreClickHitUrls).toEqual([]);
		expect(proof.matchingPostClickHitUrls).toEqual([]);
	});

	test('accepts pre-click selected content route only as rendered-selection evidence', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-other-head',
			],
			beforeHitCount: 2,
			expectedItemId: 'worktree-review-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(true);
		expect(proof.contentRouteSatisfiedBy).toBe('matching-pre-click-route-with-rendered-selection');
		expect(proof.matchingPreClickHitUrls).toEqual([
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
		]);
		expect(proof.matchingPostClickHitUrls).toEqual([]);
	});

	test('requires a post-click Review content route for the clicked item', () => {
		const proof = buildReviewContentRouteDeltaProof({
			allHitUrls: [
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-other-head',
				'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-base',
			],
			beforeHitCount: 2,
			expectedItemId: 'worktree-review-target',
		});

		expect(reviewContentRouteDeltaSatisfied(proof)).toBe(true);
		expect(proof.contentRouteSatisfiedBy).toBe('matching-post-click-route');
		expect(proof.matchingPostClickHitUrls).toEqual([
			'http://127.0.0.1:5173/__bridge-worktree/review-content/worktree-review-target-base',
		]);
	});

	test('requires clicked item materialization in the visible Review CodeView canvas', () => {
		expect(
			reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: 'worktree-review-gitignore',
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: '# Xcode',
				},
				snapshot: {
					codeViewOverflow: 'wrap',
					selectedHeaderPresent: true,
					selectedItemId: 'worktree-review-gitignore',
					selectedMaterializedFileLineCount: 0,
					selectedMaterializedItemType: 'diff',
					visibleText: '# Xcode\n*.xcodeproj\n',
				},
			}),
		).toBe(true);
		expect(
			reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: 'worktree-review-gitignore',
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: '# Xcode',
				},
				snapshot: {
					codeViewOverflow: 'wrap',
					selectedHeaderPresent: false,
					selectedItemId: 'worktree-review-gitignore',
					selectedMaterializedFileLineCount: 0,
					selectedMaterializedItemType: 'diff',
					visibleText: 'name: CI / Test',
				},
			}),
		).toBe(false);
		expect(
			reviewRenderedSelectionSatisfied({
				expectation: {
					expectedCodeViewOverflow: 'wrap',
					expectedItemId: 'worktree-review-gitignore',
					expectedMaterializedItemType: 'diff',
					expectedVisibleText: '# Xcode',
				},
				snapshot: {
					codeViewOverflow: 'scroll',
					selectedHeaderPresent: true,
					selectedItemId: 'worktree-review-gitignore',
					selectedMaterializedFileLineCount: 0,
					selectedMaterializedItemType: 'diff',
					visibleText: '# Xcode\n*.xcodeproj\n',
				},
			}),
		).toBe(false);
	});
});
