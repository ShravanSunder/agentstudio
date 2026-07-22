# Retired Bridge Diff Viewer Plan

> Status: retired historical note.
> Original date: 2026-02-23
> Retired: 2026-06-10
> Current foundation spec: [Bridge Review Foundation Spec](../superpowers/specs/2026-06-10-bridge-review-foundation.md)
> Current execution plan: [Bridge Agent Review Foundation Implementation Plan](2026-06-08-bridge-agent-review-foundation.md)
> Architecture companion: [Bridge Viewer Architecture](../architecture/bridge_viewer_architecture.md)

This file used to contain the old Bridge + diff viewer execution plan. It is no
longer an executable plan and must not be used for LUNA-337 implementation.

The useful design material was ported into the current foundation spec as
downstream architecture-plan inputs:

- Pierre CodeView as the future mixed file/diff scroll surface.
- Shiki highlighting through Pierre worker/highlighter infrastructure.
- Worker chunks served as packaged `agentstudio://app/*` assets.
- Trees-style path-first navigation using prepared or presorted input.
- Annotation anchors and markdown-capable review artifacts deferred to a later
  annotation plan.
- Agent review workflow as context/timeline exchange only, without source
  mutation.
- Security, performance, cancellation, stale-generation, and lifecycle
  hardening as downstream plans.

The old foundation vocabulary was removed instead of preserved inline because it
conflicted with the current model. Do not reintroduce:

- `DiffManifest(epoch, sourceId, orderedPaths, fileDescriptors)`
- `ContentHandle(fileId, epoch, contentHash, cacheKey, ...)`
- `agentstudio://resource/file/{fileId}?epoch=...`
- `BridgeDiffPackage` / `BridgeDiffEndpoint` as review-foundation contracts
- the split `LUNA-347 -> LUNA-337` foundation path

Current foundation vocabulary lives in the spec:

- `BridgeReviewQuery`
- `BridgeSourceEndpoint`
- `BridgeReviewCheckpoint`
- `BridgeViewFilter`
- `BridgeChangeGrouping`
- `BridgeProvenanceFilter`
- `BridgeReviewPackage`
- `BridgeReviewDelta`
- `BridgeReviewItemDescriptor`
- `BridgeContentHandle`
- `BridgeReviewGeneration`
- `BridgeReviewSourceProvider`

Future execution should happen through new architecture specs and plans, not by
reviving this retired file.
