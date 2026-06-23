import type { BridgeProtocolRegistry } from '../models/bridge-protocol-registry.js';

const bridgeInternalHostKey = '__bridgeInternal';

export interface BridgeContentWorldRPCCommand {
	readonly id: string;
	readonly protocol: string;
	readonly method: string;
	readonly params: unknown;
}

interface BridgeContentWorldRPCEnvelope extends BridgeContentWorldRPCCommand {
	readonly jsonrpc: '2.0';
}

interface BridgeContentWorldInternal {
	readonly sendCommandJSON?: (commandJSON: string) => void;
}

export interface BridgeContentWorldHost {
	readonly [bridgeInternalHostKey]?: BridgeContentWorldInternal;
}

export interface SendBridgeContentWorldRPCProps {
	readonly command: BridgeContentWorldRPCCommand;
	readonly protocolRegistry: BridgeProtocolRegistry;
	readonly host: BridgeContentWorldHost;
}

export type SendBridgeContentWorldRPCResult =
	| { readonly ok: true }
	| {
			readonly ok: false;
			readonly reason: 'missing_bridge_world_sender' | 'unregistered_protocol_method';
	  };

export function sendBridgeContentWorldRPC(
	props: SendBridgeContentWorldRPCProps,
): SendBridgeContentWorldRPCResult {
	if (
		!props.protocolRegistry.isPrivilegedMethodAllowed(props.command.protocol, props.command.method)
	) {
		return { ok: false, reason: 'unregistered_protocol_method' };
	}

	const sendCommandJSON = props.host[bridgeInternalHostKey]?.sendCommandJSON;
	if (sendCommandJSON === undefined) {
		return { ok: false, reason: 'missing_bridge_world_sender' };
	}

	const envelope: BridgeContentWorldRPCEnvelope = {
		jsonrpc: '2.0',
		...props.command,
	};
	sendCommandJSON(JSON.stringify(envelope));
	return { ok: true };
}
