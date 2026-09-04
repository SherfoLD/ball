import Cocoa
import SpriteKit

protocol BallViewControllerDelegate: AnyObject {
    func ballViewController(_ vc: BallViewController, ballsDidMoveToPositions positions: [String: CGRect])
}

class BallViewController: NSViewController {
    weak var delegate: BallViewControllerDelegate?

    let scene = SKScene(size: .init(width: 200, height: 200))
    let sceneView = SKView()
    private let physicsEngine = BallPhysicsEngine()

    let collisionSounds: [NSSound] = ["pop_01", "pop_02", "pop_03"].map { id in
        NSSound(contentsOf: Bundle.main.url(forResource: id, withExtension: "caf")!, byReference: true)!
    }

    var targetMouseCatcherRects: [String: CGRect] {
        guard let win = self.view.window else { return [:] }
        var rects = [String: CGRect]()
        for ball in balls {
            let rect = tempOverrideMouseCatcherRects[ball.id] ?? ball.rect
            rects[ball.id] = win.convertToScreen(rect)
        }
        return rects
    }

    private var tempOverrideMouseCatcherRects = [String: CGRect]()

    private var balls = [Ball]()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(sceneView)
        sceneView.presentScene(scene)
        scene.backgroundColor = NSColor.clear
        sceneView.allowsTransparency = true

        sceneView.preferredFramesPerSecond = 120
        scene.delegate = self

        for sound in collisionSounds {
            sound.volume = 0
            sound.play() // Ensure ready to play
        }
    }


    override func viewDidLayout() {
        super.viewDidLayout()
        scene.size = view.bounds.size
        sceneView.frame = view.bounds
    }

    func prepareToResumeSimulation() {
        physicsEngine.resetClock()
    }

    // MARK: - Mouse handling

    private struct DragState {
        var ballID: String
        var ballStart: CGPoint
        var mouseStart: CGPoint
        var currentMousePos: CGPoint
        var velocityTracker = VelocityTracker()

        var currentBallPos: CGPoint {
            let delta = CGPoint(x: currentMousePos.x - mouseStart.x, y: currentMousePos.y - mouseStart.y)
            return CGPoint(x: ballStart.x + delta.x, y: ballStart.y + delta.y)
        }
    }

    private var dragState: DragState? {
        didSet(oldValue) {
            if oldValue?.ballID != dragState?.ballID, let oldBallID = oldValue?.ballID {
                let oldBall = ball(withID: oldBallID)
                oldBall?.beingDragged = false
            }

            if let dragState, let ball = ball(withID: dragState.ballID) {
                if oldValue?.ballID != dragState.ballID {
                    ball.simulationVelocity = .zero
                }
                ball.beingDragged = true
            }
        }
    }

    private var currentDragTarget: CGPoint? {
        guard let dragState, let ball = ball(withID: dragState.ballID) else { return nil }
        let pos = dragState.currentBallPos
        let rect = CGRect(
            x: pos.x - ball.radius,
            y: pos.y - ball.radius,
            width: ball.radius * 2,
            height: ball.radius * 2
        ).byConstraining(withinBounds: view.bounds)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func onMouseDown() {
        let scenePos = mouseScenePos
        let hitBall = ball(containing: scenePos)
        if let hitBall {
            var state = DragState(ballID: hitBall.id, ballStart: hitBall.position, mouseStart: scenePos, currentMousePos: scenePos)
            state.velocityTracker.add(pos: scenePos)
            self.dragState = state
        } else {
            self.dragState = nil
        }
    }

    func onMouseDrag() {
        if var dragState {
            dragState.currentMousePos = mouseScenePos
            dragState.velocityTracker.add(pos: dragState.currentMousePos)
            self.dragState = dragState
        }
    }

    func onMouseUp() {
        let ball: Ball?
        if let dragState {
            ball = self.ball(withID: dragState.ballID)
        } else {
            ball = nil
        }
        let velocity = dragState?.velocityTracker.velocity ?? .zero
        self.dragState = nil

        ball?.simulationVelocity = CGVector(dx: velocity.x, dy: velocity.y)
    }

    func onScroll(event: NSEvent) {
        switch event.phase {
        case .began:
            let scenePos = mouseScenePos
            let hitBall = ball(containing: scenePos)
            if let hitBall {
                var state = DragState(ballID: hitBall.id, ballStart: hitBall.position, mouseStart: .zero, currentMousePos: .zero)
                state.velocityTracker.add(pos: .zero)
                dragState = state
                tempOverrideMouseCatcherRects[hitBall.id] = hitBall.rect
            }
        case .changed:
            if var dragState {
                dragState.currentMousePos.x += event.scrollingDeltaX
                dragState.currentMousePos.y -= event.scrollingDeltaY
                dragState.velocityTracker.add(pos: dragState.currentMousePos)
                self.dragState = dragState
            }
        case .ended, .cancelled:
            let ball: Ball?
            if let dragState {
                ball = self.ball(withID: dragState.ballID)
            } else {
                ball = nil
            }
            let velocity = dragState?.velocityTracker.velocity ?? .zero
            self.dragState = nil

            ball?.simulationVelocity = CGVector(dx: velocity.x, dy: velocity.y)
            
            tempOverrideMouseCatcherRects.removeAll()
        default: ()
        }
    }

    private var mouseScenePos: CGPoint {
        let viewPos = sceneView.convert(self.view.window!.mouseLocationOutsideOfEventStream, from: nil)
        let scenePos = scene.convertPoint(fromView: viewPos)
        return scenePos
    }

    // MARK: - Animations
    @discardableResult
    func animateBallFromRect(_ rect: CGRect) -> Ball? {
        guard let screen = self.view.window?.screen else { return nil }
        var targetRect = rect
        targetRect = targetRect.byConstraining(withinBounds: screen.frame)

        let spawnIndex = balls.count
        let color = Ball.Color.allCases.randomElement() ?? .red
        let ball = Ball(
            radius: Constants.radius,
            pos: .init(x: targetRect.midX, y: targetRect.midY),
            id: UUID().uuidString,
            color: color
        )
        balls.append(ball)
        scene.addChild(ball)

        dragState = nil
        // Launch the ball away from the dock edge and fan out consecutive balls.
        let strength: CGFloat = 1_450
        var launchVelocity = CGVector(dx: 0, dy: 0)
        let distFromLeft = targetRect.midX - screen.frame.minX
        let distFromRight = screen.frame.maxX - targetRect.midX
        let distFromBottom = targetRect.midY - screen.frame.minY
        if distFromBottom < 200 {
            launchVelocity.dy = strength
        }
        if distFromLeft < 200 {
            launchVelocity.dx = strength
        } else if distFromRight < 200 {
            launchVelocity.dx = -strength
        }
        let spawnFan = CGFloat((spawnIndex % 5) - 2)
        launchVelocity.dx += spawnFan * 250
        launchVelocity.dy += CGFloat(spawnIndex % 3) * 80

        ball.setScale(rect.width / (ball.radius * 2))
        let scaleUp = SKAction.scale(to: 1, duration: 0.5)
        ball.run(scaleUp)

        ball.animateShadow(visible: true, duration: 0.5)

        ball.position = CGPoint(x: targetRect.midX, y: targetRect.midY)
        ball.simulationVelocity = launchVelocity

        return ball
    }

    func animatePutBack(rect: CGRect, completion: @escaping () -> Void) {
        let ballsToRemove = balls
        guard !ballsToRemove.isEmpty else {
            completion()
            return
        }
        dragState = nil
        tempOverrideMouseCatcherRects.removeAll()

        var remaining = ballsToRemove.count
        for ball in ballsToRemove {
            ball.participatesInSimulation = false
            ball.simulationVelocity = .zero

            let scale = SKAction.scale(to: rect.width / (ball.radius * 2), duration: 0.25)
            ball.animateShadow(visible: false, duration: 0.25)
            ball.run(scale)
            let move = SKAction.move(to: CGPoint(x: rect.midX, y: rect.midY), duration: 0.25)
            ball.run(move) {
                self.removeBall(ball)
                remaining -= 1
                if remaining == 0 {
                    completion()
                }
            }
        }
    }

    private func ball(withID id: String) -> Ball? {
        balls.first { $0.id == id }
    }

    private func ball(containing point: CGPoint) -> Ball? {
        balls.reversed().first { ball in
            let dx = point.x - ball.position.x
            let dy = point.y - ball.position.y
            return dx * dx + dy * dy <= ball.radius * ball.radius
        }
    }

    private func removeBall(_ ball: Ball) {
        ball.removeFromParent()
        balls.removeAll { $0 === ball }
    }
}

extension BallViewController: SKSceneDelegate {
    func update(_ currentTime: TimeInterval, for scene: SKScene) {
        let draggedBall = dragState.flatMap { ball(withID: $0.ballID) }
        let collisions = physicsEngine.update(
            at: currentTime,
            balls: balls,
            bounds: view.bounds,
            draggedBall: draggedBall,
            dragTarget: currentDragTarget
        )
        handle(collisions: collisions)

        if !balls.isEmpty {
            let positions = Dictionary(uniqueKeysWithValues: balls.map { ($0.id, $0.rect) })
            delegate?.ballViewController(self, ballsDidMoveToPositions: positions)
        }
    }

    func didFinishUpdate(for scene: SKScene) {
        for ball in balls {
            ball.update()
        }
    }
}

private extension BallViewController {
    func handle(collisions: [BallPhysicsEngine.Collision]) {
        guard !collisions.isEmpty else { return }

        for collision in collisions {
            let strength = remap(
                x: collision.impactSpeed,
                domainStart: 90,
                domainEnd: 1_600,
                rangeStart: 0,
                rangeEnd: 0.7
            )
            collision.ball.didCollide(strength: strength, normal: collision.normal)
        }

        guard let strongest = collisions.max(by: { $0.impactSpeed < $1.impactSpeed }) else { return }
        let volume = remap(
            x: strongest.impactSpeed,
            domainStart: 90,
            domainEnd: 1_600,
            rangeStart: 0.05,
            rangeEnd: 0.7
        )
        var sounds = collisionSounds
        sounds.shuffle()
        guard let sound = sounds.first(where: { !$0.isPlaying }) else { return }
        sound.volume = Float(volume)
        sound.play()
    }
}

extension CGRect {
    func byConstraining(withinBounds bounds: CGRect) -> CGRect {
        var r = self
        if r.minX < bounds.minX {
            r.origin.x = bounds.minX
        }
        if r.maxX > bounds.maxX {
            r.origin.x = bounds.maxX - r.width
        }
        if r.minY < bounds.minY {
            r.origin.y = bounds.minY
        }
        if r.maxY > bounds.maxY {
            r.origin.y = bounds.maxY - r.height
        }
        return r
    }
}

private struct VelocityTracker {
    struct Sample {
        var time: TimeInterval
        var pos: CGPoint
    }
    var samples = [Sample]()

    mutating func add(pos: CGPoint) {
        let time = CACurrentMediaTime()
        let sample = Sample(time: time, pos: pos)
        samples.append(sample)
        self.samples = filteredSamples
    }

    private var filteredSamples: [Sample] {
        let time = CACurrentMediaTime()
        let filtered = samples.filter { time - $0.time < 0.1 }
        return filtered
    }

    var velocity: CGPoint {
        let samples = filteredSamples
        guard samples.count >= 2 else { return .zero }
        let first = samples.first!
        let last = samples.last!
        let delta = CGPoint(x: last.pos.x - first.pos.x, y: last.pos.y - first.pos.y)
        let time = last.time - first.time
        return CGPoint(x: delta.x / CGFloat(time), y: delta.y / CGFloat(time))
    }
}
