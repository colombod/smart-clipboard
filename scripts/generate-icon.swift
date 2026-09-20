import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func drawIcon(size: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 208, yRadius: 208)
    NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.55, blue: 0.42, alpha: 1), ending: NSColor(srgbRed: 0.12, green: 0.33, blue: 0.25, alpha: 1))!.draw(in: tile, angle: -65)
    NSColor.white.withAlphaComponent(0.96).setStroke()
    let frame = NSBezierPath(); frame.lineWidth = 44; frame.lineCapStyle = .round; frame.lineJoinStyle = .round
    for (x, y, dx, dy) in [(280.0,280.0,1.0,1.0),(744,280,-1,1),(280,744,1,-1),(744,744,-1,-1)] {
        frame.move(to: NSPoint(x: x, y: y + dy * 128))
        frame.line(to: NSPoint(x: x, y: y))
        frame.line(to: NSPoint(x: x + dx * 128, y: y))
    }
    frame.stroke()
    NSColor.white.withAlphaComponent(0.92).setFill()
    for (y, width) in [(574.0,254.0),(486.0,254.0),(398.0,164.0)] {
        NSBezierPath(roundedRect: NSRect(x: 386, y: y, width: width, height: 27), xRadius: 13.5, yRadius: 13.5).fill()
    }
    image.unlockFocus()
    return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size).write(to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2).write(to: destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
