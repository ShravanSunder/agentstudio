import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

import {
	buildReviewContentRouteDeltaProof,
	normalizeReviewTreeSearchQuery,
	reviewCollapseControlSatisfied,
	reviewContentRouteDeltaSatisfied,
	reviewRenderedSelectionSatisfied,
	reviewRouteCollapseControlArtifactSatisfied,
	selectVisibleReviewCollapseControlProof,
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

	test('publishes visible CodeView collapse-control primitive proof in Review route artifacts', async () => {
		const verifierSource = await readFile(verifierSourceUrl, 'utf8');

		expect(verifierSource).toContain('reviewCollapseControlProof');
		expect(verifierSource).toContain('readReviewCollapseControlProof');
		expect(verifierSource).toContain('reviewRouteCollapseControlArtifactSatisfied');
		expect(
			reviewRouteCollapseControlArtifactSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				routeProof: {
					reviewCollapseControlProof: {
						ariaExpanded: 'true',
						fontSize: '13px',
						height: 24,
						itemId: 'worktree-review-gitignore',
						present: true,
						primitiveSlot: 'button',
					},
				},
			}),
		).toBe(true);
		expect(
			reviewRouteCollapseControlArtifactSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				routeProof: {},
			}),
		).toBe(false);
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

	test('requires the visible Review CodeView collapse control to use compact Button primitive chrome', () => {
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof: {
					ariaExpanded: 'true',
					fontSize: '11px',
					height: 24,
					itemId: 'worktree-review-gitignore',
					present: true,
					primitiveSlot: 'button',
				},
			}),
		).toBe(true);
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof: {
					ariaExpanded: 'true',
					fontSize: '11px',
					height: 24,
					itemId: 'worktree-review-gitignore',
					present: true,
					primitiveSlot: null,
				},
			}),
		).toBe(false);
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof: {
					ariaExpanded: 'true',
					fontSize: '11px',
					height: 28,
					itemId: 'worktree-review-gitignore',
					present: true,
					primitiveSlot: 'button',
				},
			}),
		).toBe(false);
	});

	test('selects visible Review CodeView collapse-control proof over hidden stale matches', () => {
		const proof = selectVisibleReviewCollapseControlProof({
			expectedItemId: 'worktree-review-gitignore',
			candidates: [
				{
					visible: false,
					proof: {
						ariaExpanded: 'true',
						fontSize: '13px',
						height: 24,
						itemId: 'worktree-review-gitignore',
						present: true,
						primitiveSlot: 'button',
					},
				},
				{
					visible: true,
					proof: {
						ariaExpanded: 'true',
						fontSize: '13px',
						height: 28,
						itemId: 'worktree-review-gitignore',
						present: true,
						primitiveSlot: 'button',
					},
				},
			],
		});

		expect(proof.height).toBe(28);
		expect(
			reviewCollapseControlSatisfied({
				expectedItemId: 'worktree-review-gitignore',
				proof,
			}),
		).toBe(false);
		expect(
			selectVisibleReviewCollapseControlProof({
				expectedItemId: 'worktree-review-gitignore',
				candidates: [
					{
						visible: false,
						proof: {
							ariaExpanded: 'true',
							fontSize: '13px',
							height: 24,
							itemId: 'worktree-review-gitignore',
							present: true,
							primitiveSlot: 'button',
						},
					},
				],
			}),
		).toEqual({
			ariaExpanded: null,
			fontSize: null,
			height: 0,
			itemId: null,
			present: false,
			primitiveSlot: null,
		});
	});
});
