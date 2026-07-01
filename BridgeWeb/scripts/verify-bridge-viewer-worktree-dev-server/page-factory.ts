import type { Page } from 'playwright';

import type { ReviewMetadataBeforeContentProof } from '../verify-bridge-viewer-worktree-review-proof.ts';
import { requireVerifierBrowser } from './browser-session.ts';
import type { WorktreeVerifierBrowserHelpers } from './types.ts';

export async function makeVerificationPage(): Promise<Page> {
	const page = await requireVerifierBrowser().newPage({
		deviceScaleFactor: 1,
		viewport: {
			width: 1728,
			height: 980,
		},
	});
	await page.addInitScript((): void => {
		window.bridgeWorktreeVerifierTelemetrySamples = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			if (typeof detail !== 'object' || detail === null) {
				return;
			}
			if (!('method' in detail) || detail.method !== 'system.bridgeTelemetry') {
				return;
			}
			if (!('params' in detail) || typeof detail.params !== 'object' || detail.params === null) {
				return;
			}
			if (!('samples' in detail.params) || !Array.isArray(detail.params.samples)) {
				return;
			}
			for (const sample of detail.params.samples) {
				if (typeof sample !== 'object' || sample === null) {
					continue;
				}
				if (!('name' in sample) || typeof sample.name !== 'string') {
					continue;
				}
				const stringAttributes =
					'stringAttributes' in sample &&
					typeof sample.stringAttributes === 'object' &&
					sample.stringAttributes !== null
						? sample.stringAttributes
						: {};
				const numericAttributes =
					'numericAttributes' in sample &&
					typeof sample.numericAttributes === 'object' &&
					sample.numericAttributes !== null
						? sample.numericAttributes
						: {};
				const safeNumericAttributes: Record<string, number> = {};
				for (const [key, value] of Object.entries(numericAttributes)) {
					if (typeof value === 'number') {
						safeNumericAttributes[key] = value;
					}
				}
				window.bridgeWorktreeVerifierTelemetrySamples?.push({
					durationMilliseconds:
						'durationMilliseconds' in sample &&
						(typeof sample.durationMilliseconds === 'number' ||
							sample.durationMilliseconds === null)
							? sample.durationMilliseconds
							: null,
					name: sample.name,
					numericAttributes: safeNumericAttributes,
					phase:
						'agentstudio.bridge.phase' in stringAttributes &&
						typeof stringAttributes['agentstudio.bridge.phase'] === 'string'
							? stringAttributes['agentstudio.bridge.phase']
							: null,
					result:
						'agentstudio.bridge.result' in stringAttributes &&
						typeof stringAttributes['agentstudio.bridge.result'] === 'string'
							? stringAttributes['agentstudio.bridge.result']
							: null,
					slice:
						'agentstudio.bridge.slice' in stringAttributes &&
						typeof stringAttributes['agentstudio.bridge.slice'] === 'string'
							? stringAttributes['agentstudio.bridge.slice']
							: null,
					transport:
						'agentstudio.bridge.transport' in stringAttributes &&
						typeof stringAttributes['agentstudio.bridge.transport'] === 'string'
							? stringAttributes['agentstudio.bridge.transport']
							: null,
					viewer:
						'agentstudio.bridge.viewer' in stringAttributes &&
						typeof stringAttributes['agentstudio.bridge.viewer'] === 'string'
							? stringAttributes['agentstudio.bridge.viewer']
							: null,
				});
			}
		});
		const verifierHelpers: WorktreeVerifierBrowserHelpers = {
			getBridgeFileViewerRenderedCodeLineCount(): number {
				const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
				if (!(canvas instanceof HTMLElement)) {
					return 0;
				}
				return Array.from(canvas.querySelectorAll('diffs-container')).reduce(
					(lineCount, container) =>
						lineCount +
						(container.shadowRoot?.querySelectorAll('[data-content] [data-line-index]').length ??
							0),
					0,
				);
			},
			getBridgeFileViewerRenderedCodeText(): string {
				const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
				if (!(canvas instanceof HTMLElement)) {
					return '';
				}
				const renderedContentBlocks = Array.from(
					canvas.querySelectorAll('diffs-container'),
				).flatMap((container) =>
					Array.from(container.shadowRoot?.querySelectorAll('[data-content]') ?? []),
				);
				const renderedText = renderedContentBlocks
					.map((contentBlock) => contentBlock.textContent ?? '')
					.join('\n');
				return renderedText.length > 0 ? renderedText : (canvas.textContent ?? '');
			},
			getBridgeFileViewerScrollableContent(): HTMLElement | null {
				const canvas = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
				if (!(canvas instanceof HTMLElement)) {
					return null;
				}
				const candidates = [
					canvas,
					...Array.from(canvas.querySelectorAll('*')).filter(
						(candidate): candidate is HTMLElement => candidate instanceof HTMLElement,
					),
				];
				return (
					candidates.find((candidate) => candidate.scrollHeight > candidate.clientHeight) ?? canvas
				);
			},
			getPierreFileTreeItem(path: string): HTMLElement | null {
				const escapedPath = CSS.escape(path);
				return (
					this.getPierreFileTreeItems().find(
						(candidate) => candidate.dataset['itemPath'] === path,
					) ??
					this.getPierreFileTreeScrollElement()?.querySelector(
						`[data-item-path="${escapedPath}"]`,
					) ??
					null
				);
			},
			getPierreFileTreeItems(): HTMLElement[] {
				const scrollElement = this.getPierreFileTreeScrollElement();
				if (!(scrollElement instanceof HTMLElement)) {
					return [];
				}
				return Array.from(scrollElement.querySelectorAll('[data-item-path]')).filter(
					(candidate): candidate is HTMLElement =>
						candidate instanceof HTMLElement &&
						candidate.dataset['fileTreeStickyRow'] !== 'true' &&
						candidate.dataset['itemParked'] !== 'true',
				);
			},
			getPierreFileTreeScrollElement(): HTMLElement | null {
				const treeHost = document.querySelector(
					'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
				);
				const scrollElement = treeHost?.shadowRoot?.querySelector(
					'[data-file-tree-virtualized-scroll="true"]',
				);
				return scrollElement instanceof HTMLElement ? scrollElement : null;
			},
		};
		Object.defineProperty(window, 'bridgeWorktreeVerifier', {
			configurable: true,
			value: verifierHelpers,
		});
		Object.defineProperty(window, 'bridgeWorktreeReviewMetadataBeforeContentProof', {
			configurable: true,
			value: (): ReviewMetadataBeforeContentProof => {
				const reviewShell = document.querySelector('[data-testid="review-viewer-shell"]');
				const treeHost = document.querySelector(
					'[data-testid="bridge-review-trees-panel"] file-tree-container',
				);
				const scrollElement = treeHost?.shadowRoot?.querySelector(
					'[data-file-tree-virtualized-scroll="true"]',
				);
				const visibleRows = Array.from(
					scrollElement?.querySelectorAll<HTMLElement>(
						'button[data-item-path]:not([data-file-tree-sticky-row]):not([data-item-parked])',
					) ?? [],
				).filter((candidate): boolean => {
					if (!(candidate instanceof HTMLElement)) {
						return false;
					}
					const rect = candidate.getBoundingClientRect();
					return rect.width > 0 && rect.height > 0;
				});
				const scrollRect =
					scrollElement instanceof HTMLElement ? scrollElement.getBoundingClientRect() : null;
				return {
					blockedContentHitCount: 0,
					metadataHitCount: 0,
					selectedContentStateWhileBlocked:
						reviewShell instanceof HTMLElement
							? reviewShell.getAttribute('data-selected-content-state')
							: null,
					selectedDisplayPathWhileBlocked:
						reviewShell instanceof HTMLElement
							? reviewShell.getAttribute('data-selected-display-path')
							: null,
					treeVisibleRowCountWhileBlocked: visibleRows.length,
					treeVisibleWhileBlocked:
						scrollRect !== null &&
						scrollRect.width > 0 &&
						scrollRect.height > 0 &&
						visibleRows.length > 0,
				};
			},
		});
	});
	return page;
}
