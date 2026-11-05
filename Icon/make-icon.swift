// Draws the app icon and writes Icon/AppIcon.icns.
//
//   swift Icon/make-icon.swift
//
// Drawn in code rather than kept as an exported picture, so that a colour or
// a curve can be changed here and the icon made again, every size from the
// same drawing. The shape follows the macOS icon grid: an 824-point rounded
// square centred on a 1024 canvas, with room around it for the shadow.

import AppKit

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let corner: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

/// The green the app draws a rise in: Binance's.
let green = color(0x2ebd85)

/// The price line, left to right, as fractions of the chart: a day that
/// wobbles and ends higher than it began.
let points: [(CGFloat, CGFloat)] = [
    (0.00, 0.16), (0.17, 0.34), (0.32, 0.26), (0.50, 0.50),
    (0.64, 0.43), (0.82, 0.70), (1.00, 0.86),
]

func draw(in context: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let shape = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // The shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.32))
    context.addPath(shape)
    context.setFillColor(color(0x161b25))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()

    // The tile: graphite, lighter at the top.
    let background = CGGradient(colorsSpace: space, colors: [color(0x2b3343), color(0x0f131a)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    // The menu bar across the top, with a price in it: a code, then a
    // green arrow and its figure.
    let barHeight: CGFloat = 156
    let bar = CGRect(x: body.minX, y: body.maxY - barHeight, width: body.width, height: barHeight)
    context.setFillColor(color(0xffffff, 0.07))
    context.fill(bar)
    context.setFillColor(color(0xffffff, 0.10))
    context.fill(CGRect(x: bar.minX, y: bar.minY - 3, width: bar.width, height: 3))

    let pillHeight: CGFloat = 34
    let pillY = bar.midY - pillHeight / 2 + 6
    func pill(x: CGFloat, width: CGFloat, fill: CGColor) {
        let rect = CGRect(x: x, y: pillY, width: width, height: pillHeight)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil))
        context.setFillColor(fill)
        context.fillPath()
    }
    pill(x: 196, width: 96, fill: color(0xffffff, 0.42))
    pill(x: 312, width: 186, fill: color(0xffffff, 0.78))
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 534, y: pillY + 2))
    arrow.addLine(to: CGPoint(x: 574, y: pillY + 2))
    arrow.addLine(to: CGPoint(x: 554, y: pillY + pillHeight + 2))
    arrow.closeSubpath()
    context.addPath(arrow)
    context.setFillColor(green)
    context.fillPath()
    pill(x: 586, width: 110, fill: green)

    // The chart under it.
    // It comes in from the left edge, the way a day's line runs on from
    // the day before, and stops short of the right one, where the price is.
    let chart = CGRect(x: body.minX - 20, y: body.minY + 150, width: body.width - 146, height: 430)

    // Faint grid lines, so that the line reads as a chart and not a squiggle.
    context.setStrokeColor(color(0xffffff, 0.05))
    context.setLineWidth(3)
    for step in 0...3 {
        let y = chart.minY + chart.height * CGFloat(step) / 3
        context.move(to: CGPoint(x: body.minX, y: y))
        context.addLine(to: CGPoint(x: body.maxX, y: y))
    }
    context.strokePath()

    let placed = points.map { CGPoint(x: chart.minX + chart.width * $0.0, y: chart.minY + chart.height * $0.1) }

    // A Catmull-Rom curve through the points: a price line drawn with
    // corners looks like a drawing of one.
    let line = CGMutablePath()
    line.move(to: placed[0])
    for index in 0..<(placed.count - 1) {
        let p0 = placed[max(index - 1, 0)]
        let p1 = placed[index]
        let p2 = placed[index + 1]
        let p3 = placed[min(index + 2, placed.count - 1)]
        let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        line.addCurve(to: p2, control1: c1, control2: c2)
    }

    // The area under the line, fading down into the tile, and out to the
    // right before it reaches the end of the line: a hard edge under the dot
    // reads as a bar chart.
    let area = line.mutableCopy()!
    area.addLine(to: CGPoint(x: placed.last!.x, y: body.minY))
    area.addLine(to: CGPoint(x: placed[0].x, y: body.minY))
    area.closeSubpath()
    context.saveGState()
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(area)
    context.clip()
    let fade = CGGradient(colorsSpace: space, colors: [color(0x2ebd85, 0.40), color(0x2ebd85, 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(fade, start: CGPoint(x: 0, y: chart.maxY), end: CGPoint(x: 0, y: body.minY + 60), options: [])
    context.setBlendMode(.destinationOut)
    let edge = CGGradient(colorsSpace: space, colors: [color(0x000000, 0), color(0x000000, 1)] as CFArray, locations: [0, 1])!
    let right = placed.last!.x
    context.drawLinearGradient(edge, start: CGPoint(x: right - 170, y: 0), end: CGPoint(x: right, y: 0), options: [.drawsAfterEndLocation])
    context.endTransparencyLayer()
    context.restoreGState()

    // The line, with a soft glow.
    context.saveGState()
    context.setShadow(offset: .zero, blur: 26, color: color(0x2ebd85, 0.55))
    context.addPath(line)
    context.setStrokeColor(green)
    context.setLineWidth(40)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    // Where the price is now.
    let end = placed.last!
    context.setFillColor(color(0x2ebd85, 0.28))
    context.fillEllipse(in: CGRect(x: end.x - 52, y: end.y - 52, width: 104, height: 104))
    context.setFillColor(color(0xffffff))
    context.fillEllipse(in: CGRect(x: end.x - 28, y: end.y - 28, width: 56, height: 56))

    context.restoreGState()

    // A hairline round the edge, lighter at the top, as the system's own
    // icons have.
    context.saveGState()
    context.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: corner - 1.5, cornerHeight: corner - 1.5, transform: nil))
    context.setStrokeColor(color(0xffffff, 0.12))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(in: context)
    return rep.representation(using: .png, properties: [:])!
}

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(size: 1024).write(to: here.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Icon/AppIcon.icns" : "iconutil failed")
