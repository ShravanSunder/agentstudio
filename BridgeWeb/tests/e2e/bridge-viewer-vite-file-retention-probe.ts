import type { Page } from 'playwright';

interface FileRetentionLoss {
	readonly elapsedMilliseconds: number;
	readonly openState: string | null;
	readonly paintedCorrelationPresent: boolean;
	readonly renderedContainerCount: number;
	readonly renderedLineCount: number;
	readonly renderedPath: string | null;
	readonly renderedHeight: number;
	readonly visibility: string | null;
}

declare global {
	interface Window {
		bridgeFileRetentionProbe?: {
			readonly stop: () => void;
			loss: FileRetentionLoss | null;
			mutationLoss: FileRetentionLoss | null;
			frameCount: number;
		};
	}
}

export async function observeSelectedFileRetention(
	page: Page,
	expectedPath: string,
): Promise<{
	readonly stop: () => Promise<FileRetentionLoss | null>;
}> {
	await page.evaluate((path: string): void => {
		window.bridgeFileRetentionProbe?.stop();
		const startedAtMilliseconds = performance.now();
		const readLoss = (): FileRetentionLoss | null => {
			const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
			const renderedPath = canvas?.getAttribute('data-worktree-rendered-file-path') ?? null;
			const painted = canvas?.querySelector(
				'diffs-container[data-bridge-painted-source-correlations]',
			);
			const codeView = canvas?.querySelector('[data-testid="bridge-file-viewer-code-view"]');
			const visibility =
				codeView === null || codeView === undefined ? null : getComputedStyle(codeView).visibility;
			if (
				renderedPath !== path ||
				painted === null ||
				painted === undefined ||
				visibility !== 'visible'
			) {
				const renderedContainers = [...(canvas?.querySelectorAll('diffs-container') ?? [])];
				const pendingRoots: Array<Element | ShadowRoot> = [...renderedContainers];
				let renderedLineCount = 0;
				while (pendingRoots.length > 0) {
					const root = pendingRoots.pop();
					if (root === undefined) continue;
					renderedLineCount += root.querySelectorAll('[data-line][data-line-index]').length;
					if (root instanceof Element && root.shadowRoot !== null)
						pendingRoots.push(root.shadowRoot);
					for (const descendant of root.querySelectorAll('*')) {
						if (descendant.shadowRoot !== null) pendingRoots.push(descendant.shadowRoot);
					}
				}
				const renderedHeight = codeView?.getBoundingClientRect().height ?? 0;
				// Render fulfillment clears its diagnostic stamp until the next paint
				// acknowledgement. That does not erase still-visible rendered lines.
				// The journey separately requires the exact new content SHA at completion.
				if (
					renderedPath === path &&
					visibility === 'visible' &&
					renderedLineCount > 0 &&
					renderedHeight > 0
				)
					return null;
				return {
					elapsedMilliseconds: performance.now() - startedAtMilliseconds,
					openState: canvas?.getAttribute('data-worktree-open-file-state') ?? null,
					paintedCorrelationPresent: painted !== null && painted !== undefined,
					renderedContainerCount: renderedContainers.length,
					renderedLineCount,
					renderedPath,
					renderedHeight,
					visibility,
				};
			}
			return null;
		};
		const observer = new MutationObserver((): void => {
			const probe = window.bridgeFileRetentionProbe;
			if (probe !== undefined && probe.mutationLoss === null) probe.mutationLoss = readLoss();
		});
		let frameHandle = 0;
		const sampleFrame = (): void => {
			const probe = window.bridgeFileRetentionProbe;
			if (probe === undefined) return;
			probe.frameCount += 1;
			if (probe.loss === null) probe.loss = readLoss();
			frameHandle = requestAnimationFrame(sampleFrame);
		};
		window.bridgeFileRetentionProbe = {
			stop: (): void => {
				observer.disconnect();
				cancelAnimationFrame(frameHandle);
			},
			loss: null,
			mutationLoss: null,
			frameCount: 0,
		};
		frameHandle = requestAnimationFrame(sampleFrame);
		observer.observe(document.body, { attributes: true, childList: true, subtree: true });
	}, expectedPath);
	return {
		stop: async (): Promise<FileRetentionLoss | null> =>
			await page.evaluate(() => {
				const probe = window.bridgeFileRetentionProbe;
				if (probe === undefined) throw new Error('File retention observation was lost.');
				probe.stop();
				if (probe.frameCount === 0) throw new Error('File retention captured no browser frames.');
				return probe.loss;
			}),
	};
}
