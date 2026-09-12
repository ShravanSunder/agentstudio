import { afterAll, beforeAll, describe, expect, test } from 'vitest';

import { runAnnotationSaveJourney } from './bridge-viewer-vite-annotation-save-journey.ts';
import {
	createBridgeViewerViteProductFixture,
	startBridgeViewerOwnedViteProductServer,
	type BridgeViewerOwnedViteProductServer,
	type BridgeViewerViteProductFixtureOracle,
} from './bridge-viewer-vite-product-fixture.ts';

let disposeFixture: (() => Promise<void>) | null = null;
let fixtureOracle: BridgeViewerViteProductFixtureOracle | null = null;
let ownedServer: BridgeViewerOwnedViteProductServer | null = null;

describe('Bridge Viewer annotation Save journey', () => {
	beforeAll(async (): Promise<void> => {
		const fixture = await createBridgeViewerViteProductFixture();
		disposeFixture = fixture.dispose;
		fixtureOracle = fixture.oracle;
		ownedServer = await startBridgeViewerOwnedViteProductServer(fixture.oracle);
	});

	afterAll(async (): Promise<void> => {
		try {
			if (ownedServer !== null) {
				const cleanup = await ownedServer.stop();
				expect(cleanup.forcedTerminationRequired).toBe(false);
				expect(cleanup.ownedProcessAliveAfterStop).toBe(false);
			}
		} finally {
			await disposeFixture?.();
		}
	});

	test.each([
		['File', 'file'],
		['Review', 'review'],
	] as const)(
		'keeps a committed %s comment visible through projection handoff and reload',
		async (_label, surface): Promise<void> => {
			if (fixtureOracle === null || ownedServer === null) {
				throw new Error('Annotation Save journey fixture is unavailable.');
			}
			const observations = await runAnnotationSaveJourney({
				oracle: fixtureOracle,
				server: ownedServer,
				surface,
			});
			expect(observations.gatedProjectionRequestCount).toBeGreaterThan(0);
			expect(observations.savingControlCountAfterCommit).toBe(0);
			expect(observations.committedBodyCountWhileProjectionGated).toBe(1);
			expect(observations.projectedSavedMessageCount).toBe(1);
			expect(observations.reloadedSavedMessageCount).toBe(1);
		},
	);
});
