import AppKit
import Darwin
import Foundation
import UniformTypeIdentifiers

private struct BackgroundAppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let port = "9224"
    private var chatGPTURL: URL {
        if let url = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
            .compactMap({ $0.bundleURL }).first { return url }
        for path in ["/Applications/ChatGPT.app", "/Applications/Codex.app"] {
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return URL(fileURLWithPath: "/Applications/ChatGPT.app")
    }
    private let defaults = UserDefaults.standard

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var modeItems: [String: NSMenuItem] = [:]
    private var transparencySlider: NSSlider!
    private var transparencyLabel: NSTextField!
    private var clarityMenuItem: NSMenuItem!
    private var transparencyWorkItem: DispatchWorkItem?
    private var isApplying = false
    private var isCheckingConnection = false
    private var recoveryTimer: Timer?
    private var automaticRestoreAttempted = false

    private var automaticRestoreEnabled: Bool {
        get {
            (defaults.object(forKey: "automaticRestoreEnabled") as? Bool)
                ?? (defaults.string(forKey: "backgroundMode") != nil)
        }
        set { defaults.set(newValue, forKey: "automaticRestoreEnabled") }
    }

    private var launchArguments: [String] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let profile = support.appendingPathComponent("Codex", isDirectory: true)
        return ["-na", chatGPTURL.path, "--args", "--user-data-dir=\(profile.path)",
                "--remote-debugging-address=127.0.0.1", "--remote-debugging-port=\(port)"]
    }

    private var helperURL: URL {
        Bundle.main.url(forResource: "helper", withExtension: "mjs")!
    }

    private var nodeURL: URL {
        chatGPTURL.appendingPathComponent("Contents/Resources/cua_node/bin/node")
    }

    private var transparency: Double {
        get {
            let saved = defaults.object(forKey: "backgroundTransparency") as? Double
            return min(1.00, max(0.10, saved ?? 0.70))
        }
        set {
            defaults.set(min(1.00, max(0.10, newValue)), forKey: "backgroundTransparency")
        }
    }

    private var keepBackgroundClear: Bool {
        get { defaults.bool(forKey: "keepBackgroundClear") }
        set { defaults.set(newValue, forKey: "keepBackgroundClear") }
    }

    private var clarityModeArgument: String {
        keepBackgroundClear ? "clear" : "linked"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard FileManager.default.fileExists(atPath: chatGPTURL.path) else {
            showError("没有找到 /Applications/ChatGPT.app，请先安装 Codex 桌面应用。")
            NSApp.terminate(nil)
            return
        }
        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
            showError("Codex 内置运行环境不可用，请更新或重新安装 ChatGPT.app。")
            NSApp.terminate(nil)
            return
        }

        configureStatusItem()
        if CommandLine.arguments.contains("--self-test") {
            let titles = menu.items.map { $0.title }.filter { !$0.isEmpty }
            print("menu=\(titles.joined(separator: "|"))")
            print("slider=\(transparencySlider.minValue)-\(transparencySlider.maxValue),value=\(transparencySlider.doubleValue)")
            print("keepBackgroundClear=\(keepBackgroundClear)")
            print("automaticRestoreEnabled=\(automaticRestoreEnabled)")
            print("launchArguments=\(launchArguments.joined(separator: "|"))")
            fflush(stdout)
            exit(0)
        }
        refreshStatus(restoreBackground: true)
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            self?.refreshStatus(restoreBackground: true)
        }
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshStatus()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Codex 动态背景")
        statusItem.button?.toolTip = "Codex 动态背景"

        menu = NSMenu(title: "Codex 动态背景")
        menu.delegate = self

        let titleItem = NSMenuItem(title: "Codex 动态背景", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        statusMenuItem = NSMenuItem(title: "状态：正在检查", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        addModeItem(title: "流动渐变 · 轻量", mode: "gradient", action: #selector(selectLightEffect(_:)))
        addModeItem(title: "极光 · 轻量", mode: "aurora", action: #selector(selectLightEffect(_:)))
        addModeItem(title: "柔光光斑 · 轻量", mode: "bokeh", action: #selector(selectLightEffect(_:)))
        addModeItem(title: "流星雨 · 轻量", mode: "meteors", action: #selector(selectLightEffect(_:)))
        menu.addItem(.separator())
        addModeItem(title: "宇宙星河", mode: "cosmos", action: #selector(selectCosmos))
        addModeItem(title: "动态粒子", mode: "particles", action: #selector(selectParticles))
        addModeItem(title: "选择照片…", mode: "image", action: #selector(selectImage))
        addModeItem(title: "选择视频…", mode: "video", action: #selector(selectVideo))

        menu.addItem(.separator())
        menu.addItem(makeTransparencyItem())

        clarityMenuItem = NSMenuItem(title: "背景始终清晰", action: #selector(toggleBackgroundClarity), keyEquivalent: "")
        clarityMenuItem.target = self
        clarityMenuItem.toolTip = "开启后，滑杆只改变界面透明度，照片和视频不会变暗或变模糊"
        clarityMenuItem.state = keepBackgroundClear ? .on : .off
        menu.addItem(clarityMenuItem)
        menu.addItem(.separator())

        let reapplyItem = NSMenuItem(title: "重新应用／修复连接", action: #selector(reapplyCurrentBackground), keyEquivalent: "r")
        reapplyItem.target = self
        menu.addItem(reapplyItem)

        let disableItem = NSMenuItem(title: "关闭动态背景", action: #selector(disableBackground), keyEquivalent: "")
        disableItem.target = self
        menu.addItem(disableItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出菜单栏助手", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateModeChecks()
    }

    private func addModeItem(title: String, mode: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = mode
        menu.addItem(item)
        modeItems[mode] = item
    }

    private func makeTransparencyItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))

        transparencyLabel = NSTextField(labelWithString: "")
        transparencyLabel.frame = NSRect(x: 14, y: 36, width: 250, height: 18)
        transparencyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        container.addSubview(transparencyLabel)

        transparencySlider = NSSlider(
            value: transparency,
            minValue: 0.10,
            maxValue: 1.00,
            target: self,
            action: #selector(transparencyChanged)
        )
        transparencySlider.frame = NSRect(x: 14, y: 7, width: 250, height: 24)
        transparencySlider.isContinuous = true
        updateTransparencyPresentation()
        container.addSubview(transparencySlider)

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func updateTransparencyPresentation() {
        let amount = Int((transparency * 100).rounded())
        if keepBackgroundClear {
            transparencyLabel?.stringValue = "界面透明度  \(amount)%"
            transparencySlider?.toolTip = "照片和视频保持清晰；这里只调整界面透明度"
        } else {
            transparencyLabel?.stringValue = "背景可见度  \(amount)%"
            transparencySlider?.toolTip = "数值越高，照片和视频越清晰"
        }
    }

    private func updateModeChecks() {
        let selectedMode = defaults.string(forKey: "backgroundMode")
        for (mode, item) in modeItems {
            item.state = mode == selectedMode ? .on : .off
        }
    }

    private func setBusy(_ busy: Bool, text: String? = nil) {
        isApplying = busy
        for item in modeItems.values { item.isEnabled = !busy }
        transparencySlider?.isEnabled = !busy
        clarityMenuItem?.isEnabled = !busy
        if let text { statusMenuItem.title = "状态：\(text)" }
        statusItem.button?.image = NSImage(
            systemSymbolName: busy ? "sparkles.rectangle.stack" : "sparkles",
            accessibilityDescription: "Codex 动态背景"
        )
    }

    @objc private func selectLightEffect(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? String else { return }
        applyBackground(mode: mode, path: nil)
    }

    @objc private func selectCosmos() {
        applyBackground(mode: "cosmos", path: nil)
    }

    @objc private func selectParticles() {
        applyBackground(mode: "particles", path: nil)
    }

    @objc private func selectImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择背景照片"
        panel.prompt = "设为背景"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["png", "jpg", "jpeg", "webp", "gif", "heic", "heif"]
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            applyBackground(mode: "image", path: try preparedImagePath(for: url))
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func selectVideo() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择背景视频"
        panel.prompt = "设为背景"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["mp4", "mov", "m4v", "webm"]
            .compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyBackground(mode: "video", path: url.path)
    }

    @objc private func reapplyCurrentBackground() {
        let mode = defaults.string(forKey: "backgroundMode") ?? "gradient"
        let path = defaults.string(forKey: "backgroundPath")
        if ["image", "video"].contains(mode), (path == nil || !FileManager.default.fileExists(atPath: path!)) {
            showError("原来的背景文件已被移动或删除，请重新选择。")
            return
        }
        applyBackground(mode: mode, path: path)
    }

    @objc private func transparencyChanged() {
        transparency = transparencySlider.doubleValue
        updateTransparencyPresentation()
        transparencyWorkItem?.cancel()

        let value = transparency
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.debugPortReady() else { return }
            self.runHelper(["set-transparency", self.port, String(format: "%.2f", value), self.clarityModeArgument]) { _ in }
        }
        transparencyWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    @objc private func toggleBackgroundClarity() {
        keepBackgroundClear.toggle()
        clarityMenuItem.state = keepBackgroundClear ? .on : .off
        updateTransparencyPresentation()
        guard debugPortReady() else { return }
        let amount = String(format: "%.2f", transparency)
        runHelper(["set-transparency", port, amount, clarityModeArgument]) { _ in }
    }

    @objc private func disableBackground() {
        guard !isApplying else { return }
        setBusy(true, text: "正在关闭")
        runHelper(["remove", port]) { [weak self] result in
            guard let self else { return }
            self.setBusy(false)
            switch result {
            case .success:
                self.automaticRestoreEnabled = false
                self.statusMenuItem.title = "状态：背景已关闭"
            case .failure(let error):
                self.statusMenuItem.title = "状态：关闭失败"
                self.showError(error.localizedDescription)
            }
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func applyBackground(mode: String, path: String?, automatic: Bool = false) {
        guard !isApplying else { return }
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            self.setBusy(true, text: "正在应用")
            let amount = String(format: "%.2f", self.transparency)
            let clarityMode = self.clarityModeArgument
            let arguments: [String]
            switch mode {
            case "image":
                arguments = ["apply-image", self.port, path ?? "", amount, clarityMode]
            case "video":
                arguments = ["apply-video", self.port, path ?? "", amount, clarityMode]
            default:
                arguments = ["apply-effect", self.port, mode, amount, clarityMode]
            }

            self.runHelper(arguments) { [weak self] result in
                guard let self else { return }
                self.setBusy(false)
                switch result {
                case .success:
                    self.automaticRestoreEnabled = true
                    self.defaults.set(mode, forKey: "backgroundMode")
                    if let path { self.defaults.set(path, forKey: "backgroundPath") }
                    else { self.defaults.removeObject(forKey: "backgroundPath") }
                    self.updateModeChecks()
                    self.statusMenuItem.title = "状态：已启用 · \(self.title(for: mode))"
                case .failure(let error):
                    self.statusMenuItem.title = "状态：应用失败"
                    if !automatic { self.showError(error.localizedDescription) }
                }
            }
        }
        if automatic { apply() }
        else { withCodexReady(apply) }
    }

    private func title(for mode: String) -> String {
        switch mode {
        case "gradient": return "流动渐变"
        case "aurora": return "极光"
        case "bokeh": return "柔光光斑"
        case "meteors": return "流星雨"
        case "particles": return "动态粒子"
        case "image": return "照片"
        case "video": return "视频"
        default: return "宇宙星河"
        }
    }

    private func preparedImagePath(for url: URL) throws -> String {
        let extensionName = url.pathExtension.lowercased()
        guard extensionName == "heic" || extensionName == "heif" else { return url.path }

        guard
            let image = NSImage(contentsOf: url),
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        else {
            throw BackgroundAppError(message: "无法读取这张 HEIC/HEIF 照片")
        }

        let supportRoot = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let supportDirectory = supportRoot.appendingPathComponent("Codex Dynamic Background", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let outputURL = supportDirectory.appendingPathComponent("converted-background.jpg")
        try jpegData.write(to: outputURL, options: .atomic)
        return outputURL.path
    }

    private func withCodexReady(_ completion: @escaping () -> Void) {
        setBusy(true, text: "正在连接 Codex")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.debugPortReady() {
                DispatchQueue.main.async {
                    self.setBusy(false)
                    completion()
                }
                return
            }

            DispatchQueue.main.async {
                self.setBusy(false)
                let alert = NSAlert()
                alert.messageText = "需要重新启动一次 Codex"
                alert.informativeText = "Codex 更新或普通启动后，背景连接需要重新开启。重启后会恢复当前背景和透明度设置。"
                alert.addButton(withTitle: "重新启动并继续")
                alert.addButton(withTitle: "取消")
                NSApp.activate(ignoringOtherApps: true)
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                self.restartCodex(completion: completion)
            }
        }
    }

    private func restartCodex(completion: @escaping () -> Void) {
        setBusy(true, text: "正在重新启动 Codex")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            for application in NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex") {
                application.terminate()
            }

            let quitDeadline = Date().addingTimeInterval(15)
            while Date() < quitDeadline {
                if NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty { break }
                Thread.sleep(forTimeInterval: 0.25)
            }

            if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty {
                DispatchQueue.main.async {
                    self.setBusy(false, text: "Codex 未能退出")
                    self.showError("Codex 没有正常退出，请手动退出后再试。")
                }
                return
            }

            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = self.launchArguments
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.setBusy(false, text: "启动失败")
                    self.showError("无法重新启动 Codex：\(error.localizedDescription)")
                }
                return
            }

            let readyDeadline = Date().addingTimeInterval(35)
            while Date() < readyDeadline {
                if self.debugPortReady() {
                    DispatchQueue.main.async {
                        self.setBusy(false)
                        completion()
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.3)
            }

            DispatchQueue.main.async {
                self.setBusy(false, text: "连接超时")
                self.showError("Codex 已启动，但背景通道没有准备好。请稍后从菜单重新选择背景。")
            }
        }
    }

    private func refreshStatus(restoreBackground: Bool = false) {
        guard !isApplying, !isCheckingConnection else { return }
        isCheckingConnection = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard self.debugPortReady() else {
                DispatchQueue.main.async {
                    self.isCheckingConnection = false
                    self.automaticRestoreAttempted = false
                    guard !self.isApplying else { return }
                    self.statusMenuItem.title = "状态：连接未开启 · 点击修复连接"
                }
                return
            }

            let result = self.runHelperSync(["status", self.port])
            DispatchQueue.main.async {
                self.isCheckingConnection = false
                guard !self.isApplying else { return }
                if result.exitCode == 0, result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "active" {
                    self.automaticRestoreAttempted = false
                    let mode = self.defaults.string(forKey: "backgroundMode") ?? "背景"
                    self.statusMenuItem.title = "状态：已启用 · \(self.title(for: mode))"
                } else {
                    self.statusMenuItem.title = "状态：背景未启用"
                    if restoreBackground, self.automaticRestoreEnabled, !self.automaticRestoreAttempted {
                        self.automaticRestoreAttempted = true
                        let mode = self.defaults.string(forKey: "backgroundMode") ?? "gradient"
                        let path = self.defaults.string(forKey: "backgroundPath")
                        if ["image", "video"].contains(mode),
                           (path == nil || !FileManager.default.fileExists(atPath: path!)) {
                            self.statusMenuItem.title = "状态：背景文件已移动 · 请重新选择"
                            return
                        }
                        self.applyBackground(mode: mode, path: path, automatic: true)
                    }
                }
            }
        }
    }

    private func debugPortReady() -> Bool {
        let result = runSystemProcess(
            executable: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: ["-fsS", "--max-time", "1", "http://127.0.0.1:\(port)/json/list"]
        )
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let targets = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return false }
        return targets.contains { target in
            guard target["type"] as? String == "page",
                  let text = target["url"] as? String,
                  let url = URL(string: text)
            else { return false }
            let route = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "initialRoute" })?.value
            let mainRoute = route == nil || route == "/"
                || route?.range(of: "^/(threads?|new|home|codex)(/|$)", options: .regularExpression) != nil
            return mainRoute && url.scheme == "app" && url.host == "-" && url.path == "/index.html"
        }
    }

    private func runHelper(_ arguments: [String], completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.runHelperSync(arguments)
            DispatchQueue.main.async {
                if result.exitCode == 0 {
                    completion(.success(result.output.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(.failure(BackgroundAppError(message: message.isEmpty ? "操作失败" : message)))
                }
            }
        }
    }

    private func runHelperSync(_ arguments: [String]) -> (exitCode: Int32, output: String) {
        runSystemProcess(executable: nodeURL, arguments: [helperURL.path] + arguments)
    }

    private func runSystemProcess(executable: URL, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Codex 动态背景"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.accessory)
application.run()
