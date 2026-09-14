# Ball

Bouncy balls on your desktop with proper physics and collisions.

![Screen recording of a balls bouncing](balls.gif)

**Download the latest build from [Releases](https://github.com/SherfoLD/ball/releases).**

Then remove quarantine from the app:

```sh
xattr -cr /Applications/Ball.app
```

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
