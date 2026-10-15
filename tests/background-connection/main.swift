import Foundation

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    do {
        guard try condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    } catch {
        fputs("FAIL: \(message): \(error)\n", stderr)
        exit(1)
    }
}

var launches = 0
let connected = CodexConnection(isReady: { true }, isRunning: { true }, launchIfNotRunning: { launches += 1; return true })
require(try connected.ensureReady() == .ready, "已有连接应直接应用")
require(launches == 0, "已有连接不能启动或重启 Codex")
require(try connected.ensureReady(allowRestart: true) == .ready, "确认期间已恢复连接时也不能再重启")

let disconnected = CodexConnection(isReady: { false }, isRunning: { true }, launchIfNotRunning: { launches += 1; return true })
require(try disconnected.ensureReady() == .waiting, "运行中未连接应等待")
require(launches == 0, "运行中未连接不能启动重复实例")

var ticks: TimeInterval = 0
var ready = false
let stopped = CodexConnection(isReady: { ready }, isRunning: { false }, launchIfNotRunning: {
    launches += 1
    return true
}, timeout: 2, now: { ticks }, pause: { ticks += 1; ready = true })
require(try stopped.ensureReady() == .ready, "未运行时应正常打开并等待连接")
require(launches == 1, "正常打开只发送一次启动请求")

let raced = CodexConnection(isReady: { false }, isRunning: { false }, launchIfNotRunning: { false })
require(try raced.ensureReady() == .waiting, "启动前已被其他入口打开时应等待，不能重启")

ticks = 0
let timedOut = CodexConnection(isReady: { false }, isRunning: { false }, launchIfNotRunning: { true }, timeout: 2, now: { ticks }, pause: { ticks += 1 })
do {
    _ = try timedOut.ensureReady()
    require(false, "连接超时应返回错误")
} catch CodexConnectionError.timedOut {} catch { require(false, "超时错误类型不正确") }
require(ticks == 2, "连接等待应按时截止")

let launchFailed = CodexConnection(isReady: { false }, isRunning: { false }, launchIfNotRunning: { throw CodexConnectionError.launchFailed })
do {
    _ = try launchFailed.ensureReady()
    require(false, "启动失败必须返回错误")
} catch CodexConnectionError.launchFailed {} catch { require(false, "启动失败错误类型不正确") }
require(try stopped.ensureReady() == .ready, "错误后应允许再次检查连接")

var quitRequests = 0
var repairLaunches = 0
var running = true
var repairReady = false
ticks = 0
let approved = CodexConnection(isReady: { repairReady }, isRunning: { running }, launchIfNotRunning: {
    require(!running, "必须等待原实例退出后才能打开")
    repairLaunches += 1
    repairReady = true
    return true
}, requestQuit: { quitRequests += 1 }, timeout: 2, quitTimeout: 3,
   now: { ticks }, pause: { ticks += 1; running = false })
require(try approved.ensureReady() == .waiting, "未确认只能请求确认，不能退出")
require(quitRequests == 0 && repairLaunches == 0, "取消确认不得产生退出或启动副作用")
require(try approved.ensureReady(allowRestart: true) == .ready, "确认后应退出、正常打开并等待连接")
require(quitRequests == 1 && repairLaunches == 1, "一次确认只允许一次退出和启动")
require(ticks == 1, "启动必须等正常退出完成")

repairReady = false
running = true
ticks = 0
quitRequests = 0
repairLaunches = 0
let quitTimeout = CodexConnection(isReady: { false }, isRunning: { true }, launchIfNotRunning: {
    repairLaunches += 1; return true
}, requestQuit: { quitRequests += 1 }, timeout: 2, quitTimeout: 2,
   now: { ticks }, pause: { ticks += 1 })
do {
    _ = try quitTimeout.ensureReady(allowRestart: true)
    require(false, "原应用未退出时必须超时返回")
} catch CodexConnectionError.quitTimedOut {} catch { require(false, "退出超时错误不正确") }
require(quitRequests == 1 && repairLaunches == 0, "退出超时不得强退、重试退出或启动第二实例")

let refused = CodexConnection(isReady: { false }, isRunning: { true }, launchIfNotRunning: {
    repairLaunches += 1; return true
}, requestQuit: { throw CodexConnectionError.quitFailed })
do {
    _ = try refused.ensureReady(allowRestart: true)
    require(false, "拒绝退出必须返回错误")
} catch CodexConnectionError.quitFailed {} catch { require(false, "退出失败错误不正确") }
require(repairLaunches == 0, "拒绝退出后不能打开第二实例")

running = true
quitRequests = 0
let repairRace = CodexConnection(isReady: { false }, isRunning: { running }, launchIfNotRunning: {
    running = true
    return false
}, requestQuit: { quitRequests += 1; running = false })
require(try repairRace.ensureReady(allowRestart: true) == .waiting, "修复期间被其他入口打开时应返回，不能再次退出")
require(quitRequests == 1, "出现新实例不能复用之前的重启确认")

let suite = "CodexBackdrop.ConnectionTests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = BackgroundSelectionStore(defaults: defaults)
let original = BackgroundSelectionStore.Selection(mode: "image", path: "/test/photo.png")
let latest = BackgroundSelectionStore.Selection(mode: "aurora", path: nil)
store.request(original)
require(store.needsApply && store.restorationEnabled, "未连接的选择应保存并允许后续应用")
store.request(latest)
require(store.selection == latest && defaults.string(forKey: "backgroundPath") == nil, "切换内置背景应替换照片选择并清除旧路径")
store.markApplied(original)
require(store.needsApply, "旧完成回调不能清除最新待应用选择")
let relaunchedStore = BackgroundSelectionStore(defaults: defaults)
require(relaunchedStore.selection == latest && relaunchedStore.needsApply, "助手重新打开仍应保留最新待应用选择")
require(try disconnected.ensureReady() == .waiting && relaunchedStore.needsApply, "等待连接不能丢失选择")
require(try connected.ensureReady() == .ready, "连接恢复应允许继续应用")
relaunchedStore.markApplied(latest)
require(!store.needsApply && store.restorationEnabled, "成功应用后应清除等待并保留自动恢复")
store.request(original)
store.disable()
require(!store.needsApply && !store.restorationEnabled, "关闭背景应取消待应用和自动恢复")
store.markApplied(original)
require(!store.restorationEnabled, "取消后迟到的回调不能重新启用背景")
store.request(latest)
require(store.needsApply && store.restorationEnabled, "关闭后重新选择应能再次应用")

defaults.removePersistentDomain(forName: suite)
defaults.set("meteors", forKey: "backgroundMode")
require(store.restorationEnabled && !store.needsApply, "旧版本保存的选择应保留自动恢复兼容")
print("PASS: 已连接直接应用、确认前零退出、确认后正常修复、退出拒绝与超时、启动竞争、最新选择与取消")
