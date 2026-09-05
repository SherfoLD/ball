import AppKit

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError(message) }
}
func near(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool { abs(lhs - rhs) < 0.001 }
let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
let bottom = CGRect(x: 0, y: 0, width: 1000, height: 80)
let left = CGRect(x: 0, y: 0, width: 80, height: 800)
let right = CGRect(x: 920, y: 0, width: 80, height: 800)
let tight = CGRect(x: 300, y: 0, width: 400, height: 80)
func overlaps(_ ball: Ball, _ obstacle: CGRect) -> Bool {
    let x = min(max(ball.position.x, obstacle.minX), obstacle.maxX)
    let y = min(max(ball.position.y, obstacle.minY), obstacle.maxY)
    return hypot(ball.position.x - x, ball.position.y - y) < ball.radius - 0.001
}
@discardableResult
func advance(_ engine: BallPhysicsEngine, _ balls: [Ball], _ obstacles: [CGRect], frames: Int = 1,
             start: Double = 0, dragged: Ball? = nil, target: CGPoint? = nil) -> [BallPhysicsEngine.Collision] {
    var collisions: [BallPhysicsEngine.Collision] = []
    for frame in 0...frames {
        collisions += engine.update(at: start + Double(frame) / 60, balls: balls, bounds: bounds,
                                    obstacles: obstacles, draggedBall: dragged, dragTarget: target)
    }
    return collisions
}

// Screen origins must be relative to each display, never to global (0, 0).
for origin in [CGPoint.zero, CGPoint(x: -1000, y: -800), CGPoint(x: 1000, y: 800)] {
    let frame = bounds.offsetBy(dx: origin.x, dy: origin.y)
    let visible = CGRect(x: origin.x, y: origin.y + 80, width: 1000, height: 695)
    let geometry = DockGeometry.reservedArea(frame: frame, visibleFrame: visible)
    check(geometry?.position == .bottom && geometry?.rect == bottom.offsetBy(dx: origin.x, dy: origin.y), "Bottom Dock on offset display")
    check(DockGeometry.reservedArea(frame: frame, visibleFrame: CGRect(x: origin.x, y: origin.y, width: 1000, height: 775)) == nil, "Menu bar alone isn't a Dock")
    check(DockGeometry.reservedArea(frame: frame, visibleFrame: CGRect(x: origin.x, y: origin.y + 1, width: 1000, height: 774)) == nil, "Hidden Dock activation strip isn't an obstacle")
}
check(DockGeometry.reservedArea(frame: bounds, visibleFrame: CGRect(x: 80, y: 0, width: 920, height: 775))?.rect == left, "Left Dock")
check(DockGeometry.reservedArea(frame: bounds, visibleFrame: CGRect(x: 0, y: 0, width: 920, height: 775))?.rect == right, "Right Dock")
check(DockGeometry.windowArea(bounds, on: bounds) == nil, "Reject full-screen Dock surface")
check(DockGeometry.windowArea(tight, on: bounds)?.rect == tight, "Accept tight Dock surface")
check(DockGeometry.windowArea(CGRect(x: 0, y: -79, width: 500, height: 80), on: bounds) == nil, "Reject hidden Dock sliver")
check(DockGeometry.windowArea(CGRect(x: 300, y: 200, width: 400, height: 80), on: bounds) == nil, "Reject detached Dock-owned window")
check(DockGeometry.appKitRect(from: CGRect(x: -1000, y: 1500, width: 1000, height: 100), primaryScreenTop: 800) == CGRect(x: -1000, y: -800, width: 1000, height: 100), "Quartz conversion on lower secondary display")

for obstacle in [bottom, left, right] {
    let engine = BallPhysicsEngine()
    let ball = Ball(obstacle.midX, obstacle.midY)
    advance(engine, [ball], [obstacle])
    check(!overlaps(ball, obstacle), "Recover ball embedded in newly shown Dock")
    check(bounds.insetBy(dx: ball.radius - 0.001, dy: ball.radius - 0.001).contains(ball.position), "Dock recovery must stay on screen")
}

let falling = Ball(500, 300)
falling.simulationVelocity.dy = -8000
let fallingEngine = BallPhysicsEngine()
let impacts = advance(fallingEngine, [falling], [bottom], frames: 2)
check(!overlaps(falling, bottom) && falling.simulationVelocity.dy > 0, "Fast ball bounces off Dock")
check(impacts.contains { $0.normal.dy > 0 && $0.impactSpeed > 90 }, "Dock supplies collision feedback")
advance(fallingEngine, [falling], [bottom], frames: 600, start: 2.0 / 60)
check(near(falling.position.y, 130) && near(falling.simulationVelocity.dy, 0), "Ball settles on Dock")
advance(fallingEngine, [falling], [], frames: 120, start: 602.0 / 60)
check(near(falling.position.y, 50), "Ball falls to screen edge after Dock hides")

for (obstacle, x, speed, normal) in [(left, CGFloat(150), CGFloat(-8000), CGFloat(1)), (right, CGFloat(850), CGFloat(8000), CGFloat(-1))] {
    let ball = Ball(x, 400)
    ball.simulationVelocity.dx = speed
    let impacts = advance(BallPhysicsEngine(), [ball], [obstacle])
    check(!overlaps(ball, obstacle) && ball.simulationVelocity.dx * normal > 0, "Side Dock rebound")
    check(impacts.contains { $0.normal.dx == normal }, "Side Dock collision normal")
}

let besideDock = Ball(200, 60)
advance(BallPhysicsEngine(), [besideDock], [tight], frames: 120)
check(near(besideDock.position.y, 50), "Tight bounds leave space beside the Dock")
let corner = Ball(280, 110)
advance(BallPhysicsEngine(), [corner], [tight])
check(!overlaps(corner, tight), "Circle versus Dock corner")

let dragged = Ball(500, 300)
dragged.beingDragged = true
advance(BallPhysicsEngine(), [dragged], [bottom], frames: 60, dragged: dragged, target: CGPoint(x: 500, y: 0))
check(near(dragged.position.y, 130), "Dragging cannot cover Dock")
let crossing = Ball(100, 60)
crossing.beingDragged = true
advance(BallPhysicsEngine(), [crossing], [tight], frames: 60, dragged: crossing, target: CGPoint(x: 900, y: 60))
check(crossing.position.x <= 250.001 && !overlaps(crossing, tight), "Dragging cannot tunnel through Dock")

// Dragging still separates balls, but gives them a gentle push instead of
// launching them at cursor speed. Check either ordering in the pair solver.
for reverseOrder in [false, true] {
    let held = Ball(300, 400)
    let pushed = Ball(400, 400)
    held.beingDragged = true
    let target = CGPoint(x: 320, y: 400)
    advance(BallPhysicsEngine(), reverseOrder ? [pushed, held] : [held, pushed], [],
            dragged: held, target: target)
    check(held.position == target, "Softer collisions preserve cursor tracking")
    check(pushed.simulationVelocity.dx > 0 && pushed.simulationVelocity.dx < 600,
          "Dragged ball transfers less than half its 1200-point/second cursor speed")
    check(hypot(pushed.position.x - held.position.x, pushed.position.y - held.position.y) > 99,
          "Softer dragging still keeps balls separated")
}

let thrown = Ball(300, 400)
let struck = Ball(400, 400)
thrown.simulationVelocity.dx = 1200
advance(BallPhysicsEngine(), [thrown, struck], [])
check(struck.simulationVelocity.dx > 1000, "Free ball collisions retain their momentum transfer")

let pile = (0..<5).map { Ball(500, 140 + CGFloat($0) * 105, id: String($0)) }
advance(BallPhysicsEngine(), pile, [bottom], frames: 600)
check(pile.allSatisfy { !overlaps($0, bottom) }, "Pile stays above Dock")
check(zip(pile, pile.dropFirst()).allSatisfy { $1.position.y - $0.position.y > 99 }, "Pile remains separated")
let returning = Ball(500, 40)
returning.participatesInSimulation = false
advance(BallPhysicsEngine(), [returning], [bottom])
check(returning.position == CGPoint(x: 500, y: 40), "Put-back animation remains outside physics")

let spawn = BallPhysicsEngine().positionOutsideObstacles(CGPoint(x: 20, y: 20), radius: 100, bounds: bounds, obstacles: [left])
check(spawn.x >= 180 && spawn.y >= 100, "Launch starts clear of Dock and screen edges")

// All four corners constrain dragging symmetrically and bounce free balls
// inward. With a 50-point ball, the previous 100-point curve is now 80 points.
for isLeft in [true, false] {
    for isBottom in [true, false] {
        let engine = BallPhysicsEngine()
        let signX: CGFloat = isLeft ? 1 : -1
        let signY: CGFloat = isBottom ? 1 : -1
        let edgeX: CGFloat = isLeft ? 0 : bounds.maxX
        let edgeY: CGFloat = isBottom ? 0 : bounds.maxY
        let held = Ball(edgeX + signX * 100, edgeY + signY * 100)
        held.beingDragged = true
        advance(engine, [held], [], dragged: held, target: CGPoint(x: edgeX, y: edgeY))
        let inset = 50 + 80 * (1 - 1 / sqrt(CGFloat(2)))
        check(near(held.position.x, edgeX + signX * inset) &&
              near(held.position.y, edgeY + signY * inset),
              "All corner curves are 20% smaller and constrain dragging equally")

        let moving = Ball(edgeX + signX * 80, edgeY + signY * 80)
        moving.simulationVelocity = CGVector(dx: -signX * 1200, dy: -signY * 1200)
        let impacts = advance(BallPhysicsEngine(), [moving], [])
        check(moving.simulationVelocity.dx * signX > 0 && moving.simulationVelocity.dy * signY > 0,
              "Free balls bounce inward at every curved corner")
        check(impacts.contains { $0.normal.dx * signX > 0 && $0.normal.dy * signY > 0 },
              "Corner collisions supply a diagonal inward normal")
    }
}

let tracker = DockGeometryTracker()
for obstacles in [[], [bottom], [left], [right]] as [[CGRect]] {
    let floor: CGFloat = obstacles == [bottom] ? 80 : 0
    let leftEdge: CGFloat = obstacles == [left] ? 80 : 0
    let rightEdge: CGFloat = obstacles == [right] ? 920 : 1000
    for fromLeft in [true, false] {
        let edge = fromLeft ? leftEdge : rightEdge
        let direction: CGFloat = fromLeft ? 1 : -1
        let engine = BallPhysicsEngine()
        let trapped = Ball(edge + direction * 80, floor + 50)
        let pusher = Ball(edge + direction * 230, floor + 50)
        pusher.beingDragged = true
        _ = engine.update(at: 0, balls: [trapped, pusher], bounds: bounds,
                          obstacles: obstacles, draggedBall: pusher, dragTarget: pusher.position)
        for frame in 1...120 {
            let targetX = edge + direction * (230 - min(CGFloat(frame), 60) * 160 / 60)
            _ = engine.update(at: Double(frame) / 60, balls: [trapped, pusher], bounds: bounds,
                              obstacles: obstacles, draggedBall: pusher,
                              dragTarget: CGPoint(x: targetX, y: floor + 50))
        }
        check(trapped.position.y > pusher.position.y + 80,
              "A ball pushed into either bottom corner must climb above the pusher")
        check(hypot(trapped.position.x - pusher.position.x, trapped.position.y - pusher.position.y) > 99,
              "Pushing into a bottom corner must leave balls separated")
        check(obstacles.allSatisfy { !overlaps(trapped, $0) && !overlaps(pusher, $0) },
              "Corner ramps must keep both balls outside the Dock")
        advance(engine, [trapped], obstacles, frames: 240, start: 2)
        check((trapped.position.x - edge) * direction > 110 && trapped.position.y < floor + 60,
              "Ball rolls back toward the floor when the pusher is removed")
    }
}
if let screen = NSScreen.screens.first {
    print("Live Dock geometry: \(String(describing: tracker.geometry(on: screen, at: ProcessInfo.processInfo.systemUptime)))")
}
print("Passed \(checks) Dock geometry and physics checks")
