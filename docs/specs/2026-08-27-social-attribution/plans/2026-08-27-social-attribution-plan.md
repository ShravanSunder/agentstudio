# Agent Studio social attribution implementation plan

## Scope

Add the approved `/x`, `/yt`, and `/c` aggregate and short-code campaign routes
without changing homepage copy, media, layout, interaction, or install behavior.

## Work and proof

1. Extract the existing homepage composition into one shared Astro component.
   Prove `/` is byte-equivalent in meaningful body structure after extraction.
2. Add one typed campaign registry and deterministic four-character code
   derivation. Reject duplicate identities and collisions at build time.
3. Generate aggregate channel pages and registered campaign pages as direct
   static output. Unknown codes remain absent from the build.
4. Give `SiteShell` explicit canonical and social-URL inputs, defaulting to the
   current pathname. Campaign pages explicitly consolidate to `/`.
5. Update the shared document/social title without changing the approved card
   or page copy.
6. Add focused registry and built-route tests, including sitemap exclusion and
   unknown-code behavior.
7. Run the complete website quality gates, Cloudflare build, and prebuilt dry
   run. Inspect local production at desktop and phone sizes for unchanged page
   rendering.
8. Commit and push the exact verified artifact, record the rollback version,
   deploy through `cf`, and verify the custom domain.
9. Enable Cloudflare Web Analytics through the authorized account surface,
   perform one controlled campaign-path visit, and retain visible Path-report
   and Security Analytics evidence.
10. Verify the exact X campaign route in the real composer without publishing.
