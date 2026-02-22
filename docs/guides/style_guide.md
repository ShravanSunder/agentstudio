# macOS Design & Style Guide

This guide outlines the principles and resources for creating a high-quality, modern, and minimalistic macOS application.

## Modern Minimalist Philosophy
Agent Studio aims for an aesthetic that prioritizes content over chrome, following the lead of "immaculate" macOS apps like **Things**, **Linear**, and **Ghostty**.

### Core Principles
- **Content Over Chrome**: Minimize visible UI controls until they are needed. Use whitespace and hierarchy to guide the eye.
- **Precision Typography**: Use **SF Pro** for all UI elements and **SF Mono** for terminal data, code, and technical logs.
- **Subtle Materials**: Leverage macOS vibrancy (`NSVisualEffectView`) for sidebars and toolbars to create depth and a "Liquid Glass" feel.
- **Keyboard-First UX**: Every action should be accessible via keyboard shortcuts. Follow the "Command Palette" pattern seen in Linear and Ghostty.
- **Purposeful Motion**: Animations should feel physical, snappy, and provide clear feedback (inspired by Things 3's interactions).
- **High Information Density**: Design for power users. Ensure data is compact and readable without feeling cluttered.

## Reference Apps
Use these apps as benchmarks for quality and style:
- **Things 3**: The gold standard for whitespace, typography, and delightful interactions on macOS.
- **Linear**: Best-in-class for high-density, keyboard-driven productivity tools.
- **Ghostty**: A reference for modern, native terminal integration and "zero-config" simplicity.
- **Claude**: Clean, focused interface for AI-driven workflows.

## Standard Layout Zones
- **Sidebar**: App-level navigation and project hierarchy. Use rounded-corner highlight styles and `.sidebar` material.
- **Toolbar**: Global actions and search. Use the "unified" titlebar style where the toolbar and title area merge.
- **Content Area**: The primary workspace (e.g., the terminal). Ensure it feels immersive and focused.

## Design Resources

### Official Apple Resources
- **Human Interface Guidelines (macOS)**: [https://developer.apple.com/design/human-interface-guidelines/macos](https://developer.apple.com/design/human-interface-guidelines/macos)
- **Apple Design Resources (Figma/Sketch)**: [https://developer.apple.com/design/resources/](https://developer.apple.com/design/resources/)
- **SF Symbols**: Use hierarchical or multi-color rendering for a modern look.

### Community & Expert Guides
- **Mario Guzman's Layout Guides**: [General Layout](https://marioaguzman.github.io/design/) and [Toolbars](https://marioaguzman.github.io/design/toolbars/).
- **Design+Code macOS Guide**: [Designing for macOS](https://designcode.io/ios-design-handbook-design-for-macos-big-sur/) (reference for general patterns; Agent Studio targets **macOS 26 only**).

## Implementation Best Practices

### SwiftUI Styling
- **Custom Modifiers**: Create reusable styles like `.agentStudioCard()` or `.minimalistButton()`.
- **Materials**: Use `.background(.ultraThinMaterial)` for modern, translucent overlays.
- **Transitions**: Use `.matchedGeometryEffect` for seamless UI state changes.

### AppKit Styling
- **NSVisualEffectView**: Use for vibrant backgrounds and sidebars.
- **Standard Spacing**: Follow the 8pt/16pt grid system for all alignments.
- **System Colors**: Always use semantic colors (e.g., `NSColor.secondaryLabelColor`) to ensure perfect Dark Mode support.

## Key WWDC Sessions
- **WWDC24**: [Tailor macOS windows with SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10148/)
