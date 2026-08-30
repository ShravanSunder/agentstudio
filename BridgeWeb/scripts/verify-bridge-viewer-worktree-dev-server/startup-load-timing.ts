import type { Page } from 'playwright';

import {
	summarizeInteractionSamples,
	type ReviewStartupLoadTimingProof,
	type WorktreeStartupLoadTimingProof,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import { worktreeReviewDevServerUrl } from './config.ts';
import { navigateToWorktreeDevServerFileShell } from './page-shell.ts';
import {
	waitForAnyWorktreeSelectedPathTiming,
	waitForWorktreeFirstVisibleContentWindow,
	waitForWorktreeMetadataMilliseconds,
	waitForWorktreeOpenFileReadyMilliseconds,
	waitForWorktreeSourceAcceptedMilliseconds,
} from './performance-click-waits.ts';
import { waitForAnyReviewSelectedContentState } from './review-tree-click.ts';
import { observeWorktreeFileContentRouteTiming } from './startup-route-timing.ts';

interface WorktreeStartupTimingSample {
	readonly contentReadyMilliseconds: number;
	readonly contentRequestStartedMilliseconds: number;
	readonly contentResponseStartedMilliseconds: number;
	readonly firstVisibleContentWindowMilliseconds: number;
	readonly metadataMilliseconds: number;
	readonly selectedPathMilliseconds: number;
	readonly shellMountedMilliseconds: number;
	readonly sourceAcceptedMilliseconds: number;
}

interface ReviewStartupTimingSample {
	readonly metadataMilliseconds: number;
	readonly selectedContentReadyMilliseconds: number;
}

export async function collectWorktreeStartupLoadTimingProof(props: {
	readonly page: Page;
}): Promise<WorktreeStartupLoadTimingProof> {
	const sample = await collectWorktreeStartupTimingSample(props.page);
	return {
		pageLoadToContentReady: summarizeInteractionSamples([sample.contentReadyMilliseconds]),
		pageLoadToContentRequestStarted: summarizeInteractionSamples([
			sample.contentRequestStartedMilliseconds,
		]),
		pageLoadToContentResponseStarted: summarizeInteractionSamples([
			sample.contentResponseStartedMilliseconds,
		]),
		pageLoadToFirstVisibleContentWindow: summarizeInteractionSamples([
			sample.firstVisibleContentWindowMilliseconds,
		]),
		pageLoadToMetadata: summarizeInteractionSamples([sample.metadataMilliseconds]),
		pageLoadToSelectedPath: summarizeInteractionSamples([sample.selectedPathMilliseconds]),
		pageLoadToShellMounted: summarizeInteractionSamples([sample.shellMountedMilliseconds]),
		pageLoadToSourceAccepted: summarizeInteractionSamples([sample.sourceAcceptedMilliseconds]),
	};
}

export async function collectReviewStartupLoadTimingProof(props: {
	readonly page: Page;
}): Promise<ReviewStartupLoadTimingProof> {
	const sample = await collectReviewStartupTimingSample(props.page);
	return {
		pageLoadToMetadata: summarizeInteractionSamples([sample.metadataMilliseconds]),
		pageLoadToSelectedContentReady: summarizeInteractionSamples([
			sample.selectedContentReadyMilliseconds,
		]),
	};
}

async function collectWorktreeStartupTimingSample(
	page: Page,
): Promise<WorktreeStartupTimingSample> {
	const pageLoadStartedAt = performance.now();
	const contentRouteTiming = observeWorktreeFileContentRouteTiming({
		page,
		startedAt: pageLoadStartedAt,
		timeoutMilliseconds: 20_000,
	});
	await navigateToWorktreeDevServerFileShell(page);
	const shellMountedMilliseconds = Math.max(0, performance.now() - pageLoadStartedAt);
	const sourceAcceptedMilliseconds = await waitForWorktreeSourceAcceptedMilliseconds({
		page,
		startedAt: pageLoadStartedAt,
		timeoutMilliseconds: 20_000,
	});
	const metadataMilliseconds = await waitForWorktreeMetadataMilliseconds({
		page,
		startedAt: pageLoadStartedAt,
		timeoutMilliseconds: 20_000,
	});
	const selectedPathTiming = await waitForAnyWorktreeSelectedPathTiming({
		page,
		startedAt: pageLoadStartedAt,
		timeoutMilliseconds: 20_000,
	});
	const [contentRequestStartedMilliseconds, contentResponseStartedMilliseconds] = await Promise.all(
		[contentRouteTiming.requestStartedMilliseconds, contentRouteTiming.responseStartedMilliseconds],
	);
	const contentReadyMilliseconds = await waitForWorktreeOpenFileReadyMilliseconds({
		page,
		path: selectedPathTiming.path,
		startedAt: pageLoadStartedAt,
		timeoutMilliseconds: 20_000,
	});
	await waitForWorktreeFirstVisibleContentWindow({
		page,
		path: selectedPathTiming.path,
		timeoutMilliseconds: 20_000,
	});
	return {
		contentReadyMilliseconds,
		contentRequestStartedMilliseconds,
		contentResponseStartedMilliseconds,
		firstVisibleContentWindowMilliseconds: Math.max(0, performance.now() - pageLoadStartedAt),
		metadataMilliseconds,
		selectedPathMilliseconds: selectedPathTiming.selectedPathMilliseconds,
		shellMountedMilliseconds,
		sourceAcceptedMilliseconds,
	};
}

async function collectReviewStartupTimingSample(page: Page): Promise<ReviewStartupTimingSample> {
	const pageLoadStartedAt = performance.now();
	await page.goto(worktreeReviewDevServerUrl, {
		waitUntil: 'domcontentloaded',
		timeout: 30_000,
	});
	await page.waitForSelector('[data-testid="review-viewer-shell"]', { timeout: 30_000 });
	await page.waitForFunction(
		(): boolean => {
			const shell = document.querySelector('[data-testid="review-viewer-shell"]');
			return Number(shell?.getAttribute('data-review-metadata-item-count') ?? '0') > 0;
		},
		undefined,
		{ timeout: 30_000 },
	);
	const metadataMilliseconds = Math.max(0, performance.now() - pageLoadStartedAt);
	await waitForAnyReviewSelectedContentState({ page, state: 'ready' });
	return {
		metadataMilliseconds,
		selectedContentReadyMilliseconds: Math.max(0, performance.now() - pageLoadStartedAt),
	};
}
