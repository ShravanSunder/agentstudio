import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

const applicationDiscriminator = /['"`](?:annotation|file|review)\.[^'"`]+['"`]/u;

describe('Bridge product transport opacity', () => {
	test.each(['./bridge-product-content-frame-codec.ts', './bridge-product-session-authority.ts'])(
		'%s does not interpret application discriminators',
		async (relativePath) => {
			// Arrange
			const source = await readFile(new URL(relativePath, import.meta.url), 'utf8');

			// Act
			const interpretedApplicationDiscriminator =
				source.match(applicationDiscriminator)?.[0] ?? null;

			// Assert
			expect(interpretedApplicationDiscriminator).toBeNull();
		},
	);

	test('transport stores opaque registered surfaces instead of declaring File and Review', async () => {
		// Arrange
		const source = await readFile(
			new URL('./bridge-product-transport.ts', import.meta.url),
			'utf8',
		);

		// Act / Assert
		expect(source).not.toContain("export type BridgeProductSurface = 'file' | 'review'");
		expect(source).not.toContain('props.initialWorkerDerivationEpochs?.file');
		expect(source).not.toContain('props.initialWorkerDerivationEpochs?.review');
	});
});
