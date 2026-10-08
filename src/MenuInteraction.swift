import AppKit
import CoreFoundation

// A menu can keep a main-queue callback on the stack for its entire tracking loop.
// Run-loop blocks can still complete UI work while that menu is open.
func performOnMainRunLoop(_ action: @escaping () -> Void) {
    RunLoop.main.perform(inModes: [.common], block: action)
    CFRunLoopWakeUp(CFRunLoopGetMain())
}

func makeInteractiveMenu(title: String) -> NSMenu {
    let menu = NSMenu(title: title)
    // Custom-view items have no menu action, so automatic validation disables them.
    // AppDelegate manages enabled states for its actions explicitly.
    menu.autoenablesItems = false
    return menu
}

final class TransparencyUpdateCoordinator {
    struct Selection: Equatable {
        let amount: Double
        let keepBackgroundClear: Bool
    }

    private let apply: (Selection, @escaping () -> Void) -> Void
    private var pending: Selection?
    private var timer: Timer?
    private var isUpdating = false

    var isApplyingBackground = false {
        didSet {
            if !isApplyingBackground { flush() }
        }
    }

    init(apply: @escaping (Selection, @escaping () -> Void) -> Void) {
        self.apply = apply
    }

    func request(amount: Double, keepBackgroundClear: Bool) {
        pending = Selection(amount: amount, keepBackgroundClear: keepBackgroundClear)
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.12, repeats: false) { [weak self] _ in
            self?.flush()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func flush() {
        guard !isApplyingBackground, !isUpdating, let selection = pending else { return }
        timer?.invalidate()
        timer = nil
        pending = nil
        isUpdating = true
        apply(selection) { [weak self] in
            performOnMainRunLoop {
                guard let self else { return }
                self.isUpdating = false
                self.flush()
            }
        }
    }
}
