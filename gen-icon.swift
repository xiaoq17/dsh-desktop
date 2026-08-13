#!/usr/bin/env swift
// Generates the app icon (AppIcon.icns) by drawing with AppKit/CoreGraphics.
// Usage: swift gen-icon.swift <output-dir>
import AppKit
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    .appendingPathComponent("build", isDirectory: true)

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let baseSize: CGFloat = 1024
let size = NSSize(width: baseSize, height: baseSize)

func drawIcon(in ctx: CGContext, size: CGFloat, cornerRadius: CGFloat) {
    // Background: vertical gradient, dark navy -> deep blue
    let colors = [
        NSColor(calibratedRed: 0.043, green: 0.078, blue: 0.161, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.090, green: 0.173, blue: 0.353, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors,
                              locations: [0.0, 1.0])!

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = CGPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
                      cornerWidth: cornerRadius,
                      cornerHeight: cornerRadius,
                      transform: nil)
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: 0, y: 0),
                           options: [])

    // Accent glow: teal/cyan
    let accent = NSColor(calibratedRed: 0.188, green: 0.863, blue: 0.878, alpha: 1).cgColor

    // Draw a stylized "D" ring: an outer ring + inner bar
    let cx = size * 0.5
    let cy = size * 0.5
    let ringRadius = size * 0.26
    let barWidth = size * 0.115

    ctx.setStrokeColor(accent)
    ctx.setLineWidth(size * 0.085)
    ctx.setLineCap(.round)

    // Outer ring (arc from 0° to 270° -> a "D" shape opening to the right)
    let arcCenter = CGPoint(x: cx, y: cy)
    let startAngle: CGFloat = -.pi * 0.5
    let endAngle: CGFloat = .pi * 0.5
    ctx.addArc(center: arcCenter, radius: ringRadius,
               startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.strokePath()

    // Vertical bar of the "D"
    let barRect = CGRect(x: cx + ringRadius - barWidth * 0.45,
                         y: cy - ringRadius,
                         width: barWidth,
                         height: ringRadius * 2)
    let bar = CGPath(roundedRect: barRect,
                     cornerWidth: barWidth * 0.5,
                     cornerHeight: barWidth * 0.5,
                     transform: nil)
    ctx.addPath(bar)
    ctx.setFillColor(accent)
    ctx.fillPath()

    // Glow dot on the ring
    ctx.setFillColor(accent)
    ctx.fillEllipse(in: CGRect(x: cx - size * 0.045, y: cy - size * 0.045,
                               width: size * 0.09, height: size * 0.09))
}

// Render a bitmap at the given pixel size and write PNG.
func renderPNG(pixelSize: Int, to url: URL) {
    let w = pixelSize
    let h = pixelSize
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h,
                        bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    // Flip so drawing coordinates match AppKit
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)

    let s = CGFloat(w)
    drawIcon(in: ctx, size: s, cornerRadius: s * 0.2237)

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: url)
}

// Build the .iconset
let iconsetDir = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in specs {
    print("rendering \(name) (\(px)x\(px))")
    renderPNG(pixelSize: px, to: iconsetDir.appendingPathComponent(name))
}

// iconutil -> .icns
let icnsOut = outDir.appendingPathComponent("AppIcon.icns")
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsOut.path]
try proc.run()
proc.waitUntilExit()
print("Wrote \(icnsOut.path)")
