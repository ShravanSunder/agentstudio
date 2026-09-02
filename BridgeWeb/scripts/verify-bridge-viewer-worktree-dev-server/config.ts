import { execFile } from 'node:child_process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

export const defaultWorktreeDevServerUrl =
	'http://127.0.0.1:5173/?fixture=worktree&viewer=file&workers=on&scenario=current-worktree';

export const repoRootPath = fileURLToPath(new URL('../../..', import.meta.url));

export const proofRootPath =
	process.env['AGENTSTUDIO_BRIDGE_WORKTREE_DEV_SERVER_PROOF_ROOT'] ??
	join(repoRootPath, 'tmp/bridge-viewer-worktree-dev-server');

export const proofRunCreatedAtUnixMilliseconds = Date.now();

export const proofRunDirectoryPath = join(
	proofRootPath,
	timestampForPath(new Date(proofRunCreatedAtUnixMilliseconds)),
);

export const worktreeDevServerUrl = fileModeUrlFromWorktreeDevServerUrl(
	process.env['BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL'] ?? defaultWorktreeDevServerUrl,
);

export const worktreeReviewDevServerUrl =
	reviewModeUrlFromWorktreeDevServerUrl(worktreeDevServerUrl);

export const worktreeDevServerOrigin = new URL(worktreeDevServerUrl).origin;

export const targetPathOverride = process.env['BRIDGE_VIEWER_WORKTREE_TARGET_PATH'] ?? null;

export const performanceOnlyMode = process.env['BRIDGE_VIEWER_WORKTREE_PERFORMANCE_ONLY'] === '1';

export const startupOnlyMode = process.env['BRIDGE_VIEWER_WORKTREE_STARTUP_ONLY'] === '1';

export const completeJourneyMode = process.env['BRIDGE_VIEWER_WORKTREE_COMPLETE_JOURNEY'] === '1';

export const completeJourneyAttemptCount = completeJourneyAttemptCountFromEnvironment(
	process.env['BRIDGE_VIEWER_WORKTREE_COMPLETE_JOURNEY_ATTEMPTS'],
);

export const execFileAsync = promisify(execFile);

function completeJourneyAttemptCountFromEnvironment(rawValue: string | undefined): number {
	if (rawValue === undefined) return 100;
	const parsedValue = Number(rawValue);
	if (!Number.isInteger(parsedValue) || parsedValue <= 0) {
		throw new Error('BRIDGE_VIEWER_WORKTREE_COMPLETE_JOURNEY_ATTEMPTS must be a positive integer.');
	}
	return parsedValue;
}

export const fileToReviewHandoffFixtureRelativePath =
	'BridgeWeb/src/test-fixtures/worktree-file-to-review-handoff-canary.txt';

export const initialContentFixtureRelativePath = fileToReviewHandoffFixtureRelativePath;

export const selectedContentFixtureRelativePath = 'BridgeWeb/scripts/app-asset-contract.ts';

export const reviewSelectionFixtureRelativePath =
	'BridgeWeb/src/test-fixtures/worktree-review-selection-canary.txt';

export const staleRefreshFixtureRelativePath =
	'BridgeWeb/src/test-fixtures/worktree-stale-refresh-canary.txt';

export const splitResetFixtureRelativePath =
	'BridgeWeb/src/test-fixtures/worktree-split-reset-canary.txt';

export const recentlyUpdatedFixtureRelativePath =
	'BridgeWeb/src/test-fixtures/worktree-recently-updated-canary.txt';

export const reviewSelectionFixtureMarker = `bridge_worktree_devserver_review_selection_${proofRunCreatedAtUnixMilliseconds}`;

export const minimumExpectedReviewMetadataRouteHitCount = 2;

export function scenarioNameFromDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	return parsedUrl.searchParams.get('scenario') ?? 'current-worktree';
}

export function fileModeUrlFromWorktreeDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	parsedUrl.searchParams.set('viewer', 'file');
	return parsedUrl.toString();
}

export function reviewModeUrlFromWorktreeDevServerUrl(url: string): string {
	const parsedUrl = new URL(url);
	parsedUrl.searchParams.set('viewer', 'review');
	return parsedUrl.toString();
}

export function timestampForPath(date: Date): string {
	return date.toISOString().replace(/[:.]/gu, '-');
}
