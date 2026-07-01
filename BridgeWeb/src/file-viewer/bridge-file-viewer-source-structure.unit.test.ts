import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Bridge file viewer source structure', () => {
	test('keeps content body loading in the content controller hook', () => {
		const appSource = readFileSync(
			fileURLToPath(new URL('./bridge-file-viewer-app.tsx', import.meta.url)),
			'utf8',
		);

		expect(appSource).toContain('useBridgeFileViewerContentController');
		expect(appSource).not.toContain('runtime.openFile');
		expect(appSource).not.toContain('runtime.refreshOpenFile');
		expect(appSource).not.toContain('recordBridgeViewerFileOpenReadyTelemetrySample');
	});
});
