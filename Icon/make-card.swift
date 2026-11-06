// Draws the social preview cards (docs/card.png, docs/card-zh.png).
//
//   swift Icon/make-card.swift
//
// 1200×630, the size Facebook, X and Slack expect. Drawn in code for the same
// reason as the app icon: the wording and the numbers can be changed here and
// the picture made again, instead of being patched in an image editor.

import AppKit

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let docs = here.deletingLastPathComponent().appendingPathComponent("docs")

let W: CGFloat = 1200, H: CGFloat = 630

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

let ink = color(0x16181c)
let bodyInk = color(0x3d4249)
let green = color(0x2ebd85)
let red = color(0xf6465d)
let white = NSColor(white: 0.96, alpha: 1)
let dim = NSColor(white: 0.88, alpha: 1)

/// One menu bar label, as the pieces it is drawn from: ticker, dollar sign,
/// price, change. Kept as pieces so the width can be measured before drawing.
func segments(_ ticker: String, _ price: String, _ change: String, up: Bool) -> [(String, NSFont, NSColor)] {
    [
        (ticker + " ", .systemFont(ofSize: 15, weight: .medium), white),
        ("$", .systemFont(ofSize: 15), dim),
        ("\u{2009}" + price, .monospacedDigitSystemFont(ofSize: 21, weight: .regular), white),
        (" " + change, .systemFont(ofSize: 15, weight: .medium), up ? green : red),
    ]
}

func width(of pieces: [(String, NSFont, NSColor)]) -> CGFloat {
    pieces.reduce(0) { $0 + ($1.0 as NSString).size(withAttributes: [.font: $1.1]).width }
}

func draw(_ pieces: [(String, NSFont, NSColor)], at x: CGFloat) {
    var cursor = x
    for (text, font, colour) in pieces {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        (text as NSString).draw(at: NSPoint(x: cursor, y: 0), withAttributes: attrs)
        cursor += (text as NSString).size(withAttributes: attrs).width
    }
}

@MainActor
func drawCard(headline: String, subline: String, panel: String, to name: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: W, height: H)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    color(0xf8f8f7).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // The menu bar: a dark strip, prices right-aligned, as in the app.
    let bar = NSRect(x: 0, y: H - 96, width: W, height: 96)
    color(0x2d2e32).setFill()
    bar.fill()

    // Right-aligned like a real menu bar, so the whole set is measured first.
    let labels = [
        segments("BTC", "80,356", "▲2.39%", up: true),
        segments("ETH", "2,414", "▲3.92%", up: true),
        segments("XAU", "4,118", "▲0.62%", up: true),
        segments("AAPL", "271.40", "▼0.31%", up: false),
    ]
    let gap: CGFloat = 40
    let total = labels.map(width(of:)).reduce(0, +) + gap * CGFloat(labels.count - 1)
    var x = W - 48 - total
    let baseline = bar.midY - 12
    for pieces in labels {
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: x, yBy: baseline)
        t.concat()
        draw(pieces, at: 0)
        NSGraphicsContext.restoreGraphicsState()
        x += width(of: pieces) + gap
    }

    // Wordmark, top left.
    let logo = NSRect(x: 80, y: 470, width: 34, height: 34)
    ink.setFill()
    NSBezierPath(roundedRect: logo, xRadius: 8, yRadius: 8).fill()
    let spark = NSBezierPath()
    spark.move(to: NSPoint(x: 86, y: 483))
    spark.line(to: NSPoint(x: 94, y: 491))
    spark.line(to: NSPoint(x: 100, y: 486))
    spark.line(to: NSPoint(x: 106, y: 495))
    spark.line(to: NSPoint(x: 112, y: 490))
    green.setStroke()
    spark.lineWidth = 2.4
    spark.lineJoinStyle = .round
    spark.stroke()

    ("PriceBar" as NSString).draw(
        at: NSPoint(x: 124, y: 476),
        withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: ink]
    )

    // Headline and one line under it.
    let titleFont = NSFont.systemFont(ofSize: headline.count > 12 ? 60 : 66, weight: .semibold)
    (headline as NSString).draw(
        at: NSPoint(x: 80, y: 336),
        withAttributes: [.font: titleFont, .foregroundColor: ink]
    )
    (subline as NSString).draw(
        at: NSPoint(x: 80, y: 286),
        withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: bodyInk]
    )

    // The real panel screenshot, on a white card with a soft shadow.
    let shot = docs.appendingPathComponent(panel)
    if let image = NSImage(contentsOf: shot) {
        let box = NSRect(x: 80, y: 60, width: 280, height: 158)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.12)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: box.insetBy(dx: -12, dy: -10), xRadius: 12, yRadius: 12).fill()
        NSGraphicsContext.restoreGraphicsState()
        image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: docs.appendingPathComponent(name))
    print("wrote docs/\(name) \(rep.pixelsWide)×\(rep.pixelsHigh)")
}

MainActor.assumeIsolated {
    // English keeps the plain name: it is the card on the page at /.
    drawCard(
        headline: "Prices in the menu bar.",
        subline: "Crypto, gold, silver, US stocks · 24h chart · alerts",
        panel: "panel@2x.png", to: "card.png"
    )
    drawCard(
        headline: "价格，就在菜单栏里。",
        subline: "币、黄金、白银、美股 · 24 小时走势 · 价格提醒",
        panel: "panel-zh@2x.png", to: "card-zh.png"
    )
}
