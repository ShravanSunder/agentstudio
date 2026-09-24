import { describe, expect, test } from 'vitest';

import type { BridgeProductFileMemberGroup } from './bridge-product-file-member-group-contracts.js';
import { bridgeProductFileMetadataEventSchema } from './bridge-product-subscription-contracts.js';

const source = {
	collectionToken: 'root-token-1',
	rootRevisionToken: null,
	sourceCursor: 'source-cursor-1',
	sourceId: 'source-1',
	subscriptionGeneration: 11,
} as const;

function memberGroup(groupPath: string, worktreeId: string): BridgeProductFileMemberGroup {
	return { groupPath, identityPrefix: `m${groupPath}.`, nestedMemberRelativeRoots: [], worktreeId };
}

/** Mirrored in Swift's `BridgeProductFileMetadataContractTests`. */
const memberGroupsEvent = {
	eventKind: 'file.memberGroups',
	groups: [
		{
			groupPath: 'app',
			identityPrefix: 'm0123456789ab.',
			nestedMemberRelativeRoots: ['.worktrees/feature'],
			worktreeId: '0198f3a2-0000-7000-8000-00000000000a',
		},
		memberGroup('feature', '0198f3a2-0000-7000-8000-00000000000b'),
	],
	membershipRevision: 2,
	openedDocuments: [
		{
			displayPath: 'Open Files/notes.md',
			documentLocation: '/Users/example/notes.md',
			identityPrefix: 'd0123456789ab.',
		},
	],
	source,
} as const;

describe('Bridge product File member-groups event contract', () => {
	test('accepts the native member-group list exactly', () => {
		expect(bridgeProductFileMetadataEventSchema.parse(memberGroupsEvent)).toEqual(
			memberGroupsEvent,
		);
	});

	test('rejects duplicate worktrees or group paths, unknown keys, missing nested roots and bad revisions', () => {
		const invalidEvents = [
			{
				...memberGroupsEvent,
				groups: [memberGroup('app', 'worktree-a'), memberGroup('app (2)', 'worktree-a')],
			},
			{
				...memberGroupsEvent,
				groups: [memberGroup('app', 'worktree-a'), memberGroup('app', 'worktree-b')],
			},
			{
				...memberGroupsEvent,
				groups: [{ ...memberGroup('app', 'worktree-a'), rootPath: '/tmp/app' }],
			},
			{ ...memberGroupsEvent, groups: [{ groupPath: 'app', worktreeId: 'worktree-a' }] },
			{ ...memberGroupsEvent, membershipRevision: -1 },
			{
				eventKind: memberGroupsEvent.eventKind,
				groups: memberGroupsEvent.groups,
				source,
			},
		];

		for (const invalidEvent of invalidEvents) {
			expect(bridgeProductFileMetadataEventSchema.safeParse(invalidEvent).success).toBe(false);
		}
	});
});
