# Ball

Ball is a small macOS app that puts a bouncy ball in your Dock. Click the app’s Dock icon to launch a ball onto the screen, then drag it, flick it, or swipe it with two fingers.

Launch it again to add another ball. Each new ball gets a random color, and the balls collide with one another, the edges of the screen, and the Dock. Leave a few running and they settle into a surprisingly satisfying little pile.

[Watch the demo](balls.mp4)

**Download the latest build from [Releases](https://github.com/SherfoLD/ball/releases).**

## Build and run

Open `Ball.xcodeproj` in Xcode and run the `Ball` target. The app is sandboxed and does not need any extra permissions.

To run the headless Dock geometry and physics checks on macOS:

```sh
./Tests/run.sh
```

## Credits

This project started as [Nate Parrott’s original Ball app](https://github.com/nate-parrott/ball). The idea was inspired by [Nate Heagy’s](https://heagy.com/) OS X Dashboard widget, which the original author remembers from an elementary-school eMac. This version builds on that idea with multiple colored balls and ball-to-ball collisions.

The Dock-positioning work also builds on [Wessley Roche’s Gist](https://gist.github.com/wonderbit/c8896ff429a858021a7623f312dcdbf9), with further changes in [`DockUtils.swift`](Ball/DockUtils.swift).

## License

See [LICENSE](LICENSE).
