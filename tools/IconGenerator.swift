import AppKit
import Foundation

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let tile = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 218, yRadius: 218)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.07, blue: 0.30, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.52, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.45, blue: 0.63, alpha: 1),
])!
gradient.draw(in: tile, angle: -42)

NSGraphicsContext.saveGraphicsState()
tile.addClip()

for index in 0..<34 {
    let x = CGFloat((index * 193 + 71) % 900) + 62
    let y = CGFloat((index * 317 + 109) % 890) + 67
    let radius = CGFloat(index % 4 + 2)
    NSColor.white.withAlphaComponent(index % 3 == 0 ? 0.85 : 0.48).setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: radius * 2, height: radius * 2)).fill()
}

let orbitColor = NSColor(calibratedRed: 0.65, green: 0.90, blue: 1.0, alpha: 0.64)
orbitColor.setStroke()
for offset in [CGFloat(-74), 0, 74] {
    let orbit = NSBezierPath()
    orbit.lineWidth = 10
    orbit.move(to: NSPoint(x: 205, y: 512 + offset))
    orbit.curve(
        to: NSPoint(x: 819, y: 512 - offset),
        controlPoint1: NSPoint(x: 330, y: 835 + offset * 0.25),
        controlPoint2: NSPoint(x: 690, y: 190 - offset * 0.25)
    )
    orbit.stroke()
}

let core = NSBezierPath(ovalIn: NSRect(x: 372, y: 372, width: 280, height: 280))
NSGradient(colors: [
    NSColor(calibratedRed: 0.93, green: 0.98, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.75, blue: 0.97, alpha: 1),
])!.draw(in: core, relativeCenterPosition: .zero)

NSGraphicsContext.restoreGraphicsState()
image.unlockFocus()

guard
    let outputPath = CommandLine.arguments.dropFirst().first,
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to create icon\n", stderr)
    exit(1)
}

try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
