import AppKit

enum Constants {
    static let radius: CGFloat = 100
}

class AppController {
    // MARK: - Init

    init() {
        ballViewController.delegate = self
    }

    private func makeClickWindow(forBallID ballID: String) -> NSWindow {
        let catcher = MouseCatcherView()
        catcher.frame = CGRect(x: 0, y: 0, width: Constants.radius * 2, height: Constants.radius * 2)
        catcher.wantsLayer = true
        // This is needed so that the window accepts mouse events
        catcher.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        catcher.layer?.cornerRadius = Constants.radius

        catcher.onMouseDown = { [weak self] in self?.ballViewController.onMouseDown(ballID: ballID) }
        catcher.onMouseDrag = { [weak self] in self?.ballViewController.onMouseDrag(ballID: ballID) }
        catcher.onMouseUp = { [weak self] in self?.ballViewController.onMouseUp(ballID: ballID) }
        catcher.onScroll = { [weak self] in self?.ballViewController.onScroll(event: $0, ballID: ballID) }

        let clickWindow = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: Constants.radius * 2, height: Constants.radius * 2),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        clickWindow.contentView = catcher
        clickWindow.isReleasedWhenClosed = false
        clickWindow.level = .screenSaver
        clickWindow.backgroundColor = NSColor.clear
        return clickWindow
    }

    // MARK: - External actions
    func dockIconClicked() {
        guard let screen = NSScreen.main else { return }

        if ballVisible, NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            self.ballViewController.animatePutBack(rect: screen.inferredRectOfHoveredDockIcon) {
                self.ballVisible = false
            }
            return
        }

        _ = ballViewController.view

        self.ballViewController.animateBallFromRect(screen.inferredRectOfHoveredDockIcon)
        self.ballVisible = true
    }

    // MARK: - State
    private var ballVisible = false {
        didSet(old) {
            guard ballVisible != old else { return }

            ballWindowController.window!.setIsVisible(ballVisible)

            ballViewController.sceneView.isPaused = !ballVisible

            if ballVisible {
                updateClickWindowPositions()
            } else {
                for clickWindow in clickWindows.values {
                    clickWindow.setIsVisible(false)
                }
                clickWindows.removeAll()
            }
        }
    }

    // MARK - Windows
    fileprivate let ballWindowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "Main") as! BallWindowController
    fileprivate var ballViewController: BallViewController {
        ballWindowController.window!.contentViewController as! BallViewController
    }

    private var clickWindows = [String: NSWindow]()
}

extension AppController: BallViewControllerDelegate {
    func ballViewController(_ vc: BallViewController, ballsDidMoveToPositions positions: [String: CGRect]) {
        updateClickWindowPositions()
    }

    fileprivate func updateClickWindowPositions() {
        guard ballVisible else { return }
        guard let window = self.ballWindowController.window, let screen = window.screen else { return }
        let rects = ballViewController.targetMouseCatcherRects
        let activeIDs = Set(rects.keys)

        for ballID in Array(clickWindows.keys) where !activeIDs.contains(ballID) {
            clickWindows[ballID]?.setIsVisible(false)
            clickWindows.removeValue(forKey: ballID)
        }

        for (ballID, var rect) in rects {
            let rounding: CGFloat = 10
            rect.origin.x = round(rect.minX / rounding) * rounding
            rect.origin.y = round(rect.minY / rounding) * rounding
            // HACK: Assume scene coords are same as window coords
            rect = rect.byConstraining(withinBounds: screen.frame)

            let clickWindow = clickWindows[ballID] ?? makeClickWindow(forBallID: ballID)
            clickWindows[ballID] = clickWindow
            clickWindow.setFrame(rect, display: false)
            clickWindow.setIsVisible(true)
        }
    }
}
