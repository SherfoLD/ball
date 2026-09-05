import CoreGraphics

// Only rendering is replaced: the harness compiles the production solver and
// Dock geometry directly, without loading textures, audio or SpriteKit scenes.
final class Ball {
    let id: String
    let radius: CGFloat
    var position: CGPoint
    var simulationVelocity = CGVector.zero
    var beingDragged = false
    var participatesInSimulation = true
    var inverseMass: CGFloat { 1 / (radius * radius) }

    init(_ x: CGFloat, _ y: CGFloat, radius: CGFloat = 50, id: String = "ball") {
        self.id = id
        self.radius = radius
        position = CGPoint(x: x, y: y)
    }
}
