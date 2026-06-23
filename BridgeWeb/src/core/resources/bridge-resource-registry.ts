import {
	bridgeAttachedResourceDescriptorSchema,
	type BridgeAttachedResourceDescriptor,
	type BridgeDescriptorRef,
	type BridgeIdentity,
	type BridgeResourceDescriptor,
} from '../models/bridge-resource-descriptor.js';
import type { BridgeAllowedResourceKindsByProtocol } from './bridge-resource-url.js';

export interface BridgeResourceDescriptorRegistryProps {
	readonly allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol;
}

export type BridgeResourceDescriptorRegisterResult =
	| { readonly ok: true }
	| {
			readonly ok: false;
			readonly reason:
				| 'descriptor_ref_mismatch'
				| 'descriptor_schema_invalid'
				| 'unregistered_protocol_or_kind';
	  };

export interface BridgeResourceDescriptorRegistry {
	register(
		attachedDescriptor: BridgeAttachedResourceDescriptor,
	): BridgeResourceDescriptorRegisterResult;
	lookup(ref: BridgeDescriptorRef): BridgeResourceDescriptor | null;
}

export function createBridgeResourceDescriptorRegistry(
	props: BridgeResourceDescriptorRegistryProps,
): BridgeResourceDescriptorRegistry {
	const descriptorsById = new Map<string, BridgeResourceDescriptor>();
	return {
		register(
			attachedDescriptor: BridgeAttachedResourceDescriptor,
		): BridgeResourceDescriptorRegisterResult {
			const parsedAttachedDescriptor =
				bridgeAttachedResourceDescriptorSchema.safeParse(attachedDescriptor);
			if (!parsedAttachedDescriptor.success) {
				return { ok: false, reason: 'descriptor_schema_invalid' };
			}
			const { ref, descriptor } = parsedAttachedDescriptor.data;
			if (!isRegisteredResourceKind(descriptor, props.allowedResourceKindsByProtocol)) {
				return { ok: false, reason: 'unregistered_protocol_or_kind' };
			}
			if (!descriptorMatchesRef(descriptor, ref)) {
				return { ok: false, reason: 'descriptor_ref_mismatch' };
			}
			descriptorsById.set(descriptor.descriptorId, descriptor);
			return { ok: true };
		},
		lookup(ref: BridgeDescriptorRef): BridgeResourceDescriptor | null {
			const descriptor = descriptorsById.get(ref.descriptorId);
			if (descriptor === undefined || !descriptorMatchesRef(descriptor, ref)) {
				return null;
			}
			return descriptor;
		},
	};
}

function isRegisteredResourceKind(
	descriptor: BridgeResourceDescriptor,
	allowedResourceKindsByProtocol: BridgeAllowedResourceKindsByProtocol,
): boolean {
	return allowedResourceKindsByProtocol[descriptor.protocol]?.has(descriptor.resourceKind) ?? false;
}

function descriptorMatchesRef(
	descriptor: BridgeResourceDescriptor,
	ref: BridgeDescriptorRef,
): boolean {
	return (
		descriptor.descriptorId === ref.descriptorId &&
		descriptor.protocol === ref.expectedProtocol &&
		descriptor.resourceKind === ref.expectedResourceKind &&
		identityMatches(descriptor.identity, ref.expectedIdentity)
	);
}

function identityMatches(left: BridgeIdentity, right: BridgeIdentity): boolean {
	return (
		left.paneId === right.paneId &&
		left.protocol === right.protocol &&
		left.sourceId === right.sourceId &&
		left.packageId === right.packageId &&
		left.generation === right.generation &&
		left.revision === right.revision &&
		left.streamId === right.streamId &&
		left.cursor === right.cursor
	);
}
