import { act, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

import { ReviewNavigationControllerProbe } from './bridge-review-navigation-controller.browser.test-support.js';

describe('Bridge Review navigation controller', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
	});

	test('does not apply a retained command after its admission is revoked', async () => {
		// Arrange
		const events: string[] = [];

		// Act
		const rendered = await renderInsideAct(
			<ReviewNavigationControllerProbe
				events={events}
				isNavigationCommandStillEligible={(): boolean => false}
			/>,
		);

		// Assert
		expect(events).toEqual([]);
		await expect
			.element(rendered.getByTestId('review-navigation-selection'))
			.toHaveTextContent('none');
	});
});

async function renderInsideAct(element: ReactElement): Promise<Awaited<ReturnType<typeof render>>> {
	let rendered: Awaited<ReturnType<typeof render>> | null = null;
	await act(async (): Promise<void> => {
		rendered = await render(element);
		await Promise.resolve();
	});
	if (rendered === null) throw new Error('Expected Browser render result.');
	return rendered;
}
