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

        catcher.onMouseDown = { [weak self] in self?.ballViewController.onMouseDown() }
        catcher.onMouseDrag = { [weak self] in self?.ballViewController.onMouseDrag() }
        catcher.onMouseUp = { [weak self] in self?.ballViewController.onMouseUp() }
        catcher.onScroll = { [weak self] in self?.ballViewController.onScroll(event: $0) }

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
        guard !isPuttingBallsBack else { return }

        let dockIconRect = screen.inferredRectOfHoveredDockIcon
        lastDockIconRect = dockIconRect

        _ = ballViewController.view

        self.ballViewController.animateBallFromRect(dockIconRect)
        self.ballVisible = true
    }

    var canPutAllBallsBack: Bool {
        ballVisible && !isPuttingBallsBack
    }

    func putAllBallsBack() {
        guard canPutAllBallsBack else { return }
        guard let dockIconRect = lastDockIconRect else { return }

        isPuttingBallsBack = true
        self.ballViewController.animatePutBack(rect: dockIconRect) {
            self.ballVisible = false
            self.isPuttingBallsBack = false
        }
    }

    // MARK: - State
    private var isPuttingBallsBack = false
    private var lastDockIconRect: CGRect?

    private var ballVisible = false {
        didSet(old) {
            guard ballVisible != old else { return }

            ballWindowController.window!.setIsVisible(ballVisible)

            if ballVisible {
                ballViewController.prepareToResumeSimulation()
                ballViewController.sceneView.isPaused = false
                updateClickWindowPositions()
            } else {
                ballViewController.sceneView.isPaused = true
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
