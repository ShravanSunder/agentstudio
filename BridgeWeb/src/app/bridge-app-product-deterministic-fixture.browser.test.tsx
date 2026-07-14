import { describe, test } from 'vitest';

import { expectBridgeProductSourceCellCorrelation } from './bridge-app-product-source-cell.browser-test-support.js';

describe('Bridge product deterministic fixture source cell', () => {
	test('correlates selected File and Review source through descriptor, request, readable DOM, and painted disposition', async () => {
		await expectBridgeProductSourceCellCorrelation({
			expectedOracleKind: 'fixtureManifest',
			expectedProjectName: 'VB-deterministic-fixture',
			expectedSourceKind: 'deterministicFixture',
		});
	});
});
