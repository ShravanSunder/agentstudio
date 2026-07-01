import { mkdir, writeFile } from 'node:fs/promises';
import { join, relative } from 'node:path';

import {
	reviewInteractionPerformanceSatisfied,
	worktreeInteractionPerformanceSatisfied,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import {
	execFileAsync,
	proofRunCreatedAtUnixMilliseconds,
	proofRunDirectoryPath,
	repoRootPath,
	reviewSelectionFixtureRelativePath,
	worktreeDevServerUrl,
	worktreeReviewDevServerUrl,
} from './config.ts';
import type {
	WorktreeDevServerPerformanceOnlyResult,
	WorktreeDevServerVerificationResult,
} from './types.ts';
import { reviewFileTargetUrlFromWorktreeDevServerUrl } from './utils.ts';

export async function readCurrentCommitSha(): Promise<string> {
	const { stdout } = await execFileAsync('git', ['rev-parse', 'HEAD'], {
		cwd: repoRootPath,
	});
	return stdout.trim();
}

export function workerModeFromDevServerUrl(url: string): 'on' | 'off' {
	const workerMode = new URL(url).searchParams.get('workers');
	return workerMode === 'off' ? 'off' : 'on';
}

export async function writeWorktreeDevServerProofArtifact(
	result: WorktreeDevServerVerificationResult,
): Promise<string> {
	await mkdir(proofRunDirectoryPath, { recursive: true });
	const proofArtifactPath = join(proofRunDirectoryPath, 'worktree-dev-server-proof.json');
	const proofArtifactDisplayPath = relative(repoRootPath, proofArtifactPath);
	await writeFile(
		proofArtifactPath,
		`${JSON.stringify(
			{
				schemaVersion: 1,
				createdAtUnixMilliseconds: proofRunCreatedAtUnixMilliseconds,
				devServerUrl: worktreeDevServerUrl,
				requiredRouteUrls: worktreeDevServerRequiredRouteUrls(result),
				result: {
					...result,
					proofArtifactPath: proofArtifactDisplayPath,
				},
			},
			null,
			2,
		)}\n`,
	);
	return proofArtifactDisplayPath;
}

export async function writeWorktreeDevServerPerformanceProofArtifact(
	result: WorktreeDevServerPerformanceOnlyResult,
): Promise<string> {
	await mkdir(proofRunDirectoryPath, { recursive: true });
	const proofArtifactPath = join(
		proofRunDirectoryPath,
		'worktree-dev-server-performance-proof.json',
	);
	const proofArtifactDisplayPath = relative(repoRootPath, proofArtifactPath);
	await writeFile(
		proofArtifactPath,
		`${JSON.stringify(
			{
				schemaVersion: 1,
				createdAtUnixMilliseconds: proofRunCreatedAtUnixMilliseconds,
				devServerUrl: worktreeDevServerUrl,
				result: {
					...result,
					proofArtifactPath: proofArtifactDisplayPath,
				},
			},
			null,
			2,
		)}\n`,
	);
	return proofArtifactDisplayPath;
}

export function worktreeDevServerPerformanceConsoleProof(
	result: WorktreeDevServerPerformanceOnlyResult,
	proofArtifactPath: string,
): Record<string, unknown> {
	return {
		ok: true,
		devServerUrl: worktreeDevServerUrl,
		observedPageUrl: result.observedPageUrl,
		performanceOnlyMode: true,
		proofArtifactPath,
		interactionPerformanceProof: {
			blankTreeWindowCount: result.interactionPerformanceProof.blankTreeWindowCount,
			browserOrNativeRuntime: result.interactionPerformanceProof.browserOrNativeRuntime,
			clickPhaseDurations: result.interactionPerformanceProof.clickPhaseDurations,
			clickToFirstVisibleContentWindow:
				result.interactionPerformanceProof.clickToFirstVisibleContentWindow,
			commitSha: result.interactionPerformanceProof.commitSha,
			demandQueueWait: result.interactionPerformanceProof.demandQueueWait,
			foregroundContentLoadTiming: result.interactionPerformanceProof.foregroundContentLoadTiming,
			fileClickFailureDetails: result.interactionPerformanceProof.fileClickFailureDetails,
			fileClickSlowSampleDetails: result.interactionPerformanceProof.fileClickSlowSampleDetails,
			fileClickSampleCount: result.interactionPerformanceProof.fileClickSampleCount,
			passed: worktreeInteractionPerformanceSatisfied(result.interactionPerformanceProof),
			runMarker: result.interactionPerformanceProof.runMarker,
			scrollToVisibleRows: result.interactionPerformanceProof.scrollToVisibleRows,
			startupLoadTiming: result.interactionPerformanceProof.startupLoadTiming,
			treeScrollSettleFrameCount: result.interactionPerformanceProof.treeScrollSettleFrameCount,
			treeScrollSampleCount: result.interactionPerformanceProof.treeScrollSampleCount,
			workerMode: result.interactionPerformanceProof.workerMode,
			wrongVisibleRowCount: result.interactionPerformanceProof.wrongVisibleRowCount,
		},
		reviewInteractionPerformanceProof: {
			...result.reviewInteractionPerformanceProof,
			passed: reviewInteractionPerformanceSatisfied(result.reviewInteractionPerformanceProof),
		},
		scenarioName: result.scenarioName,
	};
}

export function worktreeDevServerConsoleProof(
	result: WorktreeDevServerVerificationResult,
	proofArtifactPath: string,
): Record<string, unknown> {
	return {
		ok: true,
		devServerUrl: worktreeDevServerUrl,
		observedLocationHref: result.observedLocationHref,
		observedPageUrl: result.observedPageUrl,
		requiredRouteUrls: worktreeDevServerRequiredRouteUrls(result),
		proofArtifactPath,
		interactionPerformanceProof: {
			blankTreeWindowCount: result.interactionPerformanceProof.blankTreeWindowCount,
			clickPhaseDurations: result.interactionPerformanceProof.clickPhaseDurations,
			clickToFirstVisibleContentWindow:
				result.interactionPerformanceProof.clickToFirstVisibleContentWindow,
			commitSha: result.interactionPerformanceProof.commitSha,
			demandQueueWait: result.interactionPerformanceProof.demandQueueWait,
			foregroundContentLoadTiming: result.interactionPerformanceProof.foregroundContentLoadTiming,
			fileClickFailureDetails: result.interactionPerformanceProof.fileClickFailureDetails,
			fileClickSlowSampleDetails: result.interactionPerformanceProof.fileClickSlowSampleDetails,
			fileClickSampleCount: result.interactionPerformanceProof.fileClickSampleCount,
			passed: worktreeInteractionPerformanceSatisfied(result.interactionPerformanceProof),
			runMarker: result.interactionPerformanceProof.runMarker,
			scrollToVisibleRows: result.interactionPerformanceProof.scrollToVisibleRows,
			startupLoadTiming: result.interactionPerformanceProof.startupLoadTiming,
			treeScrollSettleFrameCount: result.interactionPerformanceProof.treeScrollSettleFrameCount,
			treeScrollSampleCount: result.interactionPerformanceProof.treeScrollSampleCount,
			workerMode: result.interactionPerformanceProof.workerMode,
			wrongVisibleRowCount: result.interactionPerformanceProof.wrongVisibleRowCount,
		},
		reviewInteractionPerformanceProof: {
			...result.reviewInteractionPerformanceProof,
			passed: reviewInteractionPerformanceSatisfied(result.reviewInteractionPerformanceProof),
		},
		scenarioName: result.scenarioName,
		selectedContentState: result.selectedContentState,
		selectedDisplayPath: result.selectedDisplayPath,
		selectedLineCount: result.selectedLineCount,
		sharedShellProof: result.sharedShellProof,
		fileToReviewHandoffProof: result.fileToReviewHandoffProof,
		reviewFileTargetRouteProof: result.reviewFileTargetRouteProof,
		reviewRouteProof: result.reviewRouteProof,
		splitResetReplacementProof: {
			devReloadFrameCount: result.splitResetReplacementProof.devReloadFrameCount,
			devReloadFrameGenerationSample:
				result.splitResetReplacementProof.devReloadFrameGenerations.slice(0, 8),
			devReloadFrameKindSample: result.splitResetReplacementProof.devReloadFrameKinds.slice(0, 8),
			devReloadFrameSequenceHead: result.splitResetReplacementProof.devReloadFrameSequences.slice(
				0,
				8,
			),
			devReloadFrameSequenceTail:
				result.splitResetReplacementProof.devReloadFrameSequences.slice(-8),
			devReloadFrameStreamIdSample: result.splitResetReplacementProof.devReloadFrameStreamIds.slice(
				0,
				3,
			),
			devReloadRequest: result.splitResetReplacementProof.devReloadRequest,
			devReloadStatus: result.splitResetReplacementProof.devReloadStatus,
			oldContentRouteHitCount: result.splitResetReplacementProof.oldContentRouteHitCount,
			postRefreshContentRouteHitCount:
				result.splitResetReplacementProof.postRefreshContentRouteHitCount,
			postReplacementContentRouteHitCount:
				result.splitResetReplacementProof.postReplacementContentRouteHitCount,
			refreshDisabledAtFirstStale: result.splitResetReplacementProof.refreshDisabledAtFirstStale,
			refreshEnabledAfterReplacement:
				result.splitResetReplacementProof.refreshEnabledAfterReplacement,
			replacementContentRouteHitCount:
				result.splitResetReplacementProof.replacementContentRouteHitCount,
		},
		substituteGuardProof: result.substituteGuardProof,
		treePathCount: result.treePathCount,
		visibleAppProof: result.visibleAppProof,
	};
}

export function worktreeDevServerRequiredRouteUrls(result?: WorktreeDevServerVerificationResult): {
	readonly files: string;
	readonly review: string;
	readonly reviewFileTarget: string;
} {
	return {
		files: worktreeDevServerUrl,
		review: worktreeReviewDevServerUrl,
		reviewFileTarget:
			result?.reviewFileTargetRouteProof.locationHref ??
			reviewFileTargetUrlFromWorktreeDevServerUrl({
				path: reviewSelectionFixtureRelativePath,
				url: worktreeDevServerUrl,
				version: 'current',
			}),
	};
}
