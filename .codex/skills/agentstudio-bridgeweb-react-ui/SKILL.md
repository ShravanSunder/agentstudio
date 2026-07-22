---
name: agentstudio-bridgeweb-react-ui
description: Use when editing Agent Studio BridgeWeb React UI controls, chrome, toolbars, toggles, menus, inputs, or shared viewer components in this repo.
---

# Agent Studio BridgeWeb React UI

BridgeWeb React UI uses shadcn-style owned source primitives.

## Required Pattern

1. Inspect `BridgeWeb/src/components/ui/` before building a control.
2. If the needed shadcn primitive is missing, add the primitive source there.
3. Edit the owned primitive for Agent Studio tokens, sizing, focus, hover, and
   selected states.
4. Compose product-specific controls through a feature-neutral shared wrapper.
5. Keep FileViewer and ReviewViewer controls with the same interaction
   semantics on the same primitive layer and visual scale.

## Prohibited Pattern

Do not hand-roll route-local toggles, segmented controls, buttons, menus,
inputs, or toolbar widgets because one route has nearby markup. A local wrapper
around `Button` is not enough when the interaction is really a shadcn primitive
such as ToggleGroup, Tabs, DropdownMenu, or Input.

## Proof

Any visible BridgeWeb UI checkpoint must include browser/native screenshots and
geometry or interaction proof for the changed controls. DOM-only or jsdom-only
proof is not sufficient for visual UX.
