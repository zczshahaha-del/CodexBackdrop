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
    private let defaults: UserDefaults
    private let testSuiteName: String?
    private lazy var backgroundSelection = BackgroundSelectionStore(defaults: defaults)

    init(defaults: UserDefaults = .standard, testSuiteName: String? = nil) {
        self.defaults = defaults
        self.testSuiteName = testSuiteName
        super.init()
    }

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var modeItems: [String: NSMenuItem] = [:]
    private var transparencySlider: NSSlider!
    private var transparencyLabel: NSTextField!
    private var clarityMenuItem: NSMenuItem!
    private lazy var transparencyUpdates = TransparencyUpdateCoordinator { [weak self] selection, completion in
        guard let self else { completion(); return }
        let amount = String(format: "%.2f", selection.amount)
        let clarity = selection.keepBackgroundClear ? "clear" : "linked"
        self.runHelper(["set-transparency", self.port, amount, clarity]) { _ in completion() }
    }
    private var isApplying = false
    private var isCheckingConnection = false
    private var recoveryTimer: Timer?
    private var automaticRestoreAttempted = false
    private var hasRequestedRepairConfirmation = false

    private var automaticRestoreEnabled: Bool { backgroundSelection.restorationEnabled }

    private var codexIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").isEmpty
    }

    private var launchArguments: [String] {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let profile = support.appendingPathComponent("Codex", isDirectory: true)
        return ["-a", chatGPTURL.path, "--args", "--user-data-dir=\(profile.path)",
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
        if let testSuiteName {
            checkCancelledConnectionRepair(suiteName: testSuiteName)
            return
        }
        if CommandLine.arguments.contains("--self-test") {
            menu.update()
            precondition(menu.items.first(where: { $0.view != nil })?.isEnabled == true)
            setBusy(true)
            precondition(transparencySlider.isEnabled, "后台应用不能禁用滑杆")
            precondition(modeItems.values.allSatisfy { !$0.isEnabled })
            setBusy(false)
            let titles = menu.items.map { $0.title }.filter { !$0.isEmpty }
            precondition(!titles.contains("打开 Codex（启用背景连接）"))
            print("menu=\(titles.joined(separator: "|"))")
            print("slider=\(transparencySlider.minValue)-\(transparencySlider.maxValue),value=\(transparencySlider.doubleValue)")
            print("keepBackgroundClear=\(keepBackgroundClear)")
            print("automaticRestoreEnabled=\(automaticRestoreEnabled)")
            print("sliderInteractiveDuringBackgroundApply=true")
            precondition(!launchArguments.contains("-na") && !launchArguments.contains("-n"))
            print("opensNewInstance=false")
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
        let openMenuTimer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.statusItem.button?.performClick(nil)
        }
        RunLoop.main.add(openMenuTimer, forMode: .common)
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

        menu = makeInteractiveMenu(title: "Codex 动态背景")
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

        let reapplyItem = NSMenuItem(title: "重新应用背景", action: #selector(reapplyCurrentBackground), keyEquivalent: "r")
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
        // Changes are saved immediately and sent after any background application.
        // Automatic recovery must not interrupt an active slider drag.
        transparencyUpdates.isApplyingBackground = busy
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
        transparencyUpdates.request(amount: transparency, keepBackgroundClear: keepBackgroundClear)
    }

    @objc private func toggleBackgroundClarity() {
        keepBackgroundClear.toggle()
        clarityMenuItem.state = keepBackgroundClear ? .on : .off
        updateTransparencyPresentation()
        transparencyUpdates.request(amount: transparency, keepBackgroundClear: keepBackgroundClear)
    }

    @objc private func disableBackground() {
        guard !isApplying else { return }
        backgroundSelection.disable()
        automaticRestoreAttempted = false
        setBusy(true, text: "正在关闭")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.debugPortReady() ? self.runHelperSync(["remove", self.port]) : (exitCode: Int32(0), output: "")
            performOnMainRunLoop {
                self.setBusy(false)
                if result.exitCode == 0 {
                    self.statusMenuItem.title = "状态：背景已关闭"
                } else {
                    self.statusMenuItem.title = "状态：关闭失败 · 自动恢复已停用"
                    self.showError(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func applyBackground(mode: String, path: String?, automatic: Bool = false) {
        guard !isApplying else { return }
        let selection = BackgroundSelectionStore.Selection(mode: mode, path: path)
        if !automatic {
            backgroundSelection.request(selection)
            automaticRestoreAttempted = false
            updateModeChecks()
        }
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
                    self.backgroundSelection.markApplied(selection)
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
            let connection = self.makeConnection()
            do {
                let readiness = try connection.ensureReady()
                performOnMainRunLoop {
                    self.setBusy(false)
                    if readiness == .ready { completion() }
                    else {
                        self.confirmConnectionRepair(completion)
                    }
                }
            } catch {
                performOnMainRunLoop {
                    self.setBusy(false, text: "已保存 · 连接尚未就绪")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func tryOpeningCodex() throws -> Bool {
        guard !codexIsRunning else { return false }
        let result = runSystemProcess(executable: URL(fileURLWithPath: "/usr/bin/open"), arguments: launchArguments)
        guard result.exitCode == 0 else { throw CodexConnectionError.launchFailed }
        return true
    }

    private func makeConnection(expectedPIDs: [pid_t]? = nil) -> CodexConnection {
        CodexConnection(
            isReady: { self.debugPortReady() },
            isRunning: { self.codexIsRunning },
            launchIfNotRunning: { try self.tryOpeningCodex() },
            requestQuit: {
                let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
                guard let expectedPIDs,
                      applications.map(\.processIdentifier).sorted() == expectedPIDs,
                      applications.count == 1 else { throw CodexConnectionError.applicationChanged }
                guard applications[0].terminate() else { throw CodexConnectionError.quitFailed }
            }
        )
    }

    private func confirmConnectionRepair(_ completion: @escaping () -> Void) {
        let expectedPIDs = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
            .map(\.processIdentifier).sorted()
        setBusy(true, text: "等待重启确认")
        hasRequestedRepairConfirmation = true
        let approved: Bool
        if testSuiteName != nil {
            approved = false
        } else {
            let alert = NSAlert()
            alert.messageText = "需要重新启动 Codex"
            alert.informativeText = "为开启背景连接，需要退出并重新打开 Codex。这会中断正在进行的聊天；背景和透明度设置会保留。是否继续？"
            alert.addButton(withTitle: "重新启动并应用")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            approved = alert.runModal() == .alertFirstButtonReturn
        }
        guard approved else {
            setBusy(false, text: "已保存 · 已取消重启")
            return
        }
        setBusy(true, text: "正在修复背景连接")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let readiness = try self.makeConnection(expectedPIDs: expectedPIDs).ensureReady(allowRestart: true)
                performOnMainRunLoop {
                    self.setBusy(false)
                    if readiness == .ready { completion() }
                    else {
                        self.statusMenuItem.title = "状态：连接未开启 · 请重新应用"
                        self.showError("Codex 已从其他入口打开，背景连接仍未开启。请重新应用背景，按提示重新建立连接。")
                    }
                }
            } catch {
                performOnMainRunLoop {
                    self.setBusy(false, text: "已保存 · 连接修复未完成")
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func checkCancelledConnectionRepair(suiteName: String) {
        let pids = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").map(\.processIdentifier).sorted()
        guard !pids.isEmpty, !debugPortReady() else {
            defaults.removePersistentDomain(forName: suiteName)
            fputs("此检查要求 Codex 正在运行且 9224 背景连接未开启。\n", stderr)
            exit(1)
        }
        applyBackground(mode: "gradient", path: nil)
        let deadline = Date().addingTimeInterval(8)
        var checkedWaiting = false
        let timer = Timer(timeInterval: 0.1, repeats: true) { [self] timer in
            if Date() > deadline {
                defaults.removePersistentDomain(forName: suiteName)
                fputs("FAIL: 未连接路径没有及时结束\n", stderr)
                exit(1)
            }
            guard !isApplying else { return }
            let current = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").map(\.processIdentifier).sorted()
            precondition(current == pids, "不能退出、重启或重复打开 Codex")
            if !checkedWaiting {
                precondition(backgroundSelection.needsApply && automaticRestoreEnabled)
                precondition(hasRequestedRepairConfirmation, "应用背景必须先请求重启确认")
                precondition(statusMenuItem.title == "状态：已保存 · 已取消重启")
                checkedWaiting = true
                disableBackground()
            } else {
                precondition(!backgroundSelection.needsApply && !automaticRestoreEnabled)
                precondition(statusMenuItem.title == "状态：背景已关闭")
                timer.invalidate()
                defaults.removePersistentDomain(forName: suiteName)
                print("PASS: 应用先请求重启确认，取消后不退出或重复打开 Codex，关闭背景取消待应用选择")
                fflush(stdout)
                exit(0)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshStatus(restoreBackground: Bool = false) {
        guard !isApplying, !isCheckingConnection else { return }
        isCheckingConnection = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard self.debugPortReady() else {
                performOnMainRunLoop {
                    self.isCheckingConnection = false
                    self.automaticRestoreAttempted = false
                    guard !self.isApplying else { return }
                    self.statusMenuItem.title = self.backgroundSelection.needsApply
                        ? "状态：已保存 · 点击重新应用修复连接"
                        : (self.automaticRestoreEnabled ? "状态：连接未开启 · 点击重新应用" : "状态：背景已关闭")
                }
                return
            }

            let result = self.runHelperSync(["status", self.port])
            performOnMainRunLoop {
                self.isCheckingConnection = false
                guard !self.isApplying else { return }
                let active = result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "active"
                if active && !self.backgroundSelection.needsApply {
                    self.automaticRestoreAttempted = false
                    let mode = self.defaults.string(forKey: "backgroundMode") ?? "背景"
                    self.statusMenuItem.title = "状态：已启用 · \(self.title(for: mode))"
                } else {
                    self.statusMenuItem.title = self.backgroundSelection.needsApply ? "状态：已保存 · 等待应用" : "状态：背景未启用"
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
            performOnMainRunLoop {
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

@main
struct CodexBackdropApplication {
    static func main() {
        let application = NSApplication.shared
        let applicationDelegate: AppDelegate
        if CommandLine.arguments.contains("--cancel-repair-smoke-test") {
            let suite = "CodexBackdrop.CancelRepairSmoke.\(UUID().uuidString)"
            applicationDelegate = AppDelegate(defaults: UserDefaults(suiteName: suite)!, testSuiteName: suite)
        } else {
            applicationDelegate = AppDelegate()
        }
        application.delegate = applicationDelegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(applicationDelegate) {
            application.run()
        }
    }
}
