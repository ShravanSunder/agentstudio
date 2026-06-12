// @vitest-environment jsdom

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { BridgeApp } from './bridge-app.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('BridgeApp', () => {
	let mountedRoot: Root | null = null;

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-nonce');
	});

	test('mounts transport in order renders pushed package and sends selection commands', async () => {
		document.documentElement.setAttribute('data-bridge-nonce', 'bridge-nonce');
		const reviewPackage = makeBridgeReviewPackage();
		const commandDetails: unknown[] = [];
		document.addEventListener('__bridge_command', (event: Event): void => {
			commandDetails.push(extractEventDetail(event));
		});
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		await act(async (): Promise<void> => {
			mountedRoot?.render(
				<BridgeApp
					fetchContent={async (): Promise<Response> => new Response('loaded head text')}
				/>,
			);
		});

		await act(async (): Promise<void> => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', { detail: { pushNonce: 'push-nonce' } }),
			);
			document.dispatchEvent(
				new CustomEvent('__bridge_push', {
					detail: {
						__v: 1,
						__pushId: 'push-1',
						__revision: 1,
						__epoch: 1,
						store: 'diff',
						op: 'replace',
						level: 'cold',
						nonce: 'push-nonce',
						data: { package: reviewPackage },
					},
				}),
			);
			await Promise.resolve();
			await Promise.resolve();
		});

		expect(document.querySelector('[data-testid="review-viewer-shell"]')).not.toBeNull();
		expect(document.body.textContent).toContain('Sources/App/View.swift');
		expect(document.body.textContent).toContain('loaded head text');

		await act(async (): Promise<void> => {
			const selectedButton = document.querySelector('button');
			if (selectedButton === null) {
				throw new Error('expected selected review item button');
			}
			selectedButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});

		expect(commandDetails).toEqual([
			{
				jsonrpc: '2.0',
				method: 'review.markFileViewed',
				params: { fileId: 'item-source' },
				__nonce: 'bridge-nonce',
				__commandId: expect.stringMatching(/^cmd_/),
			},
		]);
	});
});

function extractEventDetail(event: Event): unknown {
	return 'detail' in event ? event.detail : null;
}
