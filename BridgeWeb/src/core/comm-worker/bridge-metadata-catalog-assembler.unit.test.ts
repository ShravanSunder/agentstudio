import { describe, expect, test } from 'vitest';
import { z } from 'zod';

import {
	MetadataCatalogAssembler,
	type MetadataCatalogAssemblerResult,
} from './bridge-metadata-catalog-assembler.js';
import type {
	BridgeMetadataCatalogBegin,
	BridgeMetadataCatalogCommit,
	BridgeMetadataCatalogWindow,
} from './bridge-metadata-catalog-transfer-contracts.js';

const fixtureEntrySchema = z.object({ itemId: z.string() }).strict();
interface FixtureAuthority {
	readonly source: string;
}

describe('Bridge metadata catalog assembler', () => {
	test('completes zero-entry and multi-window candidates only at valid commit', () => {
		const assembler = makeAssembler({ source: 'A' });

		expect(assembler.accept({ source: 'A' }, begin('A-1', 1, 0))).toMatchObject({
			status: 'accepted',
		});
		expect(assembler.accept({ source: 'A' }, commit('A-1', 1, 0, 0))).toEqual({
			catalog: {
				authority: { source: 'A' },
				catalogRevision: 1,
				entries: [],
				transferId: 'A-1',
			},
			status: 'completed',
		});

		expect(assembler.accept({ source: 'A' }, begin('A-2', 2, 2))).toMatchObject({
			status: 'accepted',
		});
		expect(
			assembler.accept({ source: 'A' }, window('A-2', 2, 0, [{ itemId: 'one' }])),
		).toMatchObject({ status: 'accepted' });
		expect(
			assembler.accept({ source: 'A' }, window('A-2', 2, 1, [{ itemId: 'two' }])),
		).toMatchObject({ status: 'accepted' });
		expect(assembler.accept({ source: 'A' }, commit('A-2', 2, 2, 2))).toMatchObject({
			catalog: { entries: [{ itemId: 'one' }, { itemId: 'two' }] },
			status: 'completed',
		});
	});

	test('preserves a newer C candidate from late B frames after A is active', () => {
		const assembler = makeAssembler({ source: 'authority' });
		completeSingleEntry(assembler, { source: 'authority' }, 'A', 1, 'active');
		expect(assembler.accept({ source: 'authority' }, begin('B', 2, 1))).toMatchObject({
			status: 'accepted',
		});
		expect(assembler.accept({ source: 'authority' }, begin('C', 3, 1))).toMatchObject({
			status: 'accepted',
		});

		expect(
			assembler.accept({ source: 'authority' }, window('B', 2, 0, [{ itemId: 'late' }])),
		).toMatchObject({ reason: 'noncurrent_transfer', status: 'rejected' });
		expect(assembler.diagnostics.candidate).toMatchObject({ transferId: 'C' });
		expect(assembler.accept({ source: 'authority' }, commit('B', 2, 1, 1))).toMatchObject({
			reason: 'noncurrent_transfer',
			status: 'rejected',
		});
		expect(assembler.diagnostics.candidate).toMatchObject({ transferId: 'C' });
		expect(
			assembler.accept({ source: 'authority' }, window('C', 3, 0, [{ itemId: 'current' }])),
		).toMatchObject({ status: 'accepted' });
		expect(assembler.accept({ source: 'authority' }, commit('C', 3, 1, 1))).toMatchObject({
			catalog: { entries: [{ itemId: 'current' }] },
			status: 'completed',
		});
	});

	test('discards only a defective current candidate and rejects replay without state effect', () => {
		const assembler = makeAssembler({ source: 'authority' });
		completeSingleEntry(assembler, { source: 'authority' }, 'A', 1, 'active');
		expect(assembler.accept({ source: 'authority' }, begin('B', 2, 1))).toMatchObject({
			status: 'accepted',
		});
		expect(
			assembler.accept({ source: 'authority' }, window('B', 2, 1, [{ itemId: 'bad' }])),
		).toMatchObject({ reason: 'window_ordinal_mismatch', status: 'rejected' });
		expect(assembler.diagnostics.candidate).toBeNull();
		expect(assembler.diagnostics.committed).toMatchObject({ catalogRevision: 1, transferId: 'A' });

		const beforeReplay = assembler.diagnostics;
		expect(assembler.accept({ source: 'authority' }, begin('A', 1, 1))).toMatchObject({
			reason: 'revision_not_newer',
			status: 'rejected',
		});
		expect(assembler.diagnostics).toEqual(beforeReplay);
	});

	test('rejects equal and lower same-authority begins without changing a newer candidate', () => {
		const assembler = makeAssembler({ source: 'authority' });
		completeSingleEntry(assembler, { source: 'authority' }, 'active', 5, 'active');
		expect(assembler.accept({ source: 'authority' }, begin('candidate', 6, 1))).toMatchObject({
			status: 'accepted',
		});
		const beforeRejectedBegins = assembler.diagnostics;

		expect(assembler.accept({ source: 'authority' }, begin('equal', 6, 1))).toMatchObject({
			reason: 'revision_not_newer',
			status: 'rejected',
		});
		expect(assembler.accept({ source: 'authority' }, begin('lower', 4, 1))).toMatchObject({
			reason: 'revision_not_newer',
			status: 'rejected',
		});
		expect(assembler.diagnostics).toEqual(beforeRejectedBegins);
	});

	test.each([
		{
			defect: 'duplicate window',
			exercise: (
				assembler: MetadataCatalogAssembler<{ readonly itemId: string }, FixtureAuthority>,
			): MetadataCatalogAssemblerResult<{ readonly itemId: string }, FixtureAuthority> => {
				assembler.accept({ source: 'authority' }, begin('candidate', 2, 2));
				assembler.accept({ source: 'authority' }, window('candidate', 2, 0, [{ itemId: 'one' }]));
				return assembler.accept(
					{ source: 'authority' },
					window('candidate', 2, 0, [{ itemId: 'duplicate' }]),
				);
			},
			reason: 'window_ordinal_mismatch',
		},
		{
			defect: 'out-of-order window',
			exercise: (
				assembler: MetadataCatalogAssembler<{ readonly itemId: string }, FixtureAuthority>,
			): MetadataCatalogAssemblerResult<{ readonly itemId: string }, FixtureAuthority> => {
				assembler.accept({ source: 'authority' }, begin('candidate', 2, 2));
				return assembler.accept(
					{ source: 'authority' },
					window('candidate', 2, 1, [{ itemId: 'two' }]),
				);
			},
			reason: 'window_ordinal_mismatch',
		},
		{
			defect: 'missing window at commit',
			exercise: (
				assembler: MetadataCatalogAssembler<{ readonly itemId: string }, FixtureAuthority>,
			): MetadataCatalogAssemblerResult<{ readonly itemId: string }, FixtureAuthority> => {
				assembler.accept({ source: 'authority' }, begin('candidate', 2, 2));
				assembler.accept({ source: 'authority' }, window('candidate', 2, 0, [{ itemId: 'one' }]));
				return assembler.accept({ source: 'authority' }, commit('candidate', 2, 2, 2));
			},
			reason: 'commit_count_mismatch',
		},
		{
			defect: 'wrong commit entry count',
			exercise: (
				assembler: MetadataCatalogAssembler<{ readonly itemId: string }, FixtureAuthority>,
			): MetadataCatalogAssemblerResult<{ readonly itemId: string }, FixtureAuthority> => {
				assembler.accept({ source: 'authority' }, begin('candidate', 2, 1));
				assembler.accept({ source: 'authority' }, window('candidate', 2, 0, [{ itemId: 'one' }]));
				return assembler.accept({ source: 'authority' }, commit('candidate', 2, 1, 0));
			},
			reason: 'commit_count_mismatch',
		},
	] as const)('discards only the current candidate for $defect', ({ exercise, reason }) => {
		const assembler = makeAssembler({ source: 'authority' });
		completeSingleEntry(assembler, { source: 'authority' }, 'active', 1, 'active');

		expect(exercise(assembler)).toMatchObject({ reason, status: 'rejected' });
		expect(assembler.diagnostics.candidate).toBeNull();
		expect(assembler.diagnostics.committed).toEqual({
			catalogRevision: 1,
			transferId: 'active',
		});
	});

	test('discards an explicit entry-count overflow beyond the begin declaration', () => {
		const assembler = makeAssembler({ source: 'authority' });
		completeSingleEntry(assembler, { source: 'authority' }, 'active', 1, 'active');
		assembler.accept({ source: 'authority' }, begin('candidate', 2, 1));

		expect(
			assembler.accept(
				{ source: 'authority' },
				window('candidate', 2, 0, [{ itemId: 'one' }, { itemId: 'two' }]),
			),
		).toMatchObject({ reason: 'entry_count_exceeded', status: 'rejected' });
		expect(assembler.diagnostics.candidate).toBeNull();
		expect(assembler.diagnostics.committed).toMatchObject({ transferId: 'active' });
	});

	test('retires authority, candidate, and numeric baseline until explicit replacement', () => {
		const assembler = makeAssembler({ source: 'old' });
		completeSingleEntry(assembler, { source: 'old' }, 'old-active', 99, 'active');
		assembler.accept({ source: 'old' }, begin('old-candidate', 100, 1));

		assembler.retireExpectedAuthority();
		expect(assembler.diagnostics).toEqual({ candidate: null, committed: null });
		expect(assembler.accept({ source: 'old' }, begin('after-retire', 101, 0))).toMatchObject({
			reason: 'unexpected_authority',
			status: 'rejected',
		});

		assembler.replaceExpectedAuthority({ source: 'new' });
		expect(assembler.accept({ source: 'new' }, begin('new-low', 1, 0))).toMatchObject({
			status: 'accepted',
		});
	});

	test('malformed current identity discards only current while malformed noncurrent stays isolated', () => {
		const assembler = makeAssembler({ source: 'authority' });
		assembler.accept({ source: 'authority' }, begin('current', 2, 1));

		expect(
			assembler.accept(
				{ source: 'authority' },
				{
					catalogRevision: 2,
					entries: [],
					kind: 'catalog.window',
					transferId: 'current',
					windowOrdinal: 0,
				},
			),
		).toMatchObject({ reason: 'malformed_transfer', status: 'rejected' });
		expect(assembler.diagnostics.candidate).toBeNull();

		assembler.accept({ source: 'authority' }, begin('newer', 3, 1));
		const beforeNoncurrentDefect = assembler.diagnostics;
		expect(
			assembler.accept(
				{ source: 'authority' },
				{
					catalogRevision: 2,
					entries: [],
					kind: 'catalog.window',
					transferId: 'obsolete',
					windowOrdinal: 0,
				},
			),
		).toMatchObject({ reason: 'malformed_transfer', status: 'rejected' });
		expect(assembler.diagnostics).toEqual(beforeNoncurrentDefect);
	});

	test('resets numeric precedence only for an explicitly replaced authority', () => {
		const assembler = makeAssembler({ source: 'old' });
		expect(completeSingleEntry(assembler, { source: 'old' }, 'old-99', 99, 'old')).toMatchObject({
			status: 'completed',
		});

		assembler.replaceExpectedAuthority({ source: 'new' });
		expect(assembler.diagnostics.committed).toBeNull();
		expect(assembler.accept({ source: 'old' }, begin('old-100', 100, 0))).toMatchObject({
			reason: 'unexpected_authority',
			status: 'rejected',
		});
		expect(assembler.accept({ source: 'new' }, begin('new-1', 1, 0))).toMatchObject({
			status: 'accepted',
		});
		expect(assembler.accept({ source: 'new' }, commit('new-1', 1, 0, 0))).toMatchObject({
			status: 'completed',
		});
	});

	test('enforces aggregate capacity without retaining entries beyond the candidate', () => {
		const exactAssembler = makeAssembler({ source: 'authority' }, 31, 2);
		expect(exactAssembler.accept({ source: 'authority' }, begin('exact', 1, 2))).toMatchObject({
			status: 'accepted',
		});
		expect(
			exactAssembler.accept(
				{ source: 'authority' },
				window('exact', 1, 0, [{ itemId: 'a' }, { itemId: 'bbbb' }]),
			),
		).toMatchObject({ status: 'accepted' });
		expect(exactAssembler.diagnostics.candidate).toMatchObject({
			encodedEntryBytes: 31,
			entryCount: 2,
		});
		expect(exactAssembler.accept({ source: 'authority' }, commit('exact', 1, 1, 2))).toMatchObject({
			status: 'completed',
		});

		const assembler = makeAssembler({ source: 'authority' }, 30, 2);
		expect(assembler.accept({ source: 'authority' }, begin('bounded', 1, 2))).toMatchObject({
			status: 'accepted',
		});
		expect(
			assembler.accept({ source: 'authority' }, window('bounded', 1, 0, [{ itemId: 'a' }])),
		).toMatchObject({ status: 'accepted' });
		expect(assembler.diagnostics.candidate).toMatchObject({ entryCount: 1 });
		expect(
			assembler.accept({ source: 'authority' }, window('bounded', 1, 1, [{ itemId: 'bbbb' }])),
		).toMatchObject({ reason: 'candidate_capacity_exceeded', status: 'rejected' });
		expect(assembler.diagnostics.candidate).toBeNull();
		expect(assembler.accept({ source: 'authority' }, begin('too-many', 2, 3))).toMatchObject({
			reason: 'candidate_capacity_exceeded',
			status: 'rejected',
		});
	});
});

function makeAssembler(
	expectedAuthority: FixtureAuthority,
	maximumCandidateBytes?: number,
	maximumEntryCount?: number,
): MetadataCatalogAssembler<{ readonly itemId: string }, FixtureAuthority> {
	return new MetadataCatalogAssembler({
		authoritiesEqual: (left, right) => left.source === right.source,
		entrySchema: fixtureEntrySchema,
		expectedAuthority,
		...(maximumCandidateBytes === undefined ? {} : { maximumCandidateBytes }),
		...(maximumEntryCount === undefined ? {} : { maximumEntryCount }),
	});
}

function completeSingleEntry(
	assembler: MetadataCatalogAssembler<{ readonly itemId: string }, FixtureAuthority>,
	authority: FixtureAuthority,
	transferId: string,
	catalogRevision: number,
	itemId: string,
): MetadataCatalogAssemblerResult<{ readonly itemId: string }, FixtureAuthority> {
	assembler.accept(authority, begin(transferId, catalogRevision, 1));
	assembler.accept(authority, window(transferId, catalogRevision, 0, [{ itemId }]));
	return assembler.accept(authority, commit(transferId, catalogRevision, 1, 1));
}

function begin(
	transferId: string,
	catalogRevision: number,
	expectedEntryCount: number,
): BridgeMetadataCatalogBegin {
	return { catalogRevision, expectedEntryCount, kind: 'catalog.begin', transferId } as const;
}

function window(
	transferId: string,
	catalogRevision: number,
	windowOrdinal: number,
	entries: readonly { readonly itemId: string }[],
): BridgeMetadataCatalogWindow<{ readonly itemId: string }> {
	return { catalogRevision, entries, kind: 'catalog.window', transferId, windowOrdinal } as const;
}

function commit(
	transferId: string,
	catalogRevision: number,
	windowCount: number,
	entryCount: number,
): BridgeMetadataCatalogCommit {
	return { catalogRevision, entryCount, kind: 'catalog.commit', transferId, windowCount } as const;
}
