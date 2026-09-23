import { createElement, type ReactElement, useState } from 'react';
import { render } from 'vitest-browser-react';

import { defineConsoleErrorGuardProbe } from './console-error-guard-probe.ts';

let setActWarningProbeCount: ((count: number) => void) | null = null;

function ActWarningProbe(): ReactElement {
	const [count, setCount] = useState(0);
	setActWarningProbeCount = setCount;
	return createElement('output', null, String(count));
}

// The browser suite renders a real component and updates its state outside
// act(), so react-dom itself emits the warning the guard must fail on. The
// function name is the component name the probe expects.
defineConsoleErrorGuardProbe({
	suiteName: 'browser-integration',
	emitActWarning: async (): Promise<void> => {
		await render(createElement(ActWarningProbe));
		setActWarningProbeCount?.(1);
	},
});
