import AgentStudioAppIPC
import AgentStudioProgrammaticControl

struct AgentStudioIPCHumanApprovalPort: AppIPCPermissionApprovalPort {
    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        .ask
    }
}
