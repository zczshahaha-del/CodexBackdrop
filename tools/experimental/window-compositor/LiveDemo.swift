import AppKit
import CoreImage

final class PassThroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@main
final class LiveDemo: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    var window: NSWindow!
    var panel: PassThroughPanel!
    var imageView: NSImageView!
    var base: NSView!
    var counter: NSTextField!
    var timer: Timer?
    var clicks = 0
    var frames = 0
    var started = Date()
    let compositor = try! BackgroundCompositor()
    var protection: [CGRect] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = LiveDemo()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func label(_ string: String, rect: CGRect, size: CGFloat) {
        let item = NSTextField(labelWithString: string)
        item.frame = rect
        item.font = .systemFont(ofSize: size)
        item.textColor = .white
        base.addSubview(item)
        protection.append(rect.insetBy(dx: -2, dy: -2))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: CGRect(x: 180, y: 150, width: 840, height: 540), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "背景接入试验（模拟窗口）"
        window.minSize = CGSize(width: 700, height: 530)
        window.delegate = self
        base = NSView(frame: CGRect(x: 0, y: 0, width: 840, height: 540))
        base.wantsLayer = true
        base.layer?.backgroundColor = NSColor(deviceWhite: 24.0/255, alpha: 1).cgColor
        window.contentView = base
        label("新接入原型 · 不是 Codex 聊天画面", rect: CGRect(x: 28, y: 460, width: 750, height: 35), size: 24)
        label("请点下方按钮：原窗口收到点击后，计数应增加。", rect: CGRect(x: 28, y: 411, width: 750, height: 32), size: 20)
        label("图片、控件和文字区域在此模拟中已知。真实识别尚未验证。", rect: CGRect(x: 28, y: 363, width: 770, height: 30), size: 17)
        let media = NSView(frame: CGRect(x: 30, y: 180, width: 330, height: 145))
        media.wantsLayer = true
        media.layer?.backgroundColor = NSColor(deviceWhite: 17.0/255, alpha: 1).cgColor
        base.addSubview(media)
        protection.append(media.frame)
        label("模拟图片里的黑色保持原样", rect: CGRect(x: 44, y: 230, width: 310, height: 35), size: 18)
        let button = NSButton(title: "点击原窗口按钮", target: self, action: #selector(clicked))
        button.frame = CGRect(x: 400, y: 230, width: 210, height: 42)
        button.bezelStyle = .rounded
        base.addSubview(button)
        protection.append(button.frame.insetBy(dx: -8, dy: -8))
        counter = NSTextField(labelWithString: "原窗口收到点击：0 次")
        counter.frame = CGRect(x: 400, y: 175, width: 370, height: 32)
        counter.font = .systemFont(ofSize: 21)
        counter.textColor = .white
        base.addSubview(counter)
        protection.append(counter.frame.insetBy(dx: -2, dy: -2))
        label("关闭此模拟窗口就结束试验；不会读取其他应用。", rect: CGRect(x: 28, y: 80, width: 750, height: 30), size: 18)
        panel = PassThroughPanel(contentRect: window.convertToScreen(base.bounds), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        imageView = NSImageView(frame: panel.contentView!.bounds)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleAxesIndependently
        panel.contentView = imageView
        window.addChildWindow(panel, ordered: .above)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.render() }
        render()
        print("DEMO_READY synthetic-only; no ScreenCaptureKit, Accessibility, Codex or filesystem capture")
        fflush(stdout)
    }

    @objc func clicked() {
        clicks += 1
        counter.stringValue = "原窗口收到点击：\(clicks) 次"
        print("MOUSE_CLICK_RECEIVED count=\(clicks) frame=\(frames)")
        fflush(stdout)
        render()
    }

    func render() {
        guard let rep = base.bitmapImageRepForCachingDisplay(in: base.bounds) else { return }
        base.cacheDisplay(in: base.bounds, to: rep)
        guard let cg = rep.cgImage else { return }
        let frame = CIImage(cgImage: cg)
        let scale = frame.extent.width / base.bounds.width
        let areas = protection.map { CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale) }
        let elapsed = Date().timeIntervalSince(started)
        let background = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: CGFloat(sin(elapsed/3)*200), y: 0),
            "inputPoint1": CIVector(x: frame.extent.width, y: frame.extent.height),
            "inputColor0": CIColor(red: 0.05, green: 0.22 + 0.04*sin(elapsed/4), blue: 0.30),
            "inputColor1": CIColor(red: 0.20, green: 0.06, blue: 0.29),
        ])!.outputImage!
        let palette = [17.0,24.0,33.0].map { CIColor(red: $0/255, green: $0/255, blue: $0/255) }
        guard let result = try? compositor.compose(frame: frame, background: background, palette: palette, protectedAreas: areas), let image = context.createCGImage(result, from: frame.extent) else { panel.orderOut(nil); return }
        panel.setFrame(window.convertToScreen(base.bounds), display: true)
        imageView.image = NSImage(cgImage: image, size: base.bounds.size)
        frames += 1
        if frames == 1 || frames % 100 == 0 {
            print("FRAME_OK count=\(frames) size=\(Int(base.bounds.width))x\(Int(base.bounds.height))")
            fflush(stdout)
        }
    }

    func windowDidResize(_ notification: Notification) { render() }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); panel.orderOut(nil); NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
