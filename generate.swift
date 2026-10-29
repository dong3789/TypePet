import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources", isDirectory: true)
let dir = root.appendingPathComponent("builtin", isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

struct Pose {
    var squat: CGFloat = 1
    var lift: CGFloat = 0
    var tilt: CGFloat = 0
    var mouth: CGFloat = 0.12
    var eye: CGFloat = 1
    var look: CGFloat = 0
    var arm: CGFloat = 0
}

func pose(clip: String, i: Int, n: Int) -> Pose {
    let t = n <= 1 ? 0 : CGFloat(i) / CGFloat(n)
    let wave = 0.5 - 0.5 * cos(t * .pi * 2)
    var p = Pose()
    switch clip {
    case "type":
        p.squat = 1 - 0.16 * wave
        p.mouth = 0.08 + 0.92 * wave
        p.arm = sin(t * .pi * 2)
    case "fast":
        p.squat = 1 - 0.26 * wave
        p.mouth = 0.35 + 0.65 * wave
        p.arm = sin(t * .pi * 4)
        p.tilt = 7 * sin(t * .pi * 2)
    case "rest":
        p.tilt = 4 * sin(t * .pi * 2)
        p.squat = 1 - 0.035 * wave
        p.mouth = 0.1
        p.arm = 0.2 * sin(t * .pi * 2)
        if i == n - 4 || i == n - 3 { p.eye = 0.08 }
    case "enter":
        let hop: [CGFloat] = [0, 36, 110, 180, 210, 160, 55, 0]
        let sq: [CGFloat] = [0.78, 0.96, 1.06, 1.08, 1.05, 1.0, 0.74, 0.88]
        p.lift = hop[i % hop.count]
        p.squat = sq[i % sq.count]
        p.mouth = (i > 0 && i < 6) ? 1 : 0.15
        p.arm = i < 4 ? -1 : 0.6
    case "back":
        p.tilt = -16 * sin(CGFloat(i) / CGFloat(max(n - 1, 1)) * .pi)
        p.look = -0.7
        p.mouth = 0.04
        p.squat = 0.92
        p.arm = -0.5
    default:
        break
    }
    return p
}

func rgb(_ hex: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
             green: CGFloat((hex >> 8) & 0xff) / 255,
             blue: CGFloat(hex & 0xff) / 255,
             alpha: a)
}

let ink = rgb(0x3A2918)
let W = 800
let H = 920

func fillOval(_ r: CGRect, _ c: NSColor, stroke: NSColor? = nil, width: CGFloat = 0) {
    let path = NSBezierPath(ovalIn: r)
    c.setFill()
    path.fill()
    if let stroke, width > 0 {
        stroke.setStroke()
        path.lineWidth = width
        path.stroke()
    }
}

func render(_ pose: Pose) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: W,
        pixelsHigh: H,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    let shadowScale = max(0.55, 1 - pose.lift / 280)
    let shadow = CGRect(x: 400 - 170 * shadowScale, y: 78, width: 340 * shadowScale, height: 36)
    fillOval(shadow, rgb(0x3A2918, 0.18))

    let bodyH = 520 * pose.squat
    let bodyW = 500 * (1 + (1 - pose.squat) * 0.6)
    let body = CGRect(x: 400 - bodyW / 2, y: 150 + pose.lift, width: bodyW, height: bodyH)
    let pivot = CGPoint(x: body.midX, y: body.minY + 30)

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.rotate(by: pose.tilt * .pi / 180)
    ctx.translateBy(x: -pivot.x, y: -pivot.y)

    let earR: CGFloat = 86
    fillOval(CGRect(x: body.minX + bodyW * 0.16, y: body.maxY - 78, width: earR * 1.7, height: earR * 1.85), rgb(0xFFD15A), stroke: ink, width: 10)
    fillOval(CGRect(x: body.maxX - bodyW * 0.16 - earR * 1.7, y: body.maxY - 78, width: earR * 1.7, height: earR * 1.85), rgb(0xFFD15A), stroke: ink, width: 10)
    fillOval(CGRect(x: body.minX + bodyW * 0.16 + 18, y: body.maxY - 58, width: earR * 1.15, height: earR * 1.2), rgb(0xFFE7B0))
    fillOval(CGRect(x: body.maxX - bodyW * 0.16 - earR * 1.7 + 28, y: body.maxY - 58, width: earR * 1.15, height: earR * 1.2), rgb(0xFFE7B0))

    fillOval(body, rgb(0xFFD15A), stroke: ink, width: 12)
    let belly = CGRect(x: body.midX - bodyW * 0.28, y: body.minY + bodyH * 0.12, width: bodyW * 0.56, height: bodyH * 0.42)
    fillOval(belly, rgb(0xFFF1C4))

    let footW = bodyW * 0.22
    let footH: CGFloat = 48
    fillOval(CGRect(x: body.midX - bodyW * 0.28, y: body.minY - 8, width: footW, height: footH), rgb(0xF0B43A), stroke: ink, width: 8)
    fillOval(CGRect(x: body.midX + bodyW * 0.06, y: body.minY - 8, width: footW, height: footH), rgb(0xF0B43A), stroke: ink, width: 8)

    let armW: CGFloat = 78
    let armH: CGFloat = 46
    let armY = body.minY + bodyH * 0.38
    let armSwing = pose.arm * 28
    fillOval(CGRect(x: body.minX - 18, y: armY + armSwing, width: armW, height: armH), rgb(0xFFC53D), stroke: ink, width: 8)
    fillOval(CGRect(x: body.maxX - armW + 18, y: armY - armSwing, width: armW, height: armH), rgb(0xFFC53D), stroke: ink, width: 8)

    let eyeW = bodyW * 0.16
    let eyeH = max(8, bodyH * 0.16 * pose.eye)
    let eyeY = body.minY + bodyH * 0.58 - eyeH / 2
    let look = pose.look * 16
    let leftEye = CGRect(x: body.midX - bodyW * 0.24 + look, y: eyeY, width: eyeW, height: eyeH)
    let rightEye = CGRect(x: body.midX + bodyW * 0.08 + look, y: eyeY, width: eyeW, height: eyeH)
    fillOval(leftEye, ink)
    fillOval(rightEye, ink)
    if pose.eye > 0.4 {
        fillOval(CGRect(x: leftEye.maxX - eyeW * 0.42, y: leftEye.maxY - eyeH * 0.42, width: eyeW * 0.28, height: eyeH * 0.28), rgb(0xFFFFFF))
        fillOval(CGRect(x: rightEye.maxX - eyeW * 0.42, y: rightEye.maxY - eyeH * 0.42, width: eyeW * 0.28, height: eyeH * 0.28), rgb(0xFFFFFF))
    }

    let cheek = bodyW * 0.11
    fillOval(CGRect(x: leftEye.minX - cheek * 0.2, y: leftEye.minY - cheek * 0.85, width: cheek, height: cheek * 0.62), rgb(0xFF8B9A, 0.9))
    fillOval(CGRect(x: rightEye.maxX - cheek * 0.8, y: rightEye.minY - cheek * 0.85, width: cheek, height: cheek * 0.62), rgb(0xFF8B9A, 0.9))

    let mouthW = bodyW * 0.22
    let mouthH = max(8, 18 + pose.mouth * bodyH * 0.12)
    let mouth = CGRect(x: body.midX - mouthW / 2 + look * 0.3, y: body.minY + bodyH * 0.34 - mouthH / 2, width: mouthW, height: mouthH)
    fillOval(mouth, rgb(0xE15A3A), stroke: ink, width: 6)
    if pose.mouth > 0.45 {
        fillOval(CGRect(x: mouth.minX + 8, y: mouth.minY + 4, width: mouth.width - 16, height: mouth.height * 0.45), rgb(0xFFB1A2))
    }

    let sprout = NSBezierPath()
    sprout.move(to: CGPoint(x: body.midX, y: body.maxY - 10))
    sprout.curve(to: CGPoint(x: body.midX + 34, y: body.maxY + 78),
                 controlPoint1: CGPoint(x: body.midX + 10, y: body.maxY + 30),
                 controlPoint2: CGPoint(x: body.midX + 8, y: body.maxY + 64))
    sprout.lineWidth = 12
    rgb(0x3E8F45).setStroke()
    sprout.stroke()
    fillOval(CGRect(x: body.midX + 8, y: body.maxY + 48, width: 54, height: 32), rgb(0x67B85C), stroke: ink, width: 6)

    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let clips = [("type", 8), ("fast", 6), ("rest", 12), ("enter", 8), ("back", 6)]
for (name, count) in clips {
    for i in 0..<count {
        let rep = render(pose(clip: name, i: i, n: count))
        let url = dir.appendingPathComponent(String(format: "%@_%02d.png", name, i))
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("png 실패 \(name) \(i)\n", stderr)
            exit(1)
        }
        try png.write(to: url)
    }
}

let iconRep = render(pose(clip: "type", i: 2, n: 8))
let iconURL = root.appendingPathComponent("icon-source.png")
try iconRep.representation(using: .png, properties: [:])!.write(to: iconURL)
fputs("frames ok \(dir.path)\n", stderr)
