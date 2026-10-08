import AppKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func trackMenuEvents(for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        RunLoop.main.run(mode: .eventTracking, before: deadline)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let menu = makeInteractiveMenu(title: "透明度回归测试")
let slider = NSSlider(value: 0.1, minValue: 0.1, maxValue: 1, target: nil, action: nil)
let sliderItem = NSMenuItem()
sliderItem.view = slider
menu.addItem(sliderItem)
let disabledItem = NSMenuItem(title: "状态", action: nil, keyEquivalent: "")
disabledItem.isEnabled = false
menu.addItem(disabledItem)
menu.update()
require(sliderItem.isEnabled && slider.isEnabled, "自定义滑杆条目应保持可交互")
require(!disabledItem.isEnabled, "只读状态条目应保持禁用")

// Reproduce a menu opened from inside a main-queue callback. Its nested event
// loop must allow helper completion and continuous slider updates to finish.
DispatchQueue.main.async {
    var completedWhileTracking = false
    DispatchQueue.global().async {
        performOnMainRunLoop { completedWhileTracking = true }
    }
    trackMenuEvents(for: 0.2)
    require(completedWhileTracking, "完成回调不能等到菜单关闭才执行")

    var applied: [TransparencyUpdateCoordinator.Selection] = []
    var completions: [() -> Void] = []
    let updates = TransparencyUpdateCoordinator { selection, completion in
        applied.append(selection)
        completions.append(completion)
    }
    updates.request(amount: 0.2, keepBackgroundClear: false)
    updates.request(amount: 0.3, keepBackgroundClear: true)
    trackMenuEvents(for: 0.2)
    require(applied.count == 1 && applied[0].amount == 0.3, "菜单打开时应合并连续拖动并应用")
    require(applied[0].keepBackgroundClear, "应使用最新的清晰模式")

    updates.request(amount: 0.4, keepBackgroundClear: false)
    updates.request(amount: 0.95, keepBackgroundClear: true)
    trackMenuEvents(for: 0.2)
    require(applied.count == 1, "上一笔应用完成前不能并发覆盖透明度")
    completions[0]()
    trackMenuEvents(for: 0.1)
    require(applied.count == 2 && applied[1].amount == 0.95, "慢应用完成后应采用最后一次拖动的数值")
    completions[1]()
    trackMenuEvents(for: 0.1)

    updates.isApplyingBackground = true
    updates.request(amount: 0.8, keepBackgroundClear: false)
    updates.request(amount: 0.1, keepBackgroundClear: true)
    trackMenuEvents(for: 0.2)
    require(applied.count == 2, "切换背景期间应保留数值并延后发送")
    updates.isApplyingBackground = false
    require(applied.count == 3 && applied[2].amount == 0.1, "后台恢复结束后应应用新选择的 10%")
    require(applied[2].keepBackgroundClear, "后台恢复后应保留清晰模式")

    // Completion represents either success or failure: neither may strand
    // the next slider change in a permanently busy state.
    completions[2]()
    trackMenuEvents(for: 0.1)
    updates.request(amount: 1, keepBackgroundClear: false)
    trackMenuEvents(for: 0.2)
    require(applied.count == 4 && applied[3].amount == 1, "失败后仍应能继续调整到 100%")
    completions[3]()
    trackMenuEvents(for: 0.1)
    print("PASS: 菜单可交互、跟踪期间完成回调、连续更新、最后数值优先、后台恢复和失败后继续调整")
    fflush(stdout)
    exit(0)
}
app.run()
