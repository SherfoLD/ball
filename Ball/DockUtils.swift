import AppKit

/// Screen-space Dock geometry. AppKit coordinates have their origin at the
/// bottom left; Window Server coordinates start at the primary display's top left.
struct DockGeometry {
    enum Position {
        case bottom, left, right
    }

    let rect: CGRect
    let position: Position

    /// visibleFrame tells us the Dock's thickness, but not its length. Ignore
    /// the top inset (menu bar) and the one-point auto-hide activation strip.
    static func reservedArea(frame: CGRect, visibleFrame: CGRect) -> DockGeometry? {
        let bottom = visibleFrame.minY - frame.minY
        let left = visibleFrame.minX - frame.minX
        let right = frame.maxX - visibleFrame.maxX
        if bottom > 1 {
            return DockGeometry(rect: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: bottom), position: .bottom)
        }
        if left > 1 {
            return DockGeometry(rect: CGRect(x: frame.minX, y: frame.minY, width: left, height: frame.height), position: .left)
        }
        if right > 1 {
            return DockGeometry(rect: CGRect(x: visibleFrame.maxX, y: frame.minY, width: right, height: frame.height), position: .right)
        }
        return nil
    }

    static func appKitRect(from windowRect: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: windowRect.minX, y: primaryScreenTop - windowRect.maxY, width: windowRect.width, height: windowRect.height)
    }

    /// Some macOS versions expose a tight Dock window; others report a
    /// full-screen surface. Never use that as an obstacle.
    static func windowArea(_ rect: CGRect, on frame: CGRect) -> DockGeometry? {
        let clipped = rect.intersection(frame)
        guard !clipped.isEmpty, !clipped.isNull else { return nil }
        if clipped.width > clipped.height, clipped.height > 1, clipped.height < frame.height / 2,
           abs(clipped.minY - frame.minY) <= 1 {
            return DockGeometry(rect: clipped, position: .bottom)
        }
        if clipped.height > clipped.width, clipped.width > 1, clipped.width < frame.width / 2 {
            if abs(clipped.minX - frame.minX) <= 1 {
                return DockGeometry(rect: clipped, position: .left)
            }
            if abs(clipped.maxX - frame.maxX) <= 1 {
                return DockGeometry(rect: clipped, position: .right)
            }
        }
        return nil
    }
}

/// Query at most ten times per second, independent of the 240 Hz physics step.
/// Bounds and owner PID are sufficient; no window titles, screenshots or
/// Accessibility permission are needed.
final class DockGeometryTracker {
    private var nextRefresh: TimeInterval = 0
    private var windowRects: [CGRect] = []

    func invalidate() {
        nextRefresh = 0
    }

    func geometry(on screen: NSScreen, at time: TimeInterval) -> DockGeometry? {
        if time >= nextRefresh {
            nextRefresh = time + 0.1
            windowRects = Self.readWindowRects()
        }
        let reserved = DockGeometry.reservedArea(frame: screen.frame, visibleFrame: screen.visibleFrame)
        let measured = windowRects.compactMap { DockGeometry.windowArea($0, on: screen.frame) }
            .filter { reserved == nil || $0.position == reserved?.position }
            .max { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
        return measured ?? reserved
    }

    private static func readWindowRects() -> [CGRect] {
        guard let primary = NSScreen.screens.first,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber, pid.int32Value == dock.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? NSNumber, layer.int32Value == CGWindowLevelForKey(.dockWindow),
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return DockGeometry.appKitRect(from: rect, primaryScreenTop: primary.frame.maxY)
        }
    }
}

extension NSScreen {
    var inferredRectOfHoveredDockIcon: CGRect {
        let geometry = DockGeometryTracker().geometry(on: self, at: 0)
        let position = geometry?.position ?? .bottom
        let thickness: CGFloat
        switch position {
        case .bottom: thickness = geometry?.rect.height ?? 79
        case .left, .right: thickness = geometry?.rect.width ?? 79
        }
        let tileSize = thickness * (64.0 / 79.0)
        var center = NSEvent.mouseLocation
        // Retain the click-based icon estimate for the launch animation.
        let inset = tileSize / 2 + 2.5 / 79 * thickness
        switch position {
        case .bottom: center.y = frame.minY + inset
        case .left: center.x = frame.minX + inset
        case .right: center.x = frame.maxX - inset
        }
        return CGRect(x: center.x - tileSize / 2, y: center.y - tileSize / 2, width: tileSize, height: tileSize)
    }
}
