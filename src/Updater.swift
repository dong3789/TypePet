import AppKit

/// dong3789/TypePet GitHub 릴리스를 보고, 더 새 버전이면 zip을 받아 앱을 바꾼 뒤 다시 연다.
enum Updater {
    static let repo = "dong3789/TypePet"
    static let bundleId = "com.local.typepet"

    static var currentVersion: String {
        ProcessInfo.processInfo.environment["TYPEPET_FAKE_VERSION"]
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "0.0.0"
    }

    static var autoCheck: Bool {
        UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true
    }

    struct Release {
        let version: String
        let notes: String
        let zipURL: URL
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            text.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let next = parts(candidate)
        let now = parts(current)
        for index in 0..<max(next.count, now.count) {
            let left = index < next.count ? next[index] : 0
            let right = index < now.count ? now[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func scheduleAutomaticChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            if autoCheck { check(manual: false) }
        }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
            if autoCheck, Date().timeIntervalSince1970 - last > 86400 {
                check(manual: false)
            }
        }
    }

    static func check(manual: Bool) {
        if !manual {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        }
        fetchLatest { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    if manual { alert("업데이트를 확인하지 못했어요", error.localizedDescription) }
                case .success(let release):
                    guard isNewer(release.version, than: currentVersion) else {
                        if manual { alert("최신 버전이에요", "지금 쓰는 \(currentVersion)이 가장 최신이에요.") }
                        return
                    }
                    if !manual, UserDefaults.standard.string(forKey: "skippedVersion") == release.version {
                        return
                    }
                    let alert = NSAlert()
                    alert.messageText = "새 버전 \(release.version)이 나왔어요"
                    let notes = String(release.notes.prefix(600))
                    alert.informativeText = """
                    지금 버전: \(currentVersion)

                    업데이트하면 앱을 다시 시작합니다. 서명이 바뀌면 입력 모니터링을 한 번 껐다 켜야 할 수 있어요.
                    \(notes.isEmpty ? "" : "\n\(notes)")
                    """
                    alert.addButton(withTitle: "지금 업데이트")
                    alert.addButton(withTitle: "나중에")
                    activate()
                    let response = alert.runModal()
                    deactivate()
                    if response == .alertFirstButtonReturn {
                        install(release, relaunch: true) { error in
                            if let error { self.alert("업데이트에 실패했어요", error) }
                        }
                    } else if !manual {
                        UserDefaults.standard.set(release.version, forKey: "skippedVersion")
                    }
                }
            }
        }
    }

    static func fetchLatest(_ done: @escaping (Result<Release, Error>) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TypePet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                let message = status == 404 ? "아직 배포된 릴리스가 없어요." : "릴리스 정보를 가져오지 못했어요."
                done(.failure(error ?? NSError(domain: "TypePet", code: status, userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true })?["browser_download_url"] as? String,
                  let zipURL = URL(string: zip) else {
                done(.failure(NSError(domain: "TypePet", code: -2, userInfo: [NSLocalizedDescriptionKey: "릴리스에 zip 파일이 없어요."])))
                return
            }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            done(.success(Release(version: version, notes: json["body"] as? String ?? "", zipURL: zipURL)))
        }.resume()
    }

    static func install(_ release: Release, relaunch: Bool, done: @escaping (String?) -> Void) {
        URLSession.shared.downloadTask(with: release.zipURL) { temp, _, error in
            guard let temp else {
                DispatchQueue.main.async { done("다운로드 실패: \(error?.localizedDescription ?? "?")") }
                return
            }
            let fileManager = FileManager.default
            let work = fileManager.temporaryDirectory.appendingPathComponent("typepet-update-\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("TypePet.zip")
                try fileManager.moveItem(at: temp, to: zip)
                let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
                guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else {
                    DispatchQueue.main.async { done("압축을 풀지 못했어요.") }
                    return
                }
                guard let newApp = findApp(in: unpacked) else {
                    DispatchQueue.main.async { done("받은 파일 안에 앱이 없어요.") }
                    return
                }
                guard Bundle(url: newApp)?.bundleIdentifier == bundleId else {
                    DispatchQueue.main.async { done("받은 파일이 타입펫이 아니에요.") }
                    return
                }
                _ = run("/usr/bin/xattr", ["-cr", newApp.path])
                let target = Bundle.main.bundleURL
                let script = work.appendingPathComponent("swap.sh")
                let pid = relaunch ? ProcessInfo.processInfo.processIdentifier : 0
                let body = """
                #!/bin/bash
                PID=\(pid)
                while [ "$PID" != "0" ] && kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
                rm -rf \(shellQuote(target.path + ".old"))
                mv \(shellQuote(target.path)) \(shellQuote(target.path + ".old")) 2>/dev/null || true
                if /usr/bin/ditto \(shellQuote(newApp.path)) \(shellQuote(target.path)); then
                  rm -rf \(shellQuote(target.path + ".old"))
                else
                  mv \(shellQuote(target.path + ".old")) \(shellQuote(target.path))
                  exit 1
                fi
                /usr/bin/xattr -cr \(shellQuote(target.path))
                \(relaunch ? "/usr/bin/open \(shellQuote(target.path))" : "true")
                """
                try body.write(to: script, atomically: true, encoding: .utf8)
                let starter = Process()
                starter.executableURL = URL(fileURLWithPath: "/bin/bash")
                starter.arguments = ["-c", "nohup /bin/bash \(shellQuote(script.path)) >/tmp/typepet-update.log 2>&1 &"]
                try starter.run()
                starter.waitUntilExit()
                let started = starter.terminationStatus == 0
                DispatchQueue.main.async {
                    guard started else {
                        done("업데이트를 시작하지 못했어요.")
                        return
                    }
                    done(nil)
                    if relaunch { NSApp.terminate(nil) }
                }
            } catch {
                DispatchQueue.main.async { done(error.localizedDescription) }
            }
        }.resume()
    }

    static func runUpdateTest() {
        let cases: [(String, String, Bool)] = [
            ("1.2.0", "1.1.0", true),
            ("1.1.0", "1.1.0", false),
            ("1.0.9", "1.1.0", false),
            ("1.10.0", "1.9.0", true),
            ("v1.1.1", "1.1.0", true)
        ]
        for item in cases {
            let got = isNewer(item.0, than: item.1)
            print("cmp \(item.0) \(item.1) \(got)")
            if got != item.2 { exit(1) }
        }
        print("current: \(currentVersion)")
        fetchLatest { result in
            switch result {
            case .success(let release):
                print("latest: \(release.version) newer: \(isNewer(release.version, than: currentVersion))")
            case .failure(let error):
                print("fetch failed: \(error.localizedDescription)")
            }
            exit(0)
        }
        RunLoop.main.run()
    }

    private static func findApp(in folder: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension == "app", !url.path.contains("__MACOSX") { return url }
        }
        return nil
    }

    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func activate() {
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func deactivate() {
        NSApp.setActivationPolicy(.accessory)
    }

    private static func alert(_ title: String, _ text: String) {
        activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
        deactivate()
    }
}
