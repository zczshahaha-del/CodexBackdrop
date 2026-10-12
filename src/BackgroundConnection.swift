import Foundation

enum CodexConnectionError: LocalizedError {
    case launchFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .launchFailed: return "无法打开 Codex，请检查应用是否仍在应用程序目录。"
        case .timedOut: return "Codex 已打开，但背景连接尚未准备好。选择已保存，连接恢复后会自动应用。"
        }
    }
}

struct CodexConnection {
    enum Readiness: Equatable { case ready, waiting }

    let isReady: () -> Bool
    let isRunning: () -> Bool
    // Return false if Codex started independently before the launch request.
    let launchIfNotRunning: () throws -> Bool
    var timeout: TimeInterval = 35
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var pause: () -> Void = { Thread.sleep(forTimeInterval: 0.3) }

    func ensureReady() throws -> Readiness {
        if isReady() { return .ready }
        if isRunning() { return .waiting }
        guard try launchIfNotRunning() else { return .waiting }
        let deadline = now() + timeout
        while now() < deadline {
            if isReady() { return .ready }
            pause()
        }
        throw CodexConnectionError.timedOut
    }
}

final class BackgroundSelectionStore {
    struct Selection: Equatable {
        let mode: String
        let path: String?
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var selection: Selection? {
        guard let mode = defaults.string(forKey: "backgroundMode") else { return nil }
        return Selection(mode: mode, path: defaults.string(forKey: "backgroundPath"))
    }

    var needsApply: Bool { defaults.bool(forKey: "backgroundNeedsApply") }

    var restorationEnabled: Bool {
        (defaults.object(forKey: "automaticRestoreEnabled") as? Bool) ?? (selection != nil)
    }

    func request(_ selection: Selection) {
        defaults.set(selection.mode, forKey: "backgroundMode")
        if let path = selection.path { defaults.set(path, forKey: "backgroundPath") }
        else { defaults.removeObject(forKey: "backgroundPath") }
        defaults.set(true, forKey: "automaticRestoreEnabled")
        defaults.set(true, forKey: "backgroundNeedsApply")
    }

    func markApplied(_ selection: Selection) {
        // A stale completion must not consume a newer choice or undo cancellation.
        guard restorationEnabled, self.selection == selection else { return }
        defaults.set(false, forKey: "backgroundNeedsApply")
    }

    func disable() {
        defaults.set(false, forKey: "automaticRestoreEnabled")
        defaults.set(false, forKey: "backgroundNeedsApply")
    }
}
