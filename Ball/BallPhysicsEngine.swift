import CoreGraphics
import Foundation

/// A small, deterministic circle solver tailored to the desktop-sized balls.
/// SpriteKit remains the renderer, but does not own the simulation state.
final class BallPhysicsEngine {
    struct Collision {
        let ball: Ball
        let normal: CGVector
        let impactSpeed: CGFloat
    }

    private let fixedTimeStep: CGFloat = 1.0 / 240.0
    private let maximumStepsPerFrame = 16
    private let maximumDragStepsPerFrame = 64
    private let solverIterations = 10
    private let gravity = CGVector(dx: 0, dy: -1_800)
    private let ballRestitution: CGFloat = 0.72
    private let dragMomentumTransfer: CGFloat = 0.25
    private let wallRestitution: CGFloat = 0.68
    private let friction: CGFloat = 0.22
    private let restingImpactSpeed: CGFloat = 90
    private let maximumSpeed: CGFloat = 8_000

    private var previousTime: TimeInterval?
    private var accumulatedTime: CGFloat = 0

    func resetClock() {
        previousTime = nil
        accumulatedTime = 0
    }

    func update(
        at currentTime: TimeInterval,
        balls: [Ball],
        bounds: CGRect,
        obstacles: [CGRect] = [],
        draggedBall: Ball?,
        dragTarget: CGPoint?
    ) -> [Collision] {
        guard !bounds.isEmpty else { return [] }

        guard let previousTime else {
            self.previousTime = currentTime
            return []
        }

        // A debugger stop or wake from sleep must not turn into seconds of gravity.
        let frameTime = min(max(CGFloat(currentTime - previousTime), 0), 1.0 / 15.0)
        self.previousTime = currentTime
        accumulatedTime = min(
            accumulatedTime + frameTime,
            fixedTimeStep * CGFloat(maximumStepsPerFrame)
        )

        let timeStepCount = min(Int(accumulatedTime / fixedTimeStep), maximumStepsPerFrame)
        guard timeStepCount > 0 else { return [] }

        let dragStart = draggedBall?.position
        let clampedDragTarget = draggedBall.flatMap { ball in
            dragTarget.map { clamp($0, for: ball, inside: bounds) }
        }
        let dragDistance = dragStart.flatMap { start in
            clampedDragTarget.map { target in
                CGVector(dx: target.x - start.x, dy: target.y - start.y).length
            }
        } ?? 0
        let maximumDragTravel = max((draggedBall?.radius ?? 0) * 0.25, 8)
        let requiredDragSteps = Int(ceil(dragDistance / maximumDragTravel))
        let stepCount = max(timeStepCount, min(requiredDragSteps, maximumDragStepsPerFrame))
        let simulatedTime = CGFloat(timeStepCount) * fixedTimeStep
        let simulationStep = simulatedTime / CGFloat(stepCount)

        var strongestCollisions: [ObjectIdentifier: Collision] = [:]
        for _ in 0..<stepCount {
            if let draggedBall, let dragStart, let clampedDragTarget {
                // Move from the last resolved position, so dragging across an
                // obstacle slides along it instead of teleporting through it.
                let nextPosition = CGPoint(
                    x: draggedBall.position.x + (clampedDragTarget.x - dragStart.x) / CGFloat(stepCount),
                    y: draggedBall.position.y + (clampedDragTarget.y - dragStart.y) / CGFloat(stepCount)
                )
                let constrainedPosition = positionOutsideObstacles(
                    nextPosition, radius: draggedBall.radius, bounds: bounds, obstacles: obstacles
                )
                draggedBall.simulationVelocity = CGVector(
                    dx: (constrainedPosition.x - draggedBall.position.x) / simulationStep,
                    dy: (constrainedPosition.y - draggedBall.position.y) / simulationStep
                )
                draggedBall.position = constrainedPosition
            }

            simulateStep(
                balls: balls,
                bounds: bounds,
                obstacles: obstacles,
                draggedBall: draggedBall,
                timeStep: simulationStep,
                collisions: &strongestCollisions
            )
        }

        accumulatedTime -= simulatedTime
        return Array(strongestCollisions.values)
    }

    private func simulateStep(
        balls: [Ball],
        bounds: CGRect,
        obstacles: [CGRect],
        draggedBall: Ball?,
        timeStep: CGFloat,
        collisions: inout [ObjectIdentifier: Collision]
    ) {
        let activeBalls = balls.filter(\.participatesInSimulation)
        let wallBounds = boundaryBounds(inside: bounds, obstacles: obstacles)

        for ball in activeBalls where ball !== draggedBall {
            ball.simulationVelocity.dx += gravity.dx * timeStep
            ball.simulationVelocity.dy += gravity.dy * timeStep

            // Very light air resistance prevents numerical energy from accumulating
            // without making the balls feel as though they are moving through syrup.
            let damping = pow(CGFloat(0.998), timeStep)
            ball.simulationVelocity.dx *= damping
            ball.simulationVelocity.dy *= damping
            ball.simulationVelocity = ball.simulationVelocity.limited(to: maximumSpeed)

            ball.position.x += ball.simulationVelocity.dx * timeStep
            ball.position.y += ball.simulationVelocity.dy * timeStep
        }

        // Sequential impulses plus repeated position projection remain stable in
        // tightly packed piles, unlike resolving each collision only once.
        for iteration in 0..<solverIterations {
            for indexA in activeBalls.indices {
                for indexB in activeBalls.indices where indexB > indexA {
                    resolve(
                        activeBalls[indexA],
                        activeBalls[indexB],
                        restitutionEnabled: iteration == 0,
                        collisions: &collisions
                    )
                }
            }

            for ball in activeBalls {
                resolveWalls(
                    for: ball,
                    inside: wallBounds,
                    isKinematic: ball === draggedBall,
                    restitutionEnabled: iteration == 0,
                    collisions: &collisions
                )
                for obstacle in obstacles {
                    guard let contact = obstacleContact(
                        at: ball.position, radius: ball.radius, obstacle: obstacle, bounds: bounds
                    ) else { continue }
                    ball.position = contact.position
                    if ball !== draggedBall {
                        bounce(ball, wallNormal: contact.normal, restitutionEnabled: iteration == 0, collisions: &collisions)
                    }
                }
            }
        }
    }

    private func resolve(
        _ ballA: Ball,
        _ ballB: Ball,
        restitutionEnabled: Bool,
        collisions: inout [ObjectIdentifier: Collision]
    ) {
        let delta = CGVector(
            dx: ballB.position.x - ballA.position.x,
            dy: ballB.position.y - ballA.position.y
        )
        let minimumDistance = ballA.radius + ballB.radius
        let distanceSquared = delta.squaredLength
        guard distanceSquared < minimumDistance * minimumDistance else { return }

        let distance = sqrt(max(distanceSquared, 0))
        let normal: CGVector
        if distance > 0.0001 {
            normal = delta / distance
        } else {
            // A stable direction is required when two centers exactly coincide.
            normal = ballA.id < ballB.id ? CGVector(dx: 1, dy: 0) : CGVector(dx: -1, dy: 0)
        }

        let inverseMassA = ballA.beingDragged ? 0 : ballA.inverseMass
        let inverseMassB = ballB.beingDragged ? 0 : ballB.inverseMass
        let inverseMassSum = inverseMassA + inverseMassB
        guard inverseMassSum > 0 else { return }

        let penetration = minimumDistance - distance
        let correctionMagnitude = max(penetration - 0.05, 0) * 0.82 / inverseMassSum
        let correction = normal * correctionMagnitude
        if inverseMassA > 0 {
            ballA.position.x -= correction.dx * inverseMassA
            ballA.position.y -= correction.dy * inverseMassA
        }
        if inverseMassB > 0 {
            ballB.position.x += correction.dx * inverseMassB
            ballB.position.y += correction.dy * inverseMassB
        }

        var relativeVelocity = collisionVelocity(of: ballB) - collisionVelocity(of: ballA)
        let velocityAlongNormal = relativeVelocity.dot(normal)
        guard velocityAlongNormal < 0 else { return }

        let impactSpeed = -velocityAlongNormal
        let restitution = restitutionEnabled && impactSpeed >= restingImpactSpeed ? ballRestitution : 0
        let normalImpulseMagnitude = -(1 + restitution) * velocityAlongNormal / inverseMassSum
        let normalImpulse = normal * normalImpulseMagnitude
        apply(normalImpulse, to: ballA, inverseMass: inverseMassA, sign: -1)
        apply(normalImpulse, to: ballB, inverseMass: inverseMassB, sign: 1)

        relativeVelocity = collisionVelocity(of: ballB) - collisionVelocity(of: ballA)
        let tangentVelocity = relativeVelocity - normal * relativeVelocity.dot(normal)
        if tangentVelocity.squaredLength > 0.0001 {
            let tangent = tangentVelocity.normalized
            let rawFrictionImpulse = -relativeVelocity.dot(tangent) / inverseMassSum
            let frictionImpulseMagnitude = min(
                max(rawFrictionImpulse, -friction * normalImpulseMagnitude),
                friction * normalImpulseMagnitude
            )
            let frictionImpulse = tangent * frictionImpulseMagnitude
            apply(frictionImpulse, to: ballA, inverseMass: inverseMassA, sign: -1)
            apply(frictionImpulse, to: ballB, inverseMass: inverseMassB, sign: 1)
        }

        if restitutionEnabled && impactSpeed >= restingImpactSpeed {
            record(ballA, normal: -normal, impactSpeed: impactSpeed, in: &collisions)
            record(ballB, normal: normal, impactSpeed: impactSpeed, in: &collisions)
        }
    }

    private func collisionVelocity(of ball: Ball) -> CGVector {
        // Keep cursor tracking exact, but soften the push into other balls.
        // Use the same velocity for every solver iteration and friction impulse.
        ball.simulationVelocity * (ball.beingDragged ? dragMomentumTransfer : 1)
    }

    private func resolveWalls(
        for ball: Ball,
        inside bounds: CGRect,
        isKinematic: Bool,
        restitutionEnabled: Bool,
        collisions: inout [ObjectIdentifier: Collision]
    ) {
        // A dragged ball is deliberately immovable. Its target is clamped before
        // simulation, so other balls yield to it with effectively infinite mass.
        guard !isKinematic else { return }

        let minX = bounds.minX + ball.radius
        let maxX = bounds.maxX - ball.radius
        let minY = bounds.minY + ball.radius
        let maxY = bounds.maxY - ball.radius

        if minX > maxX || minY > maxY {
            ball.position = CGPoint(x: bounds.midX, y: bounds.midY)
            ball.simulationVelocity = .zero
            return
        }

        if let contact = cornerContact(at: ball.position, radius: ball.radius, bounds: bounds) {
            ball.position = contact.position
            bounce(ball, wallNormal: contact.normal, restitutionEnabled: restitutionEnabled, collisions: &collisions)
            return
        }

        if ball.position.x < minX {
            ball.position.x = minX
            bounce(ball, wallNormal: CGVector(dx: 1, dy: 0), restitutionEnabled: restitutionEnabled, collisions: &collisions)
        } else if ball.position.x > maxX {
            ball.position.x = maxX
            bounce(ball, wallNormal: CGVector(dx: -1, dy: 0), restitutionEnabled: restitutionEnabled, collisions: &collisions)
        }

        if ball.position.y < minY {
            ball.position.y = minY
            bounce(ball, wallNormal: CGVector(dx: 0, dy: 1), restitutionEnabled: restitutionEnabled, collisions: &collisions)
        } else if ball.position.y > maxY {
            ball.position.y = maxY
            bounce(ball, wallNormal: CGVector(dx: 0, dy: -1), restitutionEnabled: restitutionEnabled, collisions: &collisions)
        }
    }

    private func bounce(
        _ ball: Ball,
        wallNormal: CGVector,
        restitutionEnabled: Bool,
        collisions: inout [ObjectIdentifier: Collision]
    ) {
        let velocityIntoWall = ball.simulationVelocity.dot(wallNormal)
        guard velocityIntoWall < 0 else { return }

        let impactSpeed = -velocityIntoWall
        let restitution = restitutionEnabled && impactSpeed >= restingImpactSpeed ? wallRestitution : 0
        ball.simulationVelocity = ball.simulationVelocity - wallNormal * ((1 + restitution) * velocityIntoWall)

        let tangent = CGVector(dx: -wallNormal.dy, dy: wallNormal.dx)
        let tangentSpeed = ball.simulationVelocity.dot(tangent)
        let frictionDelta = min(abs(tangentSpeed), friction * impactSpeed)
        ball.simulationVelocity = ball.simulationVelocity - tangent * (frictionDelta * tangentSpeed.scalarSign)

        if restitutionEnabled && impactSpeed >= restingImpactSpeed {
            record(ball, normal: wallNormal, impactSpeed: impactSpeed, in: &collisions)
        }
    }

    private func apply(_ impulse: CGVector, to ball: Ball, inverseMass: CGFloat, sign: CGFloat) {
        guard inverseMass > 0 else { return }
        ball.simulationVelocity.dx += impulse.dx * inverseMass * sign
        ball.simulationVelocity.dy += impulse.dy * inverseMass * sign
        ball.simulationVelocity = ball.simulationVelocity.limited(to: maximumSpeed)
    }

    private func record(
        _ ball: Ball,
        normal: CGVector,
        impactSpeed: CGFloat,
        in collisions: inout [ObjectIdentifier: Collision]
    ) {
        let key = ObjectIdentifier(ball)
        if impactSpeed > (collisions[key]?.impactSpeed ?? 0) {
            collisions[key] = Collision(ball: ball, normal: normal, impactSpeed: impactSpeed)
        }
    }

    private func clamp(_ point: CGPoint, for ball: Ball, inside bounds: CGRect) -> CGPoint {
        clamp(point, radius: ball.radius, inside: bounds)
    }

    private func clamp(_ point: CGPoint, radius: CGFloat, inside bounds: CGRect) -> CGPoint {
        let minX = bounds.minX + radius
        let maxX = bounds.maxX - radius
        let minY = bounds.minY + radius
        let maxY = bounds.maxY - radius
        guard minX <= maxX, minY <= maxY else {
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }
        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    func positionOutsideObstacles(
        _ point: CGPoint, radius: CGFloat, bounds: CGRect, obstacles: [CGRect]
    ) -> CGPoint {
        let wallBounds = boundaryBounds(inside: bounds, obstacles: obstacles)
        var position = clamp(point, radius: radius, inside: wallBounds)
        for obstacle in obstacles {
            if let contact = obstacleContact(at: position, radius: radius, obstacle: obstacle, bounds: bounds) {
                position = contact.position
            }
        }
        if let contact = cornerContact(at: position, radius: radius, bounds: wallBounds) {
            position = contact.position
        }
        return position
    }

    private func boundaryBounds(inside bounds: CGRect, obstacles: [CGRect]) -> CGRect {
        // A full-width or full-height Dock strip becomes the floor or side wall,
        // so its junction with the screen gets the same rounded corner.
        var minX = bounds.minX
        var maxX = bounds.maxX
        var minY = bounds.minY
        for obstacle in obstacles where !obstacle.isEmpty {
            if obstacle.minX <= bounds.minX && obstacle.maxX >= bounds.maxX &&
                obstacle.minY <= bounds.minY && obstacle.maxY < bounds.maxY {
                minY = max(minY, obstacle.maxY)
            }
            if obstacle.minY <= bounds.minY && obstacle.maxY >= bounds.maxY {
                if obstacle.minX <= bounds.minX && obstacle.maxX < bounds.maxX {
                    minX = max(minX, obstacle.maxX)
                } else if obstacle.maxX >= bounds.maxX && obstacle.minX > bounds.minX {
                    maxX = min(maxX, obstacle.minX)
                }
            }
        }
        guard minX < maxX && minY < bounds.maxY else { return bounds }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: bounds.maxY - minY)
    }

    private func cornerContact(
        at point: CGPoint, radius: CGFloat, bounds: CGRect
    ) -> (position: CGPoint, normal: CGVector)? {
        let width = bounds.width - 2 * radius
        let height = bounds.height - 2 * radius
        guard width > 0 && height > 0 else { return nil }
        // Quarter-circle ramps join all four edges smoothly. Scale the original
        // corner radius down by 20%, including in small simulation regions.
        let curveRadius = min(radius * 2, width / 2, height / 2) * 0.8
        let bottomCenterY = bounds.minY + radius + curveRadius
        let topCenterY = bounds.maxY - radius - curveRadius
        let centerY: CGFloat
        if point.y < bottomCenterY {
            centerY = bottomCenterY
        } else if point.y > topCenterY {
            centerY = topCenterY
        } else {
            return nil
        }
        let leftCenterX = bounds.minX + radius + curveRadius
        let rightCenterX = bounds.maxX - radius - curveRadius
        let centerX: CGFloat
        if point.x < leftCenterX {
            centerX = leftCenterX
        } else if point.x > rightCenterX {
            centerX = rightCenterX
        } else {
            return nil
        }
        let delta = CGVector(dx: point.x - centerX, dy: point.y - centerY)
        guard delta.squaredLength > curveRadius * curveRadius else { return nil }
        let outward = delta.normalized
        return (
            CGPoint(x: centerX + outward.dx * curveRadius, y: centerY + outward.dy * curveRadius),
            -outward
        )
    }

    private func obstacleContact(
        at point: CGPoint, radius: CGFloat, obstacle: CGRect, bounds: CGRect
    ) -> (position: CGPoint, normal: CGVector)? {
        guard !obstacle.isEmpty else { return nil }
        let closest = CGPoint(
            x: min(max(point.x, obstacle.minX), obstacle.maxX),
            y: min(max(point.y, obstacle.minY), obstacle.maxY)
        )
        let delta = CGVector(dx: point.x - closest.x, dy: point.y - closest.y)
        guard delta.squaredLength < radius * radius else { return nil }

        // Only project toward exits that keep the whole ball on screen. This
        // also recovers balls caught inside a Dock that appeared or grew.
        let allowed = bounds.insetBy(dx: radius, dy: radius)
        func fits(_ position: CGPoint) -> Bool {
            position.x >= allowed.minX && position.x <= allowed.maxX &&
                position.y >= allowed.minY && position.y <= allowed.maxY
        }
        if delta.squaredLength > 0.0001 {
            let normal = delta.normalized
            let position = CGPoint(x: closest.x + normal.dx * radius, y: closest.y + normal.dy * radius)
            if fits(position) { return (position, normal) }
        }

        let exits: [(position: CGPoint, normal: CGVector)] = [
            (CGPoint(x: point.x, y: obstacle.maxY + radius), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: obstacle.maxX + radius, y: point.y), CGVector(dx: 1, dy: 0)),
            (CGPoint(x: obstacle.minX - radius, y: point.y), CGVector(dx: -1, dy: 0)),
            (CGPoint(x: point.x, y: obstacle.minY - radius), CGVector(dx: 0, dy: -1))
        ]
        return exits.filter { fits($0.position) }.min {
            CGVector(dx: $0.position.x - point.x, dy: $0.position.y - point.y).squaredLength <
                CGVector(dx: $1.position.x - point.x, dy: $1.position.y - point.y).squaredLength
        }
    }
}

private extension CGVector {
    static prefix func - (vector: CGVector) -> CGVector {
        CGVector(dx: -vector.dx, dy: -vector.dy)
    }

    static func - (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy)
    }

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }

    static func / (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx / rhs, dy: lhs.dy / rhs)
    }

    var squaredLength: CGFloat { dx * dx + dy * dy }
    var length: CGFloat { sqrt(squaredLength) }
    var normalized: CGVector { self / max(length, 0.0001) }

    func dot(_ other: CGVector) -> CGFloat {
        dx * other.dx + dy * other.dy
    }

    func limited(to maximum: CGFloat) -> CGVector {
        guard squaredLength > maximum * maximum else { return self }
        return normalized * maximum
    }
}

private extension CGFloat {
    var scalarSign: CGFloat { self < 0 ? -1 : 1 }
}
