// `AgentStudioPrimitives` holds the pure, Foundation-only value helpers that the
// app and the `agentstudio-cli` executable both need (today: `UUIDv7`). It used
// to live inside Infrastructure, which forced the CLI to link Infrastructure's
// whole GRDB/OTel/libgit2 base for one symbol.
//
// Re-exporting it keeps every existing `import AgentStudioInfrastructure` call
// site compiling unchanged. Infrastructure remains the only publication point
// for app-side consumers; the CLI-side leaf targets depend on
// `AgentStudioPrimitives` directly instead.
@_exported import AgentStudioPrimitives
