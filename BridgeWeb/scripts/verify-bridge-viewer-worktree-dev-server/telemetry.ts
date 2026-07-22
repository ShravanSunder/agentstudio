import type { Page } from 'playwright';

import {
	worktreeFileRecentlyUpdatedDemandTelemetrySatisfied,
	type WorktreeFileDemandDispatchTelemetryProof,
} from '../verify-bridge-viewer-worktree-review-proof.ts';
import { renderedTextIncludesContent } from './content-state.ts';
import {
	worktreeFileDemandDispatchTelemetryProofSchema,
	type WorktreeFileDescriptor,
	type WorktreeFileOpenLoadTelemetryProof,
} from './types.ts';

export async function verifyWorktreeFileRecentlyUpdatedDemand(props: {
	readonly descriptor: WorktreeFileDescriptor;
	readonly page: Page;
	readonly sourceId: string;
}): Promise<WorktreeFileDemandDispatchTelemetryProof> {
	await props.page.evaluate(
		(detail: {
			readonly path: string;
			readonly proximity: string;
			readonly sourceIdentity: string;
		}): void => {
			window.dispatchEvent(
				new CustomEvent('bridge-worktree-file-recently-updated', {
					detail,
				}),
			);
		},
		{
			path: props.descriptor.path,
			proximity: 'nearby',
			sourceIdentity: props.sourceId,
		},
	);
	const proof = await waitForWorktreeFileRecentlyUpdatedDemandTelemetry(
		props.page,
		props.descriptor.contentHandle,
	);
	if (!worktreeFileRecentlyUpdatedDemandTelemetrySatisfied(proof)) {
		throw new Error(
			`Expected FileViewer recently-updated preload telemetry to be attributed: ${JSON.stringify(proof)}`,
		);
	}
	if (
		!(proof.firstDedupeKey ?? '').includes(props.descriptor.contentHandle) ||
		!(proof.firstFreshnessKey ?? '').includes(props.descriptor.contentHandle)
	) {
		throw new Error(
			`Expected recently-updated demand keys to reference ${props.descriptor.contentHandle}: ${JSON.stringify(proof)}`,
		);
	}
	return proof;
}

export async function waitForWorktreeFileRecentlyUpdatedDemandTelemetry(
	page: Page,
	expectedContentHandle: string,
): Promise<WorktreeFileDemandDispatchTelemetryProof> {
	const proofHandle = await page.waitForFunction(
		(expectedHandle: string): WorktreeFileDemandDispatchTelemetryProof | null => {
			const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
			if (!(shell instanceof HTMLElement)) {
				return null;
			}
			const readNumberAttribute = (attributeName: string): number | null => {
				const attributeValue = shell.getAttribute(attributeName);
				if (attributeValue === null) {
					return null;
				}
				const parsedValue = Number(attributeValue);
				return Number.isFinite(parsedValue) ? parsedValue : null;
			};
			const readNumberRecordAttribute = (attributeName: string): Record<string, number> | null => {
				const attributeValue = shell.getAttribute(attributeName);
				if (attributeValue === null) {
					return null;
				}
				try {
					const parsedValue: unknown = JSON.parse(attributeValue);
					if (
						parsedValue === null ||
						typeof parsedValue !== 'object' ||
						Array.isArray(parsedValue)
					) {
						return null;
					}
					const record: Record<string, number> = {};
					for (const [key, value] of Object.entries(parsedValue)) {
						if (typeof value !== 'number') {
							return null;
						}
						record[key] = value;
					}
					return record;
				} catch {
					return null;
				}
			};
			const proof: WorktreeFileDemandDispatchTelemetryProof = {
				expectedVisibleFileCount: readNumberAttribute(
					'data-last-demand-dispatch-expected-visible-file-count',
				),
				failedCount: readNumberAttribute('data-last-demand-dispatch-failed-count'),
				failedCountByLane: readNumberRecordAttribute(
					'data-last-demand-dispatch-failed-count-by-lane',
				),
				failedCountByReason: readNumberRecordAttribute(
					'data-last-demand-dispatch-failed-count-by-reason',
				),
				firstDedupeKey: shell.getAttribute('data-last-demand-dispatch-first-dedupe-key'),
				firstDisposition: shell.getAttribute('data-last-demand-dispatch-first-disposition'),
				firstExecutorInFlightMilliseconds: readNumberAttribute(
					'data-last-demand-dispatch-first-executor-in-flight-ms',
				),
				firstExecutorPendingWaitMilliseconds: readNumberAttribute(
					'data-last-demand-dispatch-first-executor-pending-wait-ms',
				),
				firstFreshnessKey: shell.getAttribute('data-last-demand-dispatch-first-freshness-key'),
				firstLane: shell.getAttribute('data-last-demand-dispatch-first-lane'),
				firstSchedulerQueueWaitMilliseconds: readNumberAttribute(
					'data-last-demand-dispatch-first-scheduler-queue-wait-ms',
				),
				intentCount: readNumberAttribute('data-last-demand-dispatch-intent-count'),
				loadedCount: readNumberAttribute('data-last-demand-dispatch-loaded-count'),
				executorInFlightBytesAfter: readNumberAttribute(
					'data-last-demand-dispatch-executor-in-flight-bytes-after',
				),
				executorInFlightCountAfter: readNumberAttribute(
					'data-last-demand-dispatch-executor-in-flight-after',
				),
				executorQueuedBytesAfter: readNumberAttribute(
					'data-last-demand-dispatch-executor-queued-bytes-after',
				),
				executorQueuedLoadCountAfter: readNumberAttribute(
					'data-last-demand-dispatch-executor-queued-after',
				),
				schedulerQueuedEstimatedBytesAfter: readNumberAttribute(
					'data-last-demand-dispatch-scheduler-queued-bytes-after',
				),
				schedulerQueuedIntentCountAfter: readNumberAttribute(
					'data-last-demand-dispatch-scheduler-queued-after',
				),
				recentlyUpdatedOpenFilePathAfter: shell.getAttribute(
					'data-last-demand-dispatch-open-file-path-after',
				),
				recentlyUpdatedOpenFilePathBefore: shell.getAttribute(
					'data-last-demand-dispatch-open-file-path-before',
				),
				status: shell.getAttribute('data-last-demand-dispatch-status'),
				stimulusCount: readNumberAttribute('data-last-demand-dispatch-stimulus-count'),
			};
			if (
				shell.getAttribute('data-last-demand-dispatch-origin') !== 'recentlyUpdatedFile' ||
				proof.status !== 'settled' ||
				proof.firstLane !== 'nearby' ||
				!(proof.firstDedupeKey ?? '').includes(expectedHandle) ||
				!(proof.firstFreshnessKey ?? '').includes(expectedHandle)
			) {
				return null;
			}
			return proof;
		},
		expectedContentHandle,
		{ timeout: 20_000 },
	);
	return worktreeFileDemandDispatchTelemetryProofSchema.parse(await proofHandle.jsonValue());
}

export async function readWorktreeFileVisibleDemandTelemetry(
	page: Page,
): Promise<WorktreeFileDemandDispatchTelemetryProof> {
	return await page.evaluate((): WorktreeFileDemandDispatchTelemetryProof => {
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const readShellNumberAttribute = (attributeName: string): number | null => {
			if (!(shell instanceof HTMLElement)) {
				return null;
			}
			const attributeValue = shell.getAttribute(attributeName);
			if (attributeValue === null) {
				return null;
			}
			const parsedValue = Number(attributeValue);
			return Number.isFinite(parsedValue) ? parsedValue : null;
		};
		const readShellNumberRecordAttribute = (
			attributeName: string,
		): Record<string, number> | null => {
			if (!(shell instanceof HTMLElement)) {
				return null;
			}
			const attributeValue = shell.getAttribute(attributeName);
			if (attributeValue === null) {
				return null;
			}
			try {
				const parsedValue: unknown = JSON.parse(attributeValue);
				if (parsedValue === null || typeof parsedValue !== 'object' || Array.isArray(parsedValue)) {
					return null;
				}
				const record: Record<string, number> = {};
				for (const [key, value] of Object.entries(parsedValue)) {
					if (typeof value !== 'number') {
						return null;
					}
					record[key] = value;
				}
				return record;
			} catch {
				return null;
			}
		};
		return {
			expectedVisibleFileCount: readShellNumberAttribute(
				'data-last-demand-dispatch-expected-visible-file-count',
			),
			failedCount: readShellNumberAttribute('data-last-demand-dispatch-failed-count'),
			failedCountByLane: readShellNumberRecordAttribute(
				'data-last-demand-dispatch-failed-count-by-lane',
			),
			failedCountByReason: readShellNumberRecordAttribute(
				'data-last-demand-dispatch-failed-count-by-reason',
			),
			firstDedupeKey:
				shell instanceof HTMLElement
					? shell.getAttribute('data-last-demand-dispatch-first-dedupe-key')
					: null,
			firstDisposition:
				shell instanceof HTMLElement
					? shell.getAttribute('data-last-demand-dispatch-first-disposition')
					: null,
			firstExecutorInFlightMilliseconds: readShellNumberAttribute(
				'data-last-demand-dispatch-first-executor-in-flight-ms',
			),
			firstExecutorPendingWaitMilliseconds: readShellNumberAttribute(
				'data-last-demand-dispatch-first-executor-pending-wait-ms',
			),
			firstFreshnessKey:
				shell instanceof HTMLElement
					? shell.getAttribute('data-last-demand-dispatch-first-freshness-key')
					: null,
			firstLane:
				shell instanceof HTMLElement
					? shell.getAttribute('data-last-demand-dispatch-first-lane')
					: null,
			firstSchedulerQueueWaitMilliseconds: readShellNumberAttribute(
				'data-last-demand-dispatch-first-scheduler-queue-wait-ms',
			),
			intentCount: readShellNumberAttribute('data-last-demand-dispatch-intent-count'),
			loadedCount: readShellNumberAttribute('data-last-demand-dispatch-loaded-count'),
			executorInFlightBytesAfter: readShellNumberAttribute(
				'data-last-demand-dispatch-executor-in-flight-bytes-after',
			),
			executorInFlightCountAfter: readShellNumberAttribute(
				'data-last-demand-dispatch-executor-in-flight-after',
			),
			executorQueuedBytesAfter: readShellNumberAttribute(
				'data-last-demand-dispatch-executor-queued-bytes-after',
			),
			executorQueuedLoadCountAfter: readShellNumberAttribute(
				'data-last-demand-dispatch-executor-queued-after',
			),
			schedulerQueuedEstimatedBytesAfter: readShellNumberAttribute(
				'data-last-demand-dispatch-scheduler-queued-bytes-after',
			),
			schedulerQueuedIntentCountAfter: readShellNumberAttribute(
				'data-last-demand-dispatch-scheduler-queued-after',
			),
			recentlyUpdatedOpenFilePathAfter:
				shell instanceof HTMLElement
					? shell.getAttribute('data-last-demand-dispatch-open-file-path-after')
					: null,
			recentlyUpdatedOpenFilePathBefore:
				shell instanceof HTMLElement
					? shell.getAttribute('data-last-demand-dispatch-open-file-path-before')
					: null,
			status:
				shell instanceof HTMLElement
					? shell.getAttribute('data-last-demand-dispatch-status')
					: null,
			stimulusCount: readShellNumberAttribute('data-last-demand-dispatch-stimulus-count'),
		};
	});
}

export async function waitForWorktreeFileVisibleDemandTelemetry(
	page: Page,
): Promise<WorktreeFileDemandDispatchTelemetryProof> {
	try {
		await page.waitForFunction(
			(): boolean => {
				const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
				if (!(shell instanceof HTMLElement)) {
					return false;
				}
				const readNumberAttribute = (attributeName: string): number | null => {
					const attributeValue = shell.getAttribute(attributeName);
					if (attributeValue === null) {
						return null;
					}
					const parsedValue = Number(attributeValue);
					return Number.isFinite(parsedValue) ? parsedValue : null;
				};
				const expectedVisibleFileCount = readNumberAttribute(
					'data-last-demand-dispatch-expected-visible-file-count',
				);
				const failedCount = readNumberAttribute('data-last-demand-dispatch-failed-count');
				const intentCount = readNumberAttribute('data-last-demand-dispatch-intent-count');
				const loadedCount = readNumberAttribute('data-last-demand-dispatch-loaded-count');
				const schedulerQueuedIntentCountAfter = readNumberAttribute(
					'data-last-demand-dispatch-scheduler-queued-after',
				);
				const executorQueuedLoadCountAfter = readNumberAttribute(
					'data-last-demand-dispatch-executor-queued-after',
				);
				const firstSchedulerQueueWaitMilliseconds = readNumberAttribute(
					'data-last-demand-dispatch-first-scheduler-queue-wait-ms',
				);
				const firstExecutorPendingWaitMilliseconds = readNumberAttribute(
					'data-last-demand-dispatch-first-executor-pending-wait-ms',
				);
				const firstExecutorInFlightMilliseconds = readNumberAttribute(
					'data-last-demand-dispatch-first-executor-in-flight-ms',
				);
				return (
					shell.getAttribute('data-last-demand-dispatch-status') === 'settled' &&
					shell.getAttribute('data-last-demand-dispatch-origin') === 'visibleViewport' &&
					shell.getAttribute('data-last-demand-dispatch-first-lane') === 'visible' &&
					(shell.getAttribute('data-last-demand-dispatch-first-disposition') ===
						'visible-preloaded' ||
						shell.getAttribute('data-last-demand-dispatch-first-disposition') === 'cache-hit') &&
					expectedVisibleFileCount !== null &&
					expectedVisibleFileCount > 0 &&
					intentCount !== null &&
					intentCount === expectedVisibleFileCount &&
					loadedCount !== null &&
					loadedCount === expectedVisibleFileCount &&
					failedCount === 0 &&
					schedulerQueuedIntentCountAfter === 0 &&
					executorQueuedLoadCountAfter === 0 &&
					firstSchedulerQueueWaitMilliseconds !== null &&
					firstExecutorPendingWaitMilliseconds !== null &&
					firstExecutorInFlightMilliseconds !== null
				);
			},
			undefined,
			{ timeout: 20_000 },
		);
	} catch {
		const proof = await readWorktreeFileVisibleDemandTelemetry(page);
		throw new Error(
			`Expected FileViewer visible preload demand telemetry to settle before read: ${JSON.stringify(proof)}`,
		);
	}
	return await readWorktreeFileVisibleDemandTelemetry(page);
}

export async function readWorktreeFileOpenLoadTelemetry(
	page: Page,
): Promise<WorktreeFileOpenLoadTelemetryProof> {
	return await page.evaluate((): WorktreeFileOpenLoadTelemetryProof => {
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const readShellNumberAttribute = (attributeName: string): number | null => {
			if (!(shell instanceof HTMLElement)) {
				return null;
			}
			const attributeValue = shell.getAttribute(attributeName);
			if (attributeValue === null) {
				return null;
			}
			const parsedValue = Number(attributeValue);
			return Number.isFinite(parsedValue) ? parsedValue : null;
		};
		return {
			disposition:
				shell instanceof HTMLElement ? shell.getAttribute('data-last-open-load-disposition') : null,
			durationMilliseconds: readShellNumberAttribute('data-last-open-load-duration-ms'),
			estimatedBytes: readShellNumberAttribute('data-last-open-load-estimated-bytes'),
			executorInFlightBytesAfter: readShellNumberAttribute(
				'data-last-open-load-executor-in-flight-bytes-after',
			),
			executorInFlightBytesBefore: readShellNumberAttribute(
				'data-last-open-load-executor-in-flight-bytes-before',
			),
			executorInFlightCountAfter: readShellNumberAttribute(
				'data-last-open-load-executor-in-flight-after',
			),
			executorInFlightCountBefore: readShellNumberAttribute(
				'data-last-open-load-executor-in-flight-before',
			),
			executorInFlightMilliseconds: readShellNumberAttribute(
				'data-last-open-load-executor-in-flight-ms',
			),
			executorPendingWaitMilliseconds: readShellNumberAttribute(
				'data-last-open-load-executor-pending-wait-ms',
			),
			executorQueuedBytesAfter: readShellNumberAttribute(
				'data-last-open-load-executor-queued-bytes-after',
			),
			executorQueuedBytesBefore: readShellNumberAttribute(
				'data-last-open-load-executor-queued-bytes-before',
			),
			executorQueuedLoadCountAfter: readShellNumberAttribute(
				'data-last-open-load-executor-queued-after',
			),
			executorQueuedLoadCountBefore: readShellNumberAttribute(
				'data-last-open-load-executor-queued-before',
			),
			lane: shell instanceof HTMLElement ? shell.getAttribute('data-last-open-load-lane') : null,
			resourceBodyRegistryCommitMilliseconds: readShellNumberAttribute(
				'data-last-open-load-resource-body-registry-commit-ms',
			),
			resourceFetchResponseWaitMilliseconds: readShellNumberAttribute(
				'data-last-open-load-resource-fetch-response-wait-ms',
			),
			resourceFirstChunkWaitMilliseconds: readShellNumberAttribute(
				'data-last-open-load-resource-first-chunk-wait-ms',
			),
			resourceStreamReadMilliseconds: readShellNumberAttribute(
				'data-last-open-load-resource-stream-read-ms',
			),
			schedulerQueueWaitMilliseconds: readShellNumberAttribute(
				'data-last-open-load-scheduler-queue-wait-ms',
			),
			schedulerQueuedEstimatedBytesAfter: readShellNumberAttribute(
				'data-last-open-load-scheduler-queued-bytes-after',
			),
			schedulerQueuedEstimatedBytesBefore: readShellNumberAttribute(
				'data-last-open-load-scheduler-queued-bytes-before',
			),
			schedulerQueuedIntentCountAfter: readShellNumberAttribute(
				'data-last-open-load-scheduler-queued-after',
			),
			schedulerQueuedIntentCountBefore: readShellNumberAttribute(
				'data-last-open-load-scheduler-queued-before',
			),
		};
	});
}

export async function dispatchWorktreeDevForceSplitResetReload(page: Page): Promise<void> {
	await page.evaluate((): void => {
		window.dispatchEvent(new Event('bridge-worktree-dev-force-split-reset-reload'));
	});
}

export async function dispatchWorktreeDevReload(page: Page): Promise<void> {
	await page.evaluate((): void => {
		window.dispatchEvent(new Event('bridge-worktree-dev-reload'));
	});
}

export async function worktreeVisibleContentText(page: Page): Promise<string> {
	return await page.evaluate((): string =>
		window.bridgeWorktreeVerifier.getBridgeFileViewerRenderedCodeText(),
	);
}

export async function assertWorktreeVisibleContentText(props: {
	readonly expectedText: string;
	readonly label: string;
	readonly page: Page;
}): Promise<void> {
	const text = await worktreeVisibleContentText(props.page);
	if (!renderedTextIncludesContent(text, props.expectedText)) {
		throw new Error(`Expected ${props.label} to be visible`);
	}
}

export async function waitForWorktreeVisibleContentText(props: {
	readonly expectedText: string;
	readonly label: string;
	readonly page: Page;
}): Promise<string> {
	const deadline = Date.now() + 10_000;
	let latestText = '';
	while (Date.now() < deadline) {
		latestText = await worktreeVisibleContentText(props.page);
		if (renderedTextIncludesContent(latestText, props.expectedText)) {
			return latestText;
		}
		await props.page.waitForTimeout(100);
	}
	const debugState = await props.page.evaluate(() => {
		const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
		const openPanel = document.querySelector('[data-testid="bridge-file-viewer-code-panel"]');
		return {
			lastRefreshCommitState: shell?.getAttribute('data-last-refresh-commit-state') ?? null,
			lastRefreshDescriptorId: shell?.getAttribute('data-last-refresh-descriptor-id') ?? null,
			lastRefreshResult: shell?.getAttribute('data-last-refresh-result') ?? null,
			openFileState: openPanel?.getAttribute('data-open-file-state') ?? null,
			selectedPath: openPanel?.getAttribute('data-selected-display-path') ?? null,
		};
	});
	throw new Error(
		`Expected ${props.label} to be visible: ${JSON.stringify({
			debugState,
			latestTextSample: latestText.slice(0, 500),
		})}`,
	);
}
