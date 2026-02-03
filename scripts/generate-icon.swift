#!/usr/bin/env swift

import AppKit
import Foundation

// Create a minimal coding-themed icon for AgentStudio
// Design: Code brackets "</>" with a subtle gradient background

func createIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    // Background - dark rounded rectangle
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = CGFloat(size) * 0.22
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient background - dark blue to purple
    let gradient = NSGradient(colors: [
        NSColor(red: 0.15, green: 0.15, blue: 0.25, alpha: 1.0),
        NSColor(red: 0.12, green: 0.12, blue: 0.20, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)

    // Draw code brackets "</>"
    let fontSize = CGFloat(size) * 0.35
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)

    let text = "</>"
    let textColor = NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0) // Light blue

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor
    ]

    let textSize = text.size(withAttributes: attributes)
    let textX = (CGFloat(size) - textSize.width) / 2
    let textY = (CGFloat(size) - textSize.height) / 2

    text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attributes)

    // Add subtle glow/accent
    let accentPath = NSBezierPath()
    let accentY = CGFloat(size) * 0.15
    let accentWidth = CGFloat(size) * 0.5
    let accentX = (CGFloat(size) - accentWidth) / 2
    accentPath.move(to: NSPoint(x: accentX, y: accentY))
    accentPath.line(to: NSPoint(x: accentX + accentWidth, y: accentY))

    NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.5).setStroke()
    accentPath.lineWidth = CGFloat(size) * 0.02
    accentPath.stroke()

    image.unlockFocus()

    return image
}

func saveIcon(image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to convert image")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Saved: \(path)")
    } catch {
        print("Failed to save \(path): \(error)")
    }
}

// Generate all required sizes
let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDir = "Sources/AgentStudio/Resources/AppIcon.iconset"

// Create iconset directory
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for size in sizes {
    let image = createIcon(size: size)

    // Standard resolution
    if size <= 512 {
        saveIcon(image: image, to: "\(outputDir)/icon_\(size)x\(size).png")
    }

    // Retina (2x) - half the size name
    let halfSize = size / 2
    if halfSize >= 16 {
        saveIcon(image: image, to: "\(outputDir)/icon_\(halfSize)x\(halfSize)@2x.png")
    }
}

// Also save 512x512@2x (1024px)
let largeImage = createIcon(size: 1024)
saveIcon(image: largeImage, to: "\(outputDir)/icon_512x512@2x.png")

print("\nIconset generated! Now run:")
print("iconutil -c icns \(outputDir) -o Sources/AgentStudio/Resources/AppIcon.icns")
