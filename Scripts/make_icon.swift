// Genera Resources/AppIcon.icns dibujando el icono en vectorial (un plumero minimalista).
// Uso: swift Scripts/make_icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Pétalo (pluma) que sale del origen hacia +y.
func feather(length: CGFloat, width: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: .zero)
    p.curve(to: NSPoint(x: 0, y: length), controlPoint1: NSPoint(x: width, y: length * 0.25), controlPoint2: NSPoint(x: width * 0.85, y: length * 0.88))
    p.curve(to: .zero, controlPoint1: NSPoint(x: -width * 0.85, y: length * 0.88), controlPoint2: NSPoint(x: -width, y: length * 0.25))
    p.close()
    return p
}

func draw() {
    // Lienzo de 1024 con el margen de la cuadrícula de iconos de macOS.
    let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tile = NSBezierPath(roundedRect: rect, xRadius: 184, yRadius: 184)
    NSGradient(starting: color(0x26262B), ending: color(0x0E0E10))!.draw(in: tile, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colors: [color(0x2DD4BF, 0.22), color(0x2DD4BF, 0)])!
        .draw(fromCenter: NSPoint(x: 880, y: 900), radius: 0, toCenter: NSPoint(x: 880, y: 900), radius: 620, options: [])
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.08).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // Plumero dibujado en vertical y girado.
    let t = NSAffineTransform()
    t.translateX(by: 512, yBy: 512)
    t.rotate(byDegrees: -38)
    t.scale(by: 1.08)
    t.translateX(by: -512, yBy: -560)
    t.concat()

    // Mango
    color(0xE6E8EC).setFill()
    NSBezierPath(roundedRect: NSRect(x: 512 - 24, y: 200, width: 48, height: 380), xRadius: 24, yRadius: 24).fill()
    // Virola
    color(0x2DD4BF).setFill()
    NSBezierPath(roundedRect: NSRect(x: 512 - 42, y: 540, width: 84, height: 84), xRadius: 22, yRadius: 22).fill()

    // Plumas
    let feathers: [(angle: CGFloat, length: CGFloat, width: CGFloat, hex: UInt32)] = [
        (-50, 255, 58, 0x60A5FA), (50, 255, 58, 0xFBBF24),
        (-25, 300, 64, 0xF472B6), (25, 300, 64, 0x2DD4BF),
        (0, 335, 68, 0xF4F5F7),
    ]
    for f in feathers {
        NSGraphicsContext.saveGraphicsState()
        let r = NSAffineTransform()
        r.translateX(by: 512, yBy: 600)
        r.rotate(byDegrees: -f.angle)
        r.concat()
        color(f.hex).setFill()
        feather(length: f.length, width: f.width).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(size) / 1024)
    scale.concat()
    draw()
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(size: 1024).write(to: URL(fileURLWithPath: "build/icon_preview.png"))
