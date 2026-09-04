import Cocoa
import SpriteKit
import SwiftUI

protocol BallViewControllerDelegate: AnyObject {
    func ballViewController(_ vc: BallViewController, ballsDidMoveToPositions positions: [String: CGRect])
}

class BallViewController: NSViewController {
    weak var delegate: BallViewControllerDelegate?

    let scene = SKScene(size: .init(width: 200, height: 200))
    let sceneView = SKView()

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
        scene.physicsWorld.contactDelegate = self
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
        scene.physicsBody = SKPhysicsBody(edgeLoopFrom: view.bounds)
        scene.physicsBody?.categoryBitMask = PhysicsCategory.wall
        scene.physicsBody?.collisionBitMask = PhysicsCategory.ball
        scene.physicsBody?.contactTestBitMask = PhysicsCategory.ball
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
                oldBall?.physicsBody?.isDynamic = true
                oldBall?.beingDragged = false
            }

            if let dragState, let ball = ball(withID: dragState.ballID) {
                ball.physicsBody?.isDynamic = false
                let pos = dragState.currentBallPos
                let rect = CGRect(origin: .init(x: pos.x - ball.radius, y: pos.y - ball.radius), size: .init(width: ball.radius * 2, height: ball.radius * 2))
                let constrainedRect = rect.byConstraining(withinBounds: view.bounds)
                ball.position = CGPoint(x: constrainedRect.midX, y: constrainedRect.midY)
                ball.beingDragged = true
            } else if let oldValue {
                self.ball(withID: oldValue.ballID)?.physicsBody?.isDynamic = true
            }
        }
    }

    func onMouseDown(ballID: String? = nil) {
        let scenePos = mouseScenePos
        var hitBall = ball(containing: scenePos)
        if hitBall == nil, let ballID {
            hitBall = self.ball(withID: ballID)
        }
        if let hitBall {
            self.dragState = .init(ballID: hitBall.id, ballStart: hitBall.position, mouseStart: scenePos, currentMousePos: scenePos)
        } else {
            self.dragState = nil
        }
    }

    func onMouseDrag(ballID: String? = nil) {
        if var dragState {
            dragState.currentMousePos = mouseScenePos
            dragState.velocityTracker.add(pos: dragState.currentMousePos)
            self.dragState = dragState
        }
    }

    func onMouseUp(ballID: String? = nil) {
        let ball: Ball?
        if let dragState {
            ball = self.ball(withID: dragState.ballID)
        } else {
            ball = nil
        }
        let velocity = dragState?.velocityTracker.velocity ?? .zero
        self.dragState = nil

        if velocity.length > 0 {
            ball?.physicsBody?.applyImpulse(CGVector(dx: velocity.x, dy: velocity.y))
        }
    }

    func onScroll(event: NSEvent, ballID: String? = nil) {
        switch event.phase {
        case .began:
            let scenePos = mouseScenePos
            var hitBall = ball(containing: scenePos)
            if hitBall == nil, let ballID {
                hitBall = self.ball(withID: ballID)
            }
            if let hitBall {
                dragState = .init(ballID: hitBall.id, ballStart: hitBall.position, mouseStart: .zero, currentMousePos: .zero)
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

            if velocity.length > 0 {
                ball?.physicsBody?.applyImpulse(CGVector(dx: velocity.x, dy: velocity.y))
            }
            
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
        // self.ball?.position = CGPoint(x: targetRect.midX, y: targetRect.midY)

        // Add impulse to fling ball to center of screen
        let strength: CGFloat = 2000
        var impulse = CGVector(dx: 0, dy: 0)
        let distFromLeft = targetRect.midX - screen.frame.minX
        let distFromRight = screen.frame.maxX - targetRect.midX
        let distFromBottom = targetRect.midY - screen.frame.minY
        if distFromBottom < 200 {
            impulse.dy = strength
        }
        if distFromLeft < 200 {
            impulse.dx = strength
        } else if distFromRight < 200 {
            impulse.dx = -strength
        }
        let spawnFan = CGFloat((spawnIndex % 5) - 2)
        impulse.dx += spawnFan * 250
        impulse.dy += CGFloat(spawnIndex % 3) * 80

        ball.setScale(rect.width / (ball.radius * 2))
        let scaleUp = SKAction.scale(to: 1, duration: 0.5)
        ball.run(scaleUp)
//        ball.physicsBody?.applyImpulse(impulse)

        ball.animateShadow(visible: true, duration: 0.5)

        nextRenderBlocks.append {
            ball.position = CGPoint(x: targetRect.midX, y: targetRect.midY)
            ball.physicsBody?.applyImpulse(impulse)
        }

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
            ball.physicsBody?.isDynamic = false
            ball.physicsBody?.affectedByGravity = false
            ball.physicsBody?.velocity = .zero

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

    fileprivate var nextRenderBlocks = [() -> Void]()

    private func ball(withID id: String) -> Ball? {
        balls.first { $0.id == id }
    }

    private func ball(containing point: CGPoint) -> Ball? {
        balls.reversed().first { $0.contains(point) }
    }

    private func removeBall(_ ball: Ball) {
        ball.removeFromParent()
        ball.physicsBody = nil
        balls.removeAll { $0 === ball }
    }
}

extension BallViewController: SKSceneDelegate {
    func update(_ currentTime: TimeInterval, for scene: SKScene) {
        if !balls.isEmpty {
            let positions = Dictionary(uniqueKeysWithValues: balls.map { ($0.id, $0.rect) })
            delegate?.ballViewController(self, ballsDidMoveToPositions: positions)
        }
    }

    func didSimulatePhysics(for scene: SKScene) {
        let blocks = nextRenderBlocks
        nextRenderBlocks = []
        for block in blocks {
            block()
        }
    }

    func didFinishUpdate(for scene: SKScene) {
        for ball in balls {
            ball.update()
//            ball.view.setCenter(CGPoint(x: ball.position.x, y: ball.position.y))
        }
    }
}

extension NSView {
    func setCenter(_ pt: CGPoint) {
        self.frame = CGRect(x: pt.x - bounds.width / 2, y: pt.y - bounds.height / 2, width: bounds.width, height: bounds.height)
    }
}

extension BallViewController: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        let minImpulse: Double = 1000
        let maxImpulse: Double = 2000

        let collisionStrength = remap(x: contact.collisionImpulse, domainStart: minImpulse, domainEnd: maxImpulse, rangeStart: 0, rangeEnd: 0.5)
        guard collisionStrength > 0 else { return }

        let bodyABall = contact.bodyA.node as? Ball
        let bodyBBall = contact.bodyB.node as? Ball
        bodyABall?.didCollide(strength: collisionStrength, normal: contact.contactNormal)
        bodyBBall?.didCollide(strength: collisionStrength, normal: CGVector(dx: -contact.contactNormal.dx, dy: -contact.contactNormal.dy))

        DispatchQueue.global().async {
            var sounds = self.collisionSounds
            sounds.shuffle()
            guard let soundToUse = sounds.first(where: { !$0.isPlaying }) else {
                return
            }
            soundToUse.volume = Float(collisionStrength)
            soundToUse.play()
        }
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

extension CGPoint {
    var length: CGFloat {
        return sqrt(x * x + y * y)
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
