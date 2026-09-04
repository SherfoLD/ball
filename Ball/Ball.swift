import SpriteKit
import CoreImage

class Ball: SKNode {
    enum Color: CaseIterable {
        case red
        case orange
        case yellow
        case green
        case blue
        case purple
        case pink

        fileprivate var monochromeColor: CIColor {
            switch self {
            case .red: CIColor(red: 0.98, green: 0.12, blue: 0.12)
            case .orange: CIColor(red: 1.00, green: 0.42, blue: 0.05)
            case .yellow: CIColor(red: 1.00, green: 0.84, blue: 0.05)
            case .green: CIColor(red: 0.12, green: 0.78, blue: 0.25)
            case .blue: CIColor(red: 0.05, green: 0.42, blue: 0.96)
            case .purple: CIColor(red: 0.58, green: 0.20, blue: 0.93)
            case .pink: CIColor(red: 1.00, green: 0.20, blue: 0.55)
            }
        }
    }

    let id: String

    private let imgOffsetContainer = SKNode()
    /**/ private let imgRotationContainer = SKNode()
    /****/ private let colorEffect = SKEffectNode()
    /********/ private let img = SKSpriteNode(imageNamed: "Ball")

    let radius: CGFloat
    var simulationVelocity = CGVector.zero
    var participatesInSimulation = true

    /// Area-based mass keeps momentum correct if differently sized balls are
    /// introduced later. The common factor (pi and density) cancels out.
    var inverseMass: CGFloat { 1 / (radius * radius) }

//    let view: NSHostingView<BallView<Circle>>
    private let shadowSprite = SKSpriteNode(imageNamed: "ContactShadow")
    private let shadowContainer = SKNode() // For fading in/out

    private let squish = MomentumValue(initialValue: 1, scale: 1000, params: .init(response: 0.3, dampingRatio: 0.5))
    private let dragScale = MomentumValue(initialValue: 1, scale: 1000, params: .init(response: 0.2, dampingRatio: 0.8))

    var beingDragged = false {
        didSet(old) {
            if beingDragged != old {
                dragScale.animate(toValue: beingDragged ? 1.05 : 1, velocity: dragScale.velocity, completion: nil)
            }
        }
    }

    init(radius: CGFloat, pos: CGPoint, id: String, color: Color) {
//        self.view = NSHostingView(rootView: BallView(shape: Circle(), radius: radius, color: Color(hex: 0xF84E35)))
//        self.view.frame = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        self.id = id
        self.radius = radius
        super.init()
        self.position = pos

        addChild(shadowContainer)
        shadowContainer.addChild(shadowSprite)
        let shadowWidth: CGFloat = radius * 4
        shadowSprite.size = CGSize(width: shadowWidth, height: 0.564 * shadowWidth)
        shadowSprite.alpha = 0
        shadowContainer.alpha = 0

        addChild(imgOffsetContainer)
        imgOffsetContainer.addChild(imgRotationContainer)
        imgRotationContainer.addChild(colorEffect)

        colorEffect.filter = CIFilter(
            name: "CIColorMonochrome",
            parameters: [
                kCIInputColorKey: color.monochromeColor,
                kCIInputIntensityKey: 1.0,
            ]
        )
        colorEffect.shouldRasterize = true

        img.size = CGSize(width: radius * 2, height: radius * 2)
        colorEffect.addChild(img)
//        img.alpha = 0.01
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var rect: CGRect {
        CGRect(origin: .init(x: position.x - radius, y: position.y - radius), size: .init(width: radius * 2, height: radius * 2))
    }

    func animateShadow(visible: Bool, duration: TimeInterval) {
        if visible {
            shadowContainer.run(SKAction.fadeIn(withDuration: duration))
        } else {
            shadowContainer.run(SKAction.fadeOut(withDuration: duration))
        }
    }

    func update() {
        shadowSprite.position = CGPoint(x: 0, y: radius * 0.3 - position.y)
        let distFromBottom = position.y - radius
        shadowSprite.alpha = remap(x: distFromBottom, domainStart: 0, domainEnd: 200, rangeStart: 1, rangeEnd: 0)
        imgRotationContainer.xScale = squish.value

        let yDelta = -(1 - imgRotationContainer.xScale) * radius / 2
        imgOffsetContainer.position = .init(x: 0, y: yDelta)

        img.setScale(dragScale.value)
    }

    func didCollide(strength: Double, normal: CGVector) {
        let angle = atan2(normal.dy, normal.dx)
        imgRotationContainer.zRotation = angle
        img.zRotation = -angle

        let targetScale = remap(x: strength, domainStart: 0, domainEnd: 1, rangeStart: 1, rangeEnd: 0.98)
        let velocity = remap(x: strength, domainStart: 0, domainEnd: 1, rangeStart: -0.5, rangeEnd: -1)
        squish.animate(toValue: targetScale, velocity: velocity) { [weak self] finished in
            guard finished, let self else { return }
            self.squish.animate(toValue: 1, velocity: self.squish.velocity, completion: nil)
        }
    }
}
