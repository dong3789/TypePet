import AppKit
import ImageIO

private let clipRows: [(key: String, title: String)] = [
    ("type", "타이핑"),
    ("fast", "빨리"),
    ("enter", "엔터"),
    ("back", "지우기"),
    ("rest", "쉴 때")
]

final class ThumbStrip: NSView {
    override var isFlipped: Bool { true }

    func show(urls: [URL], key: String, owner: CharacterEditor) {
        subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 0
        for (index, url) in urls.enumerated() {
            let imageView = NSImageView(frame: NSRect(x: x, y: 5, width: 36, height: 36))
            imageView.image = NSImage(contentsOf: url)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 6
            imageView.layer?.masksToBounds = true
            imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            imageView.layer?.borderWidth = 1
            imageView.layer?.borderColor = NSColor.separatorColor.cgColor
            addSubview(imageView)

            let close = NSButton(frame: NSRect(x: x + 22, y: 0, width: 16, height: 16))
            close.title = "×"
            close.isBordered = false
            close.font = .systemFont(ofSize: 12, weight: .bold)
            close.contentTintColor = .secondaryLabelColor
            close.tag = index
            close.identifier = NSUserInterfaceItemIdentifier(key)
            close.target = owner
            close.action = #selector(CharacterEditor.removeImage(_:))
            addSubview(close)
            x += 44
        }
        setFrameSize(NSSize(width: max(x, 4), height: 46))
    }
}

final class CharacterEditor: NSObject {
    static let shared = CharacterEditor()

    private var window: NSWindow?
    private var nameField: NSTextField!
    private var sizeSlider: NSSlider!
    private var sizeLabel: NSTextField!
    private var restSlider: NSSlider!
    private var restLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var strips: [String: ThumbStrip] = [:]
    private var files: [String: [URL]] = [:]
    private var folder: URL?
    private var loadedVisible = false

    var windowNumber: Int { window?.windowNumber ?? 0 }

    func show() {
        if window == nil { build() }
        let opening = window?.isVisible != true
        if opening || !loadedVisible {
            loadFromPrefs()
            loadedVisible = true
        }
        guard let window else { return }
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2))
        }
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func build() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 524),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "조절"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.window = window

        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18)
        ])

        let intro = NSTextField(wrappingLabelWithString: "크기와 쉬는 타이밍은 슬라이더로 바로 적용됩니다. 그림은 추가를 여러 번 눌러 이어 넣거나, 폴더에 직접 넣으세요.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        intro.preferredMaxLayoutWidth = 484
        stack.addArrangedSubview(intro)

        sizeSlider = NSSlider(value: 220, minValue: 80, maxValue: 400, target: self, action: #selector(sizeChanged))
        sizeSlider.isContinuous = true
        sizeSlider.controlSize = .large
        sizeLabel = valueLabel("220")
        stack.addArrangedSubview(sliderLine("크기", sizeSlider, sizeLabel))

        restSlider = NSSlider(value: 1.5, minValue: 0.3, maxValue: 5, target: self, action: #selector(restChanged))
        restSlider.isContinuous = true
        restSlider.controlSize = .large
        restLabel = valueLabel("1.5초")
        stack.addArrangedSubview(sliderLine("쉬는 타이밍", restSlider, restLabel))

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 484).isActive = true
        stack.addArrangedSubview(separator)

        nameField = NSTextField(string: "")
        nameField.placeholderString = "새 캐릭터"
        nameField.font = .systemFont(ofSize: 13)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let nameLabel = NSTextField(labelWithString: "이름")
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.widthAnchor.constraint(equalToConstant: 88).isActive = true
        let nameLine = NSStackView(views: [nameLabel, nameField])
        nameLine.orientation = .horizontal
        nameLine.alignment = .centerY
        stack.addArrangedSubview(nameLine)

        for row in clipRows {
            stack.addArrangedSubview(imageLine(key: row.key, title: row.title))
        }

        let rule = NSTextField(wrappingLabelWithString: "파일 이름  type_00 타이핑 · fast_00 빨리 · enter_00 엔터 · back_00 지우기 · rest_00 쉴 때")
        rule.font = .systemFont(ofSize: 12)
        rule.textColor = .secondaryLabelColor
        rule.preferredMaxLayoutWidth = 484
        stack.addArrangedSubview(rule)

        statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .labelColor
        statusLabel.preferredMaxLayoutWidth = 484
        stack.addArrangedSubview(statusLabel)

        let folderButton = NSButton(title: "폴더 열기", target: self, action: #selector(openFolder))
        folderButton.bezelStyle = .rounded
        let reloadButton = NSButton(title: "다시 읽기", target: self, action: #selector(reloadFolder))
        reloadButton.bezelStyle = .rounded
        let saveButton = NSButton(title: "저장하고 사용", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [folderButton, reloadButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        stack.addArrangedSubview(buttons)
    }

    private func sliderLine(_ title: String, _ slider: NSSlider, _ value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 88).isActive = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let line = NSStackView(views: [label, slider, value])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        return line
    }

    private func valueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true
        return label
    }

    private func imageLine(key: String, title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let strip = ThumbStrip(frame: NSRect(x: 0, y: 0, width: 4, height: 46))
        strips[key] = strip
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = strip
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.widthAnchor.constraint(equalToConstant: 300).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let add = NSButton(title: "추가", target: self, action: #selector(addImages(_:)))
        add.bezelStyle = .rounded
        add.identifier = NSUserInterfaceItemIdentifier(key)

        let line = NSStackView(views: [label, scroll, add])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        return line
    }

    private func loadFromPrefs() {
        let size = min(400, max(80, Prefs.size))
        sizeSlider.doubleValue = Double(size)
        sizeLabel.stringValue = "\(Int(size.rounded()))"
        let seconds = min(5, max(0.3, Double(Prefs.restMs) / 1000))
        restSlider.doubleValue = seconds
        restLabel.stringValue = String(format: "%.1f초", seconds)
        files = [:]
        folder = nil
        nameField.stringValue = ""
        if Prefs.packPath != "builtin" {
            let url = URL(fileURLWithPath: Prefs.packPath)
            if FileManager.default.fileExists(atPath: url.path) {
                folder = url
                nameField.stringValue = url.lastPathComponent
                files = SpritePack.groupedFiles(in: url)
            }
        }
        refreshStrips()
        if folder == nil {
            statusLabel.stringValue = "기본 캐릭터를 쓰는 중이에요. 슬라이더는 바로 적용되고, 그림을 넣으면 새 캐릭터가 됩니다."
        } else {
            statusLabel.stringValue = ""
        }
    }

    private func refreshStrips() {
        for row in clipRows {
            strips[row.key]?.show(urls: files[row.key] ?? [], key: row.key, owner: self)
        }
    }

    @objc private func sizeChanged() {
        let size = CGFloat(sizeSlider.doubleValue.rounded())
        sizeLabel.stringValue = "\(Int(size))"
        Prefs.size = size
        AppDelegate.shared.pet.setSize(size)
    }

    @objc private func restChanged() {
        let seconds = restSlider.doubleValue
        restLabel.stringValue = String(format: "%.1f초", seconds)
        Prefs.restMs = Int((seconds * 1000).rounded())
    }

    @objc private func addImages(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        let title = clipRows.first { $0.key == key }?.title ?? "그림"
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "추가"
        panel.message = "\(title) 그림을 고르세요. 한 번에 여러 장, 추가 버튼으로 이어서 넣을 수 있어요."
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let picked = panel.urls.filter { imageExts.contains($0.pathExtension.lowercased()) }
            guard !picked.isEmpty else { return }
            var stored: [URL] = []
            for url in picked {
                stored.append(contentsOf: self.materialize(url))
            }
            self.files[key, default: []].append(contentsOf: stored)
            self.refreshStrips()
            self.statusLabel.stringValue = "\(title) \(self.files[key]?.count ?? 0)장"
        }
    }

    @objc func removeImage(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        var list = files[key] ?? []
        guard sender.tag >= 0, sender.tag < list.count else { return }
        list.remove(at: sender.tag)
        files[key] = list
        refreshStrips()
    }

    @objc private func openFolder() {
        let dest = ensureFolder()
        try? namingRule.write(to: dest.appendingPathComponent("이름규칙.txt"), atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(dest)
        statusLabel.stringValue = "폴더를 열었습니다. 그림을 넣은 뒤 다시 읽기를 누르세요."
    }

    @objc private func reloadFolder() {
        guard let folder else {
            statusLabel.stringValue = "먼저 폴더 열기로 위치를 만드세요."
            return
        }
        let grouped = SpritePack.groupedFiles(in: folder)
        let count = grouped.values.reduce(0) { $0 + $1.count }
        guard count > 0 else {
            statusLabel.stringValue = "폴더에 그림이 아직 없어요."
            return
        }
        files = grouped
        refreshStrips()
        Prefs.packPath = folder.path
        AppDelegate.shared.pet.showPack(id: folder.path)
        AppDelegate.shared.pet.applyChrome()
        statusLabel.stringValue = "폴더에서 \(count)장을 불러와 적용했습니다."
    }

    @objc private func save() {
        let count = files.values.reduce(0) { $0 + $1.count }
        guard count > 0 else {
            statusLabel.stringValue = "크기와 타이밍은 이미 적용됐어요. 그림은 추가하거나 폴더에 넣은 뒤 다시 읽기를 누르세요."
            return
        }
        let dest = ensureFolder()
        do {
            try write(files, to: dest)
            Prefs.packPath = dest.path
            AppDelegate.shared.pet.showPack(id: dest.path)
            AppDelegate.shared.pet.applyChrome()
            statusLabel.stringValue = "이 캐릭터를 쓰고 있어요."
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func ensureFolder() -> URL {
        if let folder { return folder }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let dest = makePackURL(named: typed.isEmpty ? "새 캐릭터" : typed)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        folder = dest
        if nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameField.stringValue = dest.lastPathComponent
        }
        return dest
    }

    private func write(_ groups: [String: [URL]], to dest: URL) throws {
        let fileManager = FileManager.default
        let temporary = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }
        for key in clips {
            for (index, source) in (groups[key] ?? []).enumerated() {
                let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
                let name = String(format: "%@_%02d.%@", key, index, ext)
                try fileManager.copyItem(at: source, to: temporary.appendingPathComponent(name))
            }
        }
        for file in SpritePack.imageFiles(in: dest) {
            let base = file.deletingPathExtension().lastPathComponent.lowercased()
            if clips.contains(where: { base.hasPrefix($0 + "_") }) {
                try fileManager.removeItem(at: file)
            }
        }
        let written = try fileManager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        for file in written {
            let target = dest.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: file, to: target)
        }
    }

    private func materialize(_ url: URL) -> [URL] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return [url] }
        let staging = supportURL().appendingPathComponent("staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var frames: [URL] = []
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .png, properties: [:]) else { continue }
            let dest = staging.appendingPathComponent("\(UUID().uuidString).png")
            guard (try? data.write(to: dest)) != nil else { continue }
            frames.append(dest)
        }
        return frames.isEmpty ? [url] : frames
    }
}
