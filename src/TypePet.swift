import AppKit
import CoreGraphics
import ImageIO
import QuartzCore
import ServiceManagement

let clips = ["type", "fast", "rest", "enter", "back"]
let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]

enum Prefs {
    static let d = UserDefaults.standard

    static var size: CGFloat {
        get {
            let v = d.double(forKey: "size")
            return v == 0 ? 220 : CGFloat(v)
        }
        set { d.set(Double(newValue), forKey: "size") }
    }

    static var restMs: Int {
        get {
            let v = d.integer(forKey: "restMs")
            return v == 0 ? 1500 : v
        }
        set { d.set(newValue, forKey: "restMs") }
    }

    static var restAfter: Double { Double(restMs) / 1000 }

    static var onTop: Bool {
        get { d.object(forKey: "onTop") == nil ? true : d.bool(forKey: "onTop") }
        set { d.set(newValue, forKey: "onTop") }
    }

    static var lock: Bool {
        get { d.bool(forKey: "lock") }
        set { d.set(newValue, forKey: "lock") }
    }

    static var visible: Bool {
        get { d.object(forKey: "visible") == nil ? true : d.bool(forKey: "visible") }
        set { d.set(newValue, forKey: "visible") }
    }

    static var packPath: String {
        get { d.string(forKey: "packPath") ?? "builtin" }
        set { d.set(newValue, forKey: "packPath") }
    }

    static var origin: NSPoint? {
        get {
            guard d.object(forKey: "originX") != nil else { return nil }
            return NSPoint(x: d.double(forKey: "originX"), y: d.double(forKey: "originY"))
        }
        set {
            guard let newValue else { return }
            d.set(Double(newValue.x), forKey: "originX")
            d.set(Double(newValue.y), forKey: "originY")
        }
    }
}

func supportURL() -> URL {
    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("TypePet", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func packsURL() -> URL {
    let url = supportURL().appendingPathComponent("packs", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makePackURL(named name: String) -> URL {
    let cleaned = name.replacingOccurrences(of: "/", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let base = cleaned.isEmpty ? "새 캐릭터" : cleaned
    var dest = packsURL().appendingPathComponent(base, isDirectory: true)
    var n = 2
    while FileManager.default.fileExists(atPath: dest.path) {
        dest = packsURL().appendingPathComponent("\(base) \(n)", isDirectory: true)
        n += 1
    }
    return dest
}

let namingRule = """
그림 파일 이름

type_00.png   키를 누를 때마다. 이어서 type_01, type_02
fast_00.png   빨리 칠 때
enter_00.png  엔터
back_00.png   지우기
rest_00.png   쉴 때

그림을 넣은 뒤 조절 창에서 ‘다시 읽기’를 누르세요.
"""

func logLine(_ text: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/TypePet.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

struct SpritePack {
    var id: String
    var name: String
    var frames: [String: [CGImage]]

    func count(_ clip: String) -> Int { frames[clip]?.count ?? 0 }

    func image(_ clip: String, _ index: Int) -> CGImage? {
        let order = [clip, "type", "rest", "fast", "enter", "back"]
        for name in order {
            if let list = frames[name], !list.isEmpty {
                return list[index % list.count]
            }
        }
        return nil
    }

    static func load(url: URL, id: String, name: String) -> SpritePack? {
        var frames: [String: [CGImage]] = [:]
        let rootFiles = imageFiles(in: url)
        for prefix in clips {
            var images: [CGImage] = []
            let named = rootFiles.compactMap { file -> (Int, URL)? in
                guard let n = frameIndex(file.lastPathComponent, prefix: prefix) else { return nil }
                return (n, file)
            }.sorted { $0.0 < $1.0 }
            for (_, file) in named {
                images.append(contentsOf: loadFile(file))
            }
            let sub = url.appendingPathComponent(prefix, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
                let nested = imageFiles(in: sub).sorted {
                    let ia = frameIndex($0.lastPathComponent, prefix: prefix) ?? 0
                    let ib = frameIndex($1.lastPathComponent, prefix: prefix) ?? 0
                    if ia != ib { return ia < ib }
                    return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                for file in nested {
                    images.append(contentsOf: loadFile(file))
                }
            }
            if !images.isEmpty { frames[prefix] = images }
        }
        if frames.isEmpty {
            let loose = rootFiles.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            var images: [CGImage] = []
            for file in loose { images.append(contentsOf: loadFile(file)) }
            if images.isEmpty { return nil }
            frames["type"] = images
        }
        return SpritePack(id: id, name: name, frames: frames)
    }

    static func groupedFiles(in folder: URL) -> [String: [URL]] {
        let root = imageFiles(in: folder)
        var grouped: [String: [URL]] = [:]
        var used = Set<String>()
        for prefix in clips {
            var list = root.compactMap { file -> (Int, URL)? in
                guard let index = frameIndex(file.lastPathComponent, prefix: prefix) else { return nil }
                return (index, file)
            }.sorted { $0.0 < $1.0 }.map(\.1)
            for file in list { used.insert(file.path) }
            let sub = folder.appendingPathComponent(prefix, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
                let nested = imageFiles(in: sub).sorted {
                    let left = frameIndex($0.lastPathComponent, prefix: prefix) ?? 0
                    let right = frameIndex($1.lastPathComponent, prefix: prefix) ?? 0
                    if left != right { return left < right }
                    return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
                list.append(contentsOf: nested)
            }
            if !list.isEmpty { grouped[prefix] = list }
        }
        if grouped.isEmpty, !root.isEmpty {
            grouped["type"] = root
        } else if grouped["type"] == nil {
            let loose = root.filter { !used.contains($0.path) }
            if !loose.isEmpty { grouped["type"] = loose }
        }
        return grouped
    }

    static func imageFiles(in folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        return items.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return false }
            return imageExts.contains(url.pathExtension.lowercased())
        }
    }

    static func frameIndex(_ filename: String, prefix: String) -> Int? {
        let base = (filename as NSString).deletingPathExtension.lowercased()
        let head = prefix.lowercased() + "_"
        guard base.hasPrefix(head) else { return nil }
        let digits = base.dropFirst(head.count).prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private static func loadFile(_ url: URL) -> [CGImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200,
            kCGImageSourceShouldCacheImmediately: true
        ]
        var images: [CGImage] = []
        for i in 0..<count {
            if let image = CGImageSourceCreateThumbnailAtIndex(source, i, options as CFDictionary) {
                images.append(image)
            }
        }
        return images
    }
}

func builtinPack() -> SpritePack {
    let url = Bundle.main.resourceURL!.appendingPathComponent("builtin", isDirectory: true)
    return SpritePack.load(url: url, id: "builtin", name: "콩이")
        ?? SpritePack(id: "builtin", name: "콩이", frames: [:])
}

func loadPack(id: String) -> SpritePack {
    if id == "builtin" { return builtinPack() }
    let url = URL(fileURLWithPath: id)
    if let loaded = SpritePack.load(url: url, id: id, name: url.lastPathComponent) {
        return loaded
    }
    return builtinPack()
}

func installedPacks() -> [(id: String, name: String)] {
    var list: [(String, String)] = [("builtin", "콩이")]
    let folders = (try? FileManager.default.contentsOfDirectory(
        at: packsURL(),
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles])) ?? []
    for folder in folders.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { continue }
        list.append((folder.path, folder.lastPathComponent))
    }
    return list
}

final class KeyMonitor {
    static let shared = KeyMonitor()
    var onKey: ((Int) -> Void)?
    private(set) var count = 0
    private(set) var working = false
    private var port: CFMachPort?
    private var retry: Timer?
    private var loggedTapFailure = false

    var hasAccess: Bool { CGPreflightListenEventAccess() }

    func start() {
        _ = CGRequestListenEventAccess()
        install()
        guard port == nil else { return }
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] timer in
            self?.install()
            if self?.working == true { timer.invalidate() }
        }
        retry = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func install() {
        guard port == nil else { return }
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = KeyMonitor.shared.port {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
                DispatchQueue.main.async {
                    KeyMonitor.shared.count += 1
                    KeyMonitor.shared.onKey?(code)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil)
        else {
            if !loggedTapFailure {
                loggedTapFailure = true
                logLine("tap create failed access=\(hasAccess)")
            }
            return
        }
        port = created
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        working = true
        logLine("tap on access=\(hasAccess)")
    }
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    var onRightClick: ((NSEvent) -> Void)?
    let body = CALayer()
    let ground = CALayer()
    private var imageSize = CGSize(width: 1, height: 1)
    private var lift: CGFloat = 0
    private var squat: CGFloat = 1
    private var tilt: CGFloat = 0
    private var dragStart = NSPoint.zero
    private var windowStart = NSPoint.zero

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.clear.cgColor
        layer = root
        ground.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        body.contentsGravity = .resize
        body.magnificationFilter = .trilinear
        body.minificationFilter = .trilinear
        body.anchorPoint = CGPoint(x: 0.5, y: 0)
        root.addSublayer(ground)
        root.addSublayer(body)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    func show(_ image: CGImage?) {
        body.contents = image
        if let image {
            imageSize = CGSize(width: image.width, height: image.height)
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func pose(squat: CGFloat, tilt: CGFloat, lift: CGFloat) {
        self.squat = squat
        self.tilt = tilt
        self.lift = lift
        place()
    }

    override func layout() {
        super.layout()
        place()
    }

    private func place() {
        guard let root = layer else { return }
        let scale = window?.backingScaleFactor ?? 2
        root.contentsScale = scale
        body.contentsScale = scale
        ground.contentsScale = scale

        let box = bounds.insetBy(dx: bounds.width * 0.04, dy: bounds.height * 0.05)
        let fit = min(box.width / imageSize.width, box.height / imageSize.height)
        let w = imageSize.width * fit
        let h = imageSize.height * fit
        body.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        body.position = CGPoint(x: bounds.midX, y: box.minY + lift)
        var transform = CATransform3DMakeRotation(tilt * .pi / 180, 0, 0, 1)
        transform = CATransform3DScale(transform, 1 + (1 - squat) * 0.45, squat, 1)
        body.transform = transform

        let shadowWidth = bounds.width * 0.38 * max(0.55, 1 - lift / 180)
        let shadowHeight = max(7, bounds.height * 0.04)
        ground.bounds = CGRect(x: 0, y: 0, width: shadowWidth, height: shadowHeight)
        ground.cornerRadius = shadowHeight / 2
        ground.position = CGPoint(x: bounds.midX, y: box.minY + shadowHeight * 0.2)
        ground.opacity = Float(max(0.35, 1 - lift / 220))
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard !Prefs.lock, let window else { return }
        let current = NSEvent.mouseLocation
        var frame = window.frame
        frame.origin.x = windowStart.x + (current.x - dragStart.x)
        frame.origin.y = windowStart.y + (current.y - dragStart.y)
        window.setFrame(frame, display: true)
        Prefs.origin = frame.origin
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }
        AppDelegate.shared.importURLs(urls)
        return true
    }
}

final class Pet {
    let panel: PetPanel
    let view: PetView
    private(set) var pack = builtinPack()
    private var clip = "rest"
    private var frame = 0
    private var accum = 0.0
    private var lastKey = 0.0
    private var lastTick = CACurrentMediaTime()
    private var kick = 0.0
    private var phase = 0.0
    private var side = 1.0
    private var keyTimes: [Double] = []
    var onRightClick: ((NSEvent) -> Void)? {
        get { view.onRightClick }
        set { view.onRightClick = newValue }
    }

    init() {
        let side = Prefs.size
        panel = PetPanel(
            contentRect: NSRect(x: 200, y: 120, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = Prefs.onTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = Prefs.lock
        panel.isMovable = false
        view = PetView(frame: NSRect(origin: .zero, size: NSSize(width: side, height: side)))
        view.autoresizingMask = [.width, .height]
        panel.contentView = view
    }

    func start() {
        showPack(id: Prefs.packPath)
        placeInitially()
        applyChrome()
        if Prefs.visible { panel.orderFrontRegardless() }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    func showPack(id: String) {
        pack = loadPack(id: id)
        clip = "rest"
        frame = 0
        view.show(pack.image("rest", 0))
    }

    func applyChrome() {
        panel.level = Prefs.onTop ? .floating : .normal
        panel.ignoresMouseEvents = Prefs.lock
        if Prefs.visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func setSize(_ size: CGFloat) {
        Prefs.size = size
        var frame = panel.frame
        let origin = NSPoint(x: frame.midX - size / 2, y: frame.minY)
        frame = NSRect(origin: origin, size: NSSize(width: size, height: size))
        panel.setFrame(frame, display: true)
        view.needsLayout = true
    }

    func key(code: Int) {
        let now = CACurrentMediaTime()
        let gap = now - lastKey
        lastKey = now
        keyTimes.append(now)
        keyTimes.removeAll { now - $0 > 1 }
        let cps: Double
        if keyTimes.count >= 2, let first = keyTimes.first {
            cps = Double(keyTimes.count - 1) / max(0.2, now - first)
        } else {
            cps = 0
        }
        let fast = cps >= 4.5 || (gap > 0 && gap < 0.1)
        let enter = code == 36 || code == 76
        let back = code == 51 || code == 117

        if enter, pack.count("enter") > 0 {
            clip = "enter"
            frame = 0
            accum = 0
        } else if back, pack.count("back") > 0 {
            clip = "back"
            frame = 0
            accum = 0
        } else {
            let next: String
            if fast, pack.count("fast") > 0 {
                next = "fast"
            } else if pack.count("type") > 0 {
                next = "type"
            } else if pack.count("rest") > 0 {
                next = "rest"
            } else {
                next = "type"
            }
            if clip != next {
                clip = next
                frame = 0
            } else {
                let n = max(pack.count(clip), 1)
                frame = (frame + 1) % n
            }
        }
        kick = fast ? 1.15 : 1
        phase = 0.35 * side
        side = -side
        if enter { kick = 1.35 }
        view.show(pack.image(clip, frame))
    }

    func capture(to path: String) {
        view.layoutSubtreeIfNeeded()
        let scale = panel.backingScaleFactor
        let width = max(1, Int(view.bounds.width * scale))
        let height = max(1, Int(view.bounds.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0),
            let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext
        else { return }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        view.layer?.render(in: ctx)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    var frameIndex: Int { frame }
    var clipName: String { clip }
    var kickValue: Double { kick }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTick)
        lastTick = now
        if kick > 0 {
            kick *= exp(-7.5 * dt)
            phase += dt * 16
            if kick < 0.02 { kick = 0 }
        }
        let squat = 1 - kick * 0.18
        let tilt = sin(phase) * 10 * kick
        let lift = kick * (clip == "enter" ? 28 : 16)
        view.pose(squat: squat, tilt: tilt, lift: lift)

        if clip == "rest" || clip == "enter" || clip == "back" {
            accum += dt
            let fps = clip == "rest" ? 8.0 : (clip == "enter" ? 18.0 : 14.0)
            if accum >= 1 / fps {
                accum = 0
                let n = pack.count(clip)
                if n > 0 {
                    frame += 1
                    if frame >= n {
                        if clip == "rest" {
                            frame = 0
                        } else if now - lastKey < Prefs.restAfter {
                            clip = "type"
                            frame = 0
                        } else {
                            clip = "rest"
                            frame = 0
                        }
                    }
                    view.show(pack.image(clip, frame))
                }
            }
        } else if now - lastKey > Prefs.restAfter {
            clip = "rest"
            frame = 0
            accum = 0
            view.show(pack.image("rest", 0))
        }
    }

    private func placeInitially() {
        let size = Prefs.size
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let fallback = NSPoint(x: screen.maxX - size - 80, y: screen.minY + 48)
        let origin = Prefs.origin ?? fallback
        var frame = NSRect(origin: origin, size: NSSize(width: size, height: size))
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame.insetBy(dx: 30, dy: 30)) }
        if !onScreen { frame.origin = fallback }
        panel.setFrame(frame, display: true)
    }
}

@main
enum AppMain {
    static func main() {
        if CommandLine.arguments.contains("--update-test") {
            Updater.runUpdateTest()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate!
    let pet = Pet()
    var statusItem: NSStatusItem!

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        prepareSupport()
        let selftest = ProcessInfo.processInfo.environment["TYPEPET_SELFTEST"] == "1"
        let shotEditor = ProcessInfo.processInfo.environment["TYPEPET_SHOT_EDITOR"] == "1"
        pet.start()
        KeyMonitor.shared.onKey = { [weak self] code in self?.pet.key(code: code) }
        if !selftest && !shotEditor {
            KeyMonitor.shared.start()
            logLine("start access=\(KeyMonitor.shared.hasAccess)")
            if !KeyMonitor.shared.hasAccess, !Prefs.d.bool(forKey: "explained") {
                Prefs.d.set(true, forKey: "explained")
                explainPermission()
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "타입펫") {
            image.isTemplate = true
            statusItem.button?.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        pet.onRightClick = { [weak self] event in
            guard let self else { return }
            let menu = NSMenu()
            self.fill(menu)
            NSMenu.popUpContextMenu(menu, with: event, for: self.pet.view)
        }
        if selftest { scheduleSelfTest() }
        if shotEditor { scheduleEditorShot() }
        if !selftest && !shotEditor { Updater.scheduleAutomaticChecks() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu)
    }

    func fill(_ menu: NSMenu) {
        let access = KeyMonitor.shared.hasAccess
        let working = KeyMonitor.shared.working
        let status = NSMenuItem()
        if working {
            if KeyMonitor.shared.count == 0 {
                status.title = "키 입력 기다리는 중…"
            } else {
                status.title = "✅ 키 입력 감지 중 (\(KeyMonitor.shared.count)회)"
                status.state = .on
            }
            status.isEnabled = false
        } else if !access {
            status.title = "⚠️ 입력 모니터링을 껐다 켜 주세요"
            status.target = self
            status.action = #selector(openPrivacy)
        } else {
            status.title = "키 입력을 연결하는 중…"
            status.isEnabled = false
        }
        menu.addItem(status)
        menu.addItem(.separator())

        let hide = menu.addItem(withTitle: Prefs.visible ? "캐릭터 숨기기" : "캐릭터 보이기", action: #selector(toggleVisible), keyEquivalent: "")
        hide.target = self
        menu.addItem(withTitle: "조절…", action: #selector(showEditor), keyEquivalent: "").target = self

        let character = NSMenuItem(title: "캐릭터", action: nil, keyEquivalent: "")
        let characterMenu = NSMenu()
        let current = Prefs.packPath
        for item in installedPacks() {
            let row = characterMenu.addItem(withTitle: item.name, action: #selector(selectPack(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = item.id
            row.state = item.id == current ? .on : .off
        }
        characterMenu.addItem(.separator())
        let remove = characterMenu.addItem(withTitle: "이 캐릭터 지우기", action: #selector(removePack), keyEquivalent: "")
        remove.target = self
        remove.isEnabled = current != "builtin"
        character.submenu = characterMenu
        menu.addItem(character)
        menu.addItem(.separator())
        let top = menu.addItem(withTitle: "항상 맨 위에 보이기", action: #selector(toggleTop), keyEquivalent: "")
        top.target = self
        top.state = Prefs.onTop ? .on : .off
        let lock = menu.addItem(withTitle: "위치 고정 (클릭이 뒤로 통과)", action: #selector(toggleLock), keyEquivalent: "")
        lock.target = self
        lock.state = Prefs.lock ? .on : .off
        let login = menu.addItem(withTitle: "로그인할 때 자동으로 켜기", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "업데이트 확인…", action: #selector(checkUpdate), keyEquivalent: "").target = self
        let autoUpdate = menu.addItem(withTitle: "자동으로 업데이트 확인", action: #selector(toggleAutoUpdate), keyEquivalent: "")
        autoUpdate.target = self
        autoUpdate.state = Updater.autoCheck ? .on : .off
        menu.addItem(withTitle: "정보", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "종료", action: #selector(quit), keyEquivalent: "q").target = self
    }

    func importURLs(_ urls: [URL]) {
        var last: String?
        let directories = urls.filter { $0.hasDirectoryPath }
        let files = urls.filter { !$0.hasDirectoryPath }
        for directory in directories {
            if directory.standardizedFileURL.path.hasPrefix(packsURL().standardizedFileURL.path) {
                last = directory.path
                continue
            }
            let dest = makePackURL(named: directory.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: directory, to: dest)
                last = dest.path
            } catch {
                alert("가져오지 못했어요", info: error.localizedDescription)
            }
        }
        if !files.isEmpty {
            let raw = files.count == 1 ? files[0].deletingPathExtension().lastPathComponent : "가져온 이미지"
            let dest = makePackURL(named: raw.isEmpty ? "가져온 이미지" : raw)
            do {
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                for file in files {
                    let target = dest.appendingPathComponent(file.lastPathComponent)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.copyItem(at: file, to: target)
                }
                last = dest.path
            } catch {
                alert("가져오지 못했어요", info: error.localizedDescription)
            }
        }
        guard let last else { return }
        guard SpritePack.load(url: URL(fileURLWithPath: last), id: last, name: URL(fileURLWithPath: last).lastPathComponent) != nil else {
            alert("쓸 수 있는 이미지가 없어요", info: "png, jpg, gif, webp, heic 파일을 넣어 주세요.")
            return
        }
        Prefs.packPath = last
        pet.showPack(id: last)
        pet.applyChrome()
    }

    @objc func selectPack(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Prefs.packPath = id
        pet.showPack(id: id)
    }

    @objc func showEditor() {
        activate()
        CharacterEditor.shared.show()
    }

    @objc func removePack() {
        let id = Prefs.packPath
        let root = packsURL().standardizedFileURL.path
        let target = URL(fileURLWithPath: id).standardizedFileURL.path
        guard id != "builtin", target.hasPrefix(root + "/") else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: id))
        Prefs.packPath = "builtin"
        pet.showPack(id: "builtin")
    }

    @objc func toggleVisible() {
        Prefs.visible.toggle()
        pet.applyChrome()
    }

    @objc func toggleTop() {
        Prefs.onTop.toggle()
        pet.applyChrome()
    }

    @objc func toggleLock() {
        Prefs.lock.toggle()
        pet.applyChrome()
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("로그인 항목을 바꾸지 못했어요", info: "앱이 /Applications 안에 있어야 합니다.\n\(error.localizedDescription)")
        }
    }

    @objc func openPrivacy() {
        explainPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func checkUpdate() {
        Updater.check(manual: true)
    }

    @objc func toggleAutoUpdate() {
        UserDefaults.standard.set(!Updater.autoCheck, forKey: "autoUpdate")
    }

    @objc func showAbout() {
        alert("타입펫 1.0", info: """
키를 누를 때마다 화면 위 캐릭터가 따라 움직입니다.
엔터와 지우기는 다른 동작이고, 빨리 치면 빠른 동작으로 바뀝니다.

입력한 문장은 읽거나 저장하지 않습니다. 엔터와 지우개만 동작을 고를 때 쓰고, 키가 눌린 횟수만 셉니다.
위치는 고정하기 전에 캐릭터를 드래그해서 옮기면 됩니다.
""")
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func prepareSupport() {
        let note = supportURL().appendingPathComponent("읽는법.txt")
        if !FileManager.default.fileExists(atPath: note.path) {
            let text = """
타입펫 캐릭터 폴더는 packs 안에 있습니다.

type_00.png … 타이핑
fast_00.png … 빠른 타이핑
enter_00.png … 엔터
back_00.png … 지우기
rest_00.png … 쉬는 동작

이름 규칙이 없으면 폴더 안 이미지가 모두 타이핑 동작이 됩니다.
"""
            try? text.write(to: note, atomically: true, encoding: .utf8)
        }
    }

    private func explainPermission() {
        alert("키보드 입력 권한이 필요해요", info: """
캐릭터가 타이핑에 맞춰 움직이려면 입력 모니터링 권한이 필요합니다.

시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링에서 TypePet 스위치를 한 번 끄고 다시 켜 주세요. 이미 켜져 있어도, 앱을 다시 만들면 예전 권한과 서명이 어긋납니다.

입력한 글자는 보지도 저장하지도 않습니다. 키가 눌렸다는 신호와, 엔터·지우개 구분만 씁니다.

바꾼 뒤에는 앱을 한 번 종료했다가 다시 여세요.
""")
    }

    private func activate() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func alert(_ title: String, info: String) {
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.runModal()
    }

    private func scheduleEditorShot() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            CharacterEditor.shared.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let windowID = CGWindowID(CharacterEditor.shared.windowNumber)
                if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming]) {
                    let rep = NSBitmapImageRep(cgImage: image)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/typepet-editor.png"))
                }
                NSApp.terminate(nil)
            }
        }
    }

    private func scheduleSelfTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.pet.capture(to: "/tmp/typepet-rest.png")
            for _ in 0..<4 { self.pet.key(code: 0) }
            self.pet.capture(to: "/tmp/typepet-type.png")
            self.pet.key(code: 36)
            self.pet.capture(to: "/tmp/typepet-enter.png")
            let windowID = CGWindowID(self.pet.panel.windowNumber)
            if let screen = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming]) {
                let screenRep = NSBitmapImageRep(cgImage: screen)
                try? screenRep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/typepet-screen.png"))
            }
            let looseDir = URL(fileURLWithPath: "/tmp/typepet-pack-loose", isDirectory: true)
            let prefixDir = URL(fileURLWithPath: "/tmp/typepet-pack-prefix", isDirectory: true)
            let builtin = Bundle.main.resourceURL!.appendingPathComponent("builtin")
            try? FileManager.default.removeItem(at: looseDir)
            try? FileManager.default.removeItem(at: prefixDir)
            try? FileManager.default.createDirectory(at: looseDir, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: builtin.appendingPathComponent("type_00.png"), to: looseDir.appendingPathComponent("a.png"))
            try? FileManager.default.copyItem(at: builtin.appendingPathComponent("type_03.png"), to: looseDir.appendingPathComponent("b.png"))
            try? FileManager.default.copyItem(at: builtin.appendingPathComponent("type_00.png"), to: prefixDir.appendingPathComponent("type_00.png"))
            try? FileManager.default.copyItem(at: builtin.appendingPathComponent("enter_04.png"), to: prefixDir.appendingPathComponent("enter_03.png"))
            let loose = SpritePack.load(url: looseDir, id: "loose", name: "loose")
            let prefixed = SpritePack.load(url: prefixDir, id: "prefix", name: "prefix")
            let pack = self.pet.pack
            let text = "type=\(pack.count("type")) fast=\(pack.count("fast")) rest=\(pack.count("rest")) enter=\(pack.count("enter")) back=\(pack.count("back")) clip=\(self.pet.clipName) frame=\(self.pet.frameIndex) kick=\(String(format: "%.2f", self.pet.kickValue)) loose=\(loose?.count("type") ?? -1) prefixEnter=\(prefixed?.count("enter") ?? -1) prefixType=\(prefixed?.count("type") ?? -1) window=\(self.pet.panel.frame)"
            try? text.write(to: URL(fileURLWithPath: "/tmp/typepet-selftest.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}
