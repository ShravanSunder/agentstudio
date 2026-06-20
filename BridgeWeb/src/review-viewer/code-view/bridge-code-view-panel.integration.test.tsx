// @vitest-environment jsdom

import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, test } from 'vitest';

import type { BridgeContentResource } from '../../foundation/content/content-resource-loader.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type {
	BridgeTelemetryFlushProps,
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import type { BridgeTelemetryScope } from '../../foundation/telemetry/bridge-telemetry-scope.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { makeBridgeViewerProjectionFixture } from '../test-support/review-viewer-fixtures.js';
import { createBridgePierreWorkerHighlighterOptions } from '../workers/pierre/bridge-pierre-worker-pool.js';
import { bridgeCodeViewOptions, BridgeCodeViewPanel } from './bridge-code-view-panel.js';
import { bridgePierreDarkThemeName } from './bridge-code-view-theme.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeCodeViewPanel', () => {
	let mountedRoot: ReturnType<typeof createRoot> | null = null;

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
	});

	test('uses Pierre-owned dark theme and compact internal layout spacing', () => {
		expect(bridgeCodeViewOptions.theme).toEqual({
			dark: bridgePierreDarkThemeName,
			light: bridgePierreDarkThemeName,
		});
		expect(bridgeCodeViewOptions.themeType).toBe('dark');
		expect(bridgeCodeViewOptions.layout).toEqual({
			paddingTop: 0,
			paddingBottom: 0,
			gap: 1,
		});
		expect(bridgeCodeViewOptions.diffIndicators).toBe('bars');
		expect(bridgeCodeViewOptions.stickyHeaders).toBe(true);
	});

	test('keeps worker-sensitive render options identical between CodeView and Pierre worker pool', () => {
		const highlighterOptions = createBridgePierreWorkerHighlighterOptions();

		expect(highlighterOptions.theme).toEqual(bridgeCodeViewOptions.theme);
		expect(highlighterOptions.useTokenTransformer).toBe(bridgeCodeViewOptions.useTokenTransformer);
		expect(highlighterOptions.tokenizeMaxLineLength).toBe(
			bridgeCodeViewOptions.tokenizeMaxLineLength,
		);
		expect(highlighterOptions.lineDiffType).toBe(bridgeCodeViewOptions.lineDiffType);
		expect(highlighterOptions.maxLineDiffLength).toBe(bridgeCodeViewOptions.maxLineDiffLength);
	});

	test('renders hydrated markdown source through the CodeView surface', async () => {
		installDomObservers();
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'docsAndPlans' }, refinements: [] },
		});
		const selectedItem = reviewPackage.itemsById['docs-plan'];
		const headHandle = selectedItem?.contentRoles.head;
		if (selectedItem === undefined || headHandle === undefined || headHandle === null) {
			throw new Error('expected docs-plan head handle');
		}
		const selectedContentResource: BridgeContentResource = {
			handle: headHandle,
			text: '# Bridge plan\n\nInspect this as source.',
		};
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{ head: selectedContentResource }}
					selectedItemId="docs-plan"
				/>,
			);
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(document.querySelector('[data-testid="bridge-code-view-panel"]')).not.toBeNull();
		const renderedCodeViewText = renderedCodeViewTextContent();
		expect(renderedCodeViewText).toContain('Bridge plan');
		expect(renderedCodeViewText).toContain('Inspect this as source.');
	});

	test('forces telemetry flush after selected item hydration is recorded', async () => {
		installDomObservers();
		const reviewPackage = makeBridgeViewerProjectionFixture();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { base: { kind: 'docsAndPlans' }, refinements: [] },
		});
		const selectedItem = reviewPackage.itemsById['docs-plan'];
		const headHandle = selectedItem?.contentRoles.head;
		if (selectedItem === undefined || headHandle === undefined || headHandle === null) {
			throw new Error('expected docs-plan head handle');
		}
		const telemetryRecorder = makeTelemetryRecorder();
		const selectedContentResource: BridgeContentResource = {
			handle: headHandle,
			text: '# Bridge plan\n\nInspect this as source.',
		};
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeCodeViewPanel
					projection={projection}
					reviewPackage={reviewPackage}
					selectedContentResources={{ head: selectedContentResource }}
					selectedItemId="docs-plan"
					telemetryRecorder={telemetryRecorder}
				/>,
			);
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await waitForAnimationFrame();
		});

		expect(
			telemetryRecorder.samples.map((sample: BridgeTelemetrySample): string => sample.name),
		).toContain('performance.bridge.pierre.item_update');
		expect(telemetryRecorder.flushForces).toContain(true);
		expect(telemetryRecorder.flushForces.at(-1)).toBe(true);
	});
});

interface TestTelemetryRecorder extends BridgeTelemetryRecorder {
	readonly flushForces: boolean[];
	readonly samples: BridgeTelemetrySample[];
}

function makeTelemetryRecorder(): TestTelemetryRecorder {
	const samples: BridgeTelemetrySample[] = [];
	const flushForces: boolean[] = [];
	return {
		flushForces,
		samples,
		isEnabled: (scope: BridgeTelemetryScope): boolean => scope === 'web',
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		measure<TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult {
			return props.operation();
		},
		flush: (props?: BridgeTelemetryFlushProps): boolean => {
			flushForces.push(props?.force === true);
			return true;
		},
	};
}

function renderedCodeViewTextContent(): string {
	const shadowText = [...document.querySelectorAll('diffs-container')]
		.map((element: Element): string => element.shadowRoot?.textContent ?? '')
		.join(' ');
	return `${document.body.textContent ?? ''} ${shadowText}`;
}

async function waitForAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => {
			resolve();
		});
	});
}

function installDomObservers(): void {
	if (!('ResizeObserver' in globalThis)) {
		Object.assign(globalThis, { ResizeObserver: TestResizeObserver });
	}
	if (HTMLElement.prototype.scrollTo === undefined) {
		HTMLElement.prototype.scrollTo = testElementScrollTo;
	}
}

function testElementScrollTo(): void {}

class TestResizeObserver implements ResizeObserver {
	readonly #callback: ResizeObserverCallback;

	constructor(callback: ResizeObserverCallback) {
		this.#callback = callback;
	}

	observe(target: Element): void {
		const entry = {
			target,
			contentRect: {
				x: 0,
				y: 0,
				width: 900,
				height: 500,
				top: 0,
				right: 900,
				bottom: 500,
				left: 0,
				toJSON: (): Record<string, number> => ({}),
			},
			borderBoxSize: [{ blockSize: 500, inlineSize: 900 }],
			contentBoxSize: [{ blockSize: 500, inlineSize: 900 }],
			devicePixelContentBoxSize: [{ blockSize: 500, inlineSize: 900 }],
		} satisfies ResizeObserverEntry;
		this.#callback([entry], this);
	}

	unobserve(): void {}

	disconnect(): void {}
}
