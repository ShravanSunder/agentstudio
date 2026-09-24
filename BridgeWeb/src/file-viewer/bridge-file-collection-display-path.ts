import { bridgeProductIdentifierSchema } from '../core/comm-worker/bridge-product-contract-primitives.js';
import type { BridgeProductFileMemberGroup } from '../core/comm-worker/bridge-product-file-member-group-contracts.js';

/**
 * The Files display key of a worktree-relative location, or null when no
 * member lists it. Every handoff into Files that names a worktree-relative
 * path maps it here; no surface matches such a path against a display key
 * directly.
 *
 * Worktree ids compare case-insensitively: Review metadata spells them in
 * upper case, File metadata in lower case. A path inside a deeper nested
 * member belongs to that member, so this member does not list it.
 */
export function fileCollectionDisplayPath(
	groups: readonly BridgeProductFileMemberGroup[],
	worktreeId: string,
	relativePath: string,
): string | null {
	const group = fileCollectionMemberGroup(groups, worktreeId);
	if (group === null || relativePath.length === 0) return null;
	const ownedByNestedMember = group.nestedMemberRelativeRoots.some(
		(nestedRoot): boolean =>
			relativePath === nestedRoot || relativePath.startsWith(`${nestedRoot}/`),
	);
	return ownedByNestedMember ? null : `${group.groupPath}/${relativePath}`;
}

/**
 * The collection descriptor identity the page sees for a member's own
 * descriptor identity, as annotations store it, or null when the member is not
 * in the collection. The collection prefixes member identities; an identity
 * too long to prefix is digested natively and cannot be mapped here, so it is
 * null rather than guessed.
 */
export function fileCollectionDescriptorIdentity(
	groups: readonly BridgeProductFileMemberGroup[],
	worktreeId: string,
	memberDescriptorIdentity: string,
): string | null {
	const group = fileCollectionMemberGroup(groups, worktreeId);
	if (group === null || memberDescriptorIdentity.length === 0) return null;
	const identity = `${group.identityPrefix}${memberDescriptorIdentity}`;
	return bridgeProductIdentifierSchema.safeParse(identity).success ? identity : null;
}

/** A file location with the descriptor identity of the source it was read from. */
export interface BridgeFileCollectionSourceLocation {
	readonly path: string;
	readonly sourceIdentity: string;
}

/**
 * A worktree-scoped source (relative path and the member's own descriptor
 * identity, as annotations store it) under the collection's keys, or null when
 * Files does not list it.
 */
export function fileCollectionSourceLocation(
	groups: readonly BridgeProductFileMemberGroup[],
	worktreeId: string,
	storedSource: BridgeFileCollectionSourceLocation,
): BridgeFileCollectionSourceLocation | null {
	const path = fileCollectionDisplayPath(groups, worktreeId, storedSource.path);
	const sourceIdentity = fileCollectionDescriptorIdentity(
		groups,
		worktreeId,
		storedSource.sourceIdentity,
	);
	return path === null || sourceIdentity === null ? null : { path, sourceIdentity };
}

function fileCollectionMemberGroup(
	groups: readonly BridgeProductFileMemberGroup[],
	worktreeId: string,
): BridgeProductFileMemberGroup | null {
	const normalizedWorktreeId = worktreeId.toLowerCase();
	return (
		groups.find(
			(candidate): boolean => candidate.worktreeId.toLowerCase() === normalizedWorktreeId,
		) ?? null
	);
}

/** A file named by its worktree and its path relative to that worktree's root. */
export interface BridgeWorktreeFileLocation {
	readonly relativePath: string;
	readonly worktreeId: string;
}
